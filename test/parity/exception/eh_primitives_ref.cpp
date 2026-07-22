#include "Exception/EhTable.h"

#include <cstddef>
#include <cstdint>
#include <cstdio>

using MapleRuntime::EHTable;
using MapleRuntime::ScanResult;

static void Emit(const char* name, const uint8_t* bytes)
{
    const uint8_t* cursor = bytes;
    const uint8_t* start = cursor;
    const uint64_t value = EHTable::ReadULEB128(&cursor);
    std::printf("ULEB %s %llu %zu\n", name,
        static_cast<unsigned long long>(value), static_cast<size_t>(cursor - start));
}

int main()
{
    ScanResult result{};
    std::printf("SCAN_RESULT %zu %zu %zu %zu %zu %llu %llu %s\n",
        sizeof(result), alignof(ScanResult), offsetof(ScanResult, typeIndex),
        offsetof(ScanResult, landingPad), offsetof(ScanResult, isCaught),
        static_cast<unsigned long long>(result.typeIndex),
        static_cast<unsigned long long>(result.landingPad), result.isCaught ? "true" : "false");
    std::printf("TTYPE %d %d %d %d\n",
        static_cast<int>(EHTable::TTypeEncoding::ABS_PTR),
        static_cast<int>(EHTable::TTypeEncoding::U_DATA_4),
        static_cast<int>(EHTable::TTypeEncoding::INDIR_PC_REL_S_DATA_4),
        static_cast<int>(EHTable::TTypeEncoding::INDIR_PC_REL_S_DATA_8));
    const uint8_t zero[] = {0x00}; Emit("zero", zero);
    const uint8_t one[] = {0x01}; Emit("one", one);
    const uint8_t v127[] = {0x7f}; Emit("127", v127);
    const uint8_t v128[] = {0x80, 0x01}; Emit("128", v128);
    const uint8_t v624485[] = {0xe5, 0x8e, 0x26}; Emit("624485", v624485);
    const uint8_t u32max[] = {0xff, 0xff, 0xff, 0xff, 0x0f}; Emit("u32max", u32max);
    const uint8_t u64max[] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01};
    Emit("u64max", u64max);
    uint32_t tags[] = {0x55555555U, 0x12345678U};
    std::printf("ABNORMAL %s %s %s\n",
        EHTable::IsAbnormalEHTable(nullptr) ? "true" : "false",
        EHTable::IsAbnormalEHTable(reinterpret_cast<uint8_t*>(&tags[0])) ? "true" : "false",
        EHTable::IsAbnormalEHTable(reinterpret_cast<uint8_t*>(&tags[1])) ? "true" : "false");
    return 0;
}
