#include "stackmap_api.h"
#include "elf_stackmap.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <string>
#include <vector>

struct CangjieDumpWork {
    const uint8_t* data;
    uint64_t size;
    uint32_t stackGrow;
    uint32_t reserved;
    StackMapEvent* events;
    uint64_t capacity;
    uint64_t* count;
    void* opaque;
};

namespace {
struct NativeWork {
    CangjieDumpWork abi{};
    std::string objectName;
    uint32_t objectFunctionCount{};
    bool firstInObject{};
    uint32_t methodIndex{};
    uint32_t codeSize{};
    uint64_t sectionOffset{};
    std::vector<uint8_t> bytes;
    std::vector<StackMapEvent> output;
    uint64_t count{};
    NativeWork* next{};
};

std::vector<std::unique_ptr<NativeWork>> workItems;
int32_t finalStatus = 0;

void LoadWork()
{
    const char* objectList = std::getenv("CJRT_STACKMAP_OBJECTS");
    if (objectList == nullptr || *objectList == '\0') {
        throw std::runtime_error("CJRT_STACKMAP_OBJECTS is empty");
    }
    std::string paths(objectList);
    size_t begin = 0;
    NativeWork* previous = nullptr;
    while (begin <= paths.size()) {
        const size_t end = paths.find(':', begin);
        const std::string path = paths.substr(begin, end == std::string::npos ? end : end - begin);
        if (path.empty()) {
            throw std::runtime_error("empty object path");
        }
        const auto object = cjrt::parity::ReadObjectStackMaps(path);
        bool first = true;
        for (const auto& function : object.functions) {
            auto work = std::make_unique<NativeWork>();
            work->objectName = cjrt::parity::BaseName(object.path);
            work->objectFunctionCount = static_cast<uint32_t>(object.functions.size());
            work->firstInObject = first;
            work->methodIndex = function.methodIndex;
            work->codeSize = function.codeSize;
            work->sectionOffset = function.sectionOffset;
            work->bytes = function.bytes;
            work->abi.data = work->bytes.data();
            work->abi.size = work->bytes.size();
            work->abi.stackGrow = object.stackGrow ? 1U : 0U;
            work->abi.count = &work->count;
            work->abi.opaque = work.get();
            if (previous != nullptr) {
                previous->next = work.get();
            }
            previous = work.get();
            workItems.push_back(std::move(work));
            first = false;
        }
        if (end == std::string::npos) {
            break;
        }
        begin = end + 1;
    }
}

NativeWork* Native(CangjieDumpWork* work)
{
    return work == nullptr ? nullptr : static_cast<NativeWork*>(work->opaque);
}
} // namespace

extern "C" CangjieDumpWork* CJRT_CangjieDumpFirst()
{
    try {
        if (workItems.empty()) {
            LoadWork();
        }
        return workItems.empty() ? nullptr : &workItems.front()->abi;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "stackmap Cangjie dump setup failed: %s\n", error.what());
        finalStatus = 1;
        return nullptr;
    }
}

extern "C" void CJRT_CangjieDumpPrepare(CangjieDumpWork* work)
{
    auto* native = Native(work);
    if (native == nullptr) {
        finalStatus = 1;
        return;
    }
    if (native->firstInObject) {
        std::printf("OBJECT %s %u %u\n", native->objectName.c_str(), native->objectFunctionCount,
                    native->abi.stackGrow);
    }
    std::printf("FUNCTION %u %llu %u\n", native->methodIndex,
                static_cast<unsigned long long>(native->sectionOffset), native->codeSize);
    native->count = 0;
    native->output.clear();
    native->abi.events = nullptr;
    native->abi.capacity = 0;
}

extern "C" void CJRT_CangjieDumpAllocate(CangjieDumpWork* work)
{
    auto* native = Native(work);
    if (native == nullptr) {
        finalStatus = 1;
        return;
    }
    native->output.resize(native->count);
    native->abi.events = native->output.data();
    native->abi.capacity = native->output.size();
    native->count = 0;
}

extern "C" CangjieDumpWork* CJRT_CangjieDumpFinish(CangjieDumpWork* work, int32_t status)
{
    auto* native = Native(work);
    if (native == nullptr || status != 0 || native->count != native->output.size()) {
        std::fprintf(stderr, "stackmap Cangjie decode failed: status=%d count=%llu expected=%zu\n", status,
                     static_cast<unsigned long long>(native == nullptr ? 0 : native->count),
                     native == nullptr ? 0 : native->output.size());
        finalStatus = 1;
        return nullptr;
    }
    for (const auto& event : native->output) {
        cjrt::parity::PrintEvent(event);
    }
    return native->next == nullptr ? nullptr : &native->next->abi;
}

extern "C" int32_t CJRT_CangjieDumpStatus()
{
    return finalStatus;
}
