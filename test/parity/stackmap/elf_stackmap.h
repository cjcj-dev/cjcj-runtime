#ifndef CJRT_ELF_STACKMAP_H
#define CJRT_ELF_STACKMAP_H

#include <elf.h>

#include <algorithm>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace cjrt::parity {

struct FunctionStackMap {
    uint32_t methodIndex;
    uint32_t codeSize;
    uint64_t sectionOffset;
    std::vector<uint8_t> bytes;
};

struct ObjectStackMaps {
    std::string path;
    bool stackGrow;
    std::vector<FunctionStackMap> functions;
};

inline std::string BaseName(const std::string& path)
{
    const auto slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

template <class T>
inline const T* At(const std::vector<uint8_t>& file, uint64_t offset, uint64_t count = 1)
{
    if (offset > file.size() || count > (file.size() - offset) / sizeof(T)) {
        throw std::runtime_error("truncated ELF structure");
    }
    return reinterpret_cast<const T*>(file.data() + offset);
}

inline ObjectStackMaps ReadObjectStackMaps(const std::string& path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("cannot open " + path);
    }
    input.seekg(0, std::ios::end);
    const auto length = input.tellg();
    if (length < 0) {
        throw std::runtime_error("cannot size " + path);
    }
    input.seekg(0, std::ios::beg);
    std::vector<uint8_t> file(static_cast<size_t>(length));
    input.read(reinterpret_cast<char*>(file.data()), length);
    if (!input) {
        throw std::runtime_error("cannot read " + path);
    }

    const auto* eh = At<Elf64_Ehdr>(file, 0);
    if (std::memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 || eh->e_ident[EI_CLASS] != ELFCLASS64 ||
        eh->e_ident[EI_DATA] != ELFDATA2LSB || eh->e_type != ET_REL || eh->e_machine != EM_X86_64 ||
        eh->e_shentsize != sizeof(Elf64_Shdr) || eh->e_shstrndx >= eh->e_shnum) {
        throw std::runtime_error("unsupported ELF object " + path);
    }
    const auto* sections = At<Elf64_Shdr>(file, eh->e_shoff, eh->e_shnum);
    const auto& shstr = sections[eh->e_shstrndx];
    const auto* names = At<char>(file, shstr.sh_offset, shstr.sh_size);

    auto findSection = [&](const char* wanted) -> uint32_t {
        for (uint32_t i = 0; i < eh->e_shnum; ++i) {
            if (sections[i].sh_name < shstr.sh_size && std::strcmp(names + sections[i].sh_name, wanted) == 0) {
                return i;
            }
        }
        throw std::runtime_error(std::string("missing section ") + wanted + " in " + path);
    };

    const uint32_t stackMapIndex = findSection(".cjmetadata.stackmap");
    const uint32_t methodIndex = findSection(".cjmetadata.methodinfo");
    const uint32_t gcFlagsIndex = findSection(".cjmetadata.gcflags");
    const auto& stackMapSection = sections[stackMapIndex];
    const auto& methodSection = sections[methodIndex];
    const auto& gcFlagsSection = sections[gcFlagsIndex];
    if (methodSection.sh_size % 28 != 0 || gcFlagsSection.sh_size < 3) {
        throw std::runtime_error("malformed Cangjie metadata in " + path);
    }
    const auto* methodBytes = At<uint8_t>(file, methodSection.sh_offset, methodSection.sh_size);
    const auto* gcFlags = At<uint8_t>(file, gcFlagsSection.sh_offset, gcFlagsSection.sh_size);

    const Elf64_Shdr* relocationSection = nullptr;
    for (uint32_t i = 0; i < eh->e_shnum; ++i) {
        if (sections[i].sh_type == SHT_RELA && sections[i].sh_info == methodIndex) {
            relocationSection = &sections[i];
            break;
        }
    }
    if (relocationSection == nullptr || relocationSection->sh_entsize != sizeof(Elf64_Rela) ||
        relocationSection->sh_link >= eh->e_shnum) {
        throw std::runtime_error("missing methodinfo relocations in " + path);
    }
    const auto& symbolSection = sections[relocationSection->sh_link];
    if (symbolSection.sh_entsize != sizeof(Elf64_Sym)) {
        throw std::runtime_error("malformed ELF symbols in " + path);
    }
    const auto* symbols = At<Elf64_Sym>(file, symbolSection.sh_offset,
                                        symbolSection.sh_size / sizeof(Elf64_Sym));
    const uint64_t symbolCount = symbolSection.sh_size / sizeof(Elf64_Sym);
    const auto* relocations = At<Elf64_Rela>(file, relocationSection->sh_offset,
        relocationSection->sh_size / sizeof(Elf64_Rela));
    const uint64_t relocationCount = relocationSection->sh_size / sizeof(Elf64_Rela);

    struct LocatedFunction {
        uint32_t methodIndex;
        uint32_t codeSize;
        uint64_t stackMapOffset;
    };
    std::vector<LocatedFunction> located;
    for (uint64_t i = 0; i < relocationCount; ++i) {
        const auto& relocation = relocations[i];
        const uint64_t symbolIndex = ELF64_R_SYM(relocation.r_info);
        if (symbolIndex >= symbolCount || symbols[symbolIndex].st_shndx != stackMapIndex ||
            relocation.r_offset % 28 != 0 || relocation.r_offset >= methodSection.sh_size) {
            continue;
        }
        const uint64_t offset = symbols[symbolIndex].st_value + relocation.r_addend;
        if (offset >= stackMapSection.sh_size) {
            throw std::runtime_error("stack-map relocation is out of range in " + path);
        }
        uint32_t codeSize = 0;
        std::memcpy(&codeSize, methodBytes + relocation.r_offset + 4, sizeof(codeSize));
        located.push_back({static_cast<uint32_t>(relocation.r_offset / 28), codeSize, offset});
    }
    std::sort(located.begin(), located.end(), [](const auto& left, const auto& right) {
        return left.methodIndex < right.methodIndex;
    });
    if (located.size() != methodSection.sh_size / 28) {
        throw std::runtime_error("not every method has a stack-map relocation in " + path);
    }

    ObjectStackMaps result{path, gcFlags[2] != 0, {}};
    const auto* stackMapBytes = At<uint8_t>(file, stackMapSection.sh_offset, stackMapSection.sh_size);
    for (const auto& function : located) {
        result.functions.push_back({function.methodIndex, function.codeSize, function.stackMapOffset,
            std::vector<uint8_t>(stackMapBytes + function.stackMapOffset,
                                 stackMapBytes + stackMapSection.sh_size)});
    }
    return result;
}

inline void PrintEvent(const StackMapEvent& event)
{
    std::printf("E %u %u %lld %lld\n", event.kind, event.row,
                static_cast<long long>(event.value0), static_cast<long long>(event.value1));
}

} // namespace cjrt::parity

#endif
