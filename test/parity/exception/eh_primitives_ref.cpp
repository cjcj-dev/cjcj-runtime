#define private public
#include "Exception/EhTable.h"
#include "Exception/EhFrameInfo.h"
#include "Exception/CalleeSavedRegisterContext.h"
#include "Exception/Exception.h"
#undef private

#include <cstddef>
#include <cstdint>
#include <cstdio>

using MapleRuntime::EHTable;
using MapleRuntime::ScanResult;
using MapleRuntime::EHFrameInfo;

static void Emit(const char* name, const uint8_t* bytes)
{
    const uint8_t* cursor = bytes;
    const uint8_t* start = cursor;
    const uint64_t value = EHTable::ReadULEB128(&cursor);
    std::printf("ULEB %s %llu %zu\n", name,
        static_cast<unsigned long long>(value), static_cast<size_t>(cursor - start));
}

static void EmitSigned(const char* name, const uint8_t* bytes)
{
    const uint8_t* cursor = bytes;
    const uint8_t* start = cursor;
    const int64_t value = EHTable::ReadSLEB128(&cursor);
    std::printf("SLEB %s %lld %zu\n", name,
        static_cast<long long>(value), static_cast<size_t>(cursor - start));
}

static void EmitFrame(const char* name, const uint8_t* bytes, uint32_t initialPos)
{
    MapleRuntime::Uptr* cursor = reinterpret_cast<MapleRuntime::Uptr*>(const_cast<uint8_t*>(bytes));
    MapleRuntime::Uptr* start = cursor;
    uint32_t validPos = initialPos;
    const uint32_t value = EHFrameInfo::ReadVarInt(&cursor, validPos);
    std::printf("FRAME %s %u %zu %u\n", name, value,
        static_cast<size_t>(reinterpret_cast<uint8_t*>(cursor) - reinterpret_cast<uint8_t*>(start)), validPos);
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
    const uint8_t slebZero[] = {0x00}; EmitSigned("zero", slebZero);
    const uint8_t slebMinus1[] = {0x7f}; EmitSigned("minus1", slebMinus1);
    const uint8_t sleb63[] = {0x3f}; EmitSigned("63", sleb63);
    const uint8_t slebMinus64[] = {0x40}; EmitSigned("minus64", slebMinus64);
    const uint8_t sleb64[] = {0xc0, 0x00}; EmitSigned("64", sleb64);
    const uint8_t slebMinus65[] = {0xbf, 0x7f}; EmitSigned("minus65", slebMinus65);
    const uint8_t slebMinus624485[] = {0x9b, 0xf1, 0x59}; EmitSigned("minus624485", slebMinus624485);

    uint64_t pointerData[] = {8, 0x1122334455667788ULL, 0, 0};
    const uint8_t* pointerBase = reinterpret_cast<const uint8_t*>(pointerData);
    const uint8_t dummyLsda[] = {0, 0, 0, 0, 0};
    EHTable table(dummyLsda);
    std::printf("TREAD %llu %llu %llu %llu\n",
        static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(table.ReadAbsPtr(pointerBase + 8))),
        static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(table.ReadUData4(pointerBase + 8))),
        static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(table.ReadIndirPcRelSData4(pointerBase))),
        static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(table.ReadIndirPcRelSData8(pointerBase))));
    pointerData[0] = 0;
    std::printf("TREAD_ZERO %s\n", table.ReadIndirPcRelSData4(pointerBase) == nullptr ? "true" : "false");

    const uint8_t inlineNibble[] = {0xa5, 0, 0, 0, 0, 0, 0, 0};
    const uint8_t frame8[] = {0xbc, 0x0a, 0, 0, 0, 0, 0, 0};
    const uint8_t frame16[] = {0xd0, 0x34, 0x12, 0, 0, 0, 0, 0};
    const uint8_t frame24[] = {0xee, 0xde, 0xbc, 0x0a, 0, 0, 0, 0};
    const uint8_t frame32[] = {0xf0, 0x78, 0x56, 0x34, 0x12, 0, 0, 0};
    EmitFrame("inline_low", inlineNibble, 0); EmitFrame("inline_high", inlineNibble, 1);
    EmitFrame("u8_low", frame8, 0); EmitFrame("u16_high", frame16, 1);
    EmitFrame("u24_low", frame24, 0); EmitFrame("u32_high", frame32, 1);
    uint32_t tags[] = {0x55555555U, 0x12345678U};
    std::printf("ABNORMAL %s %s %s\n",
        EHTable::IsAbnormalEHTable(nullptr) ? "true" : "false",
        EHTable::IsAbnormalEHTable(reinterpret_cast<uint8_t*>(&tags[0])) ? "true" : "false",
        EHTable::IsAbnormalEHTable(reinterpret_cast<uint8_t*>(&tags[1])) ? "true" : "false");
    uint8_t lsda[32] = {};
    lsda[0] = 0; lsda[1] = static_cast<uint8_t>(EHTable::TTypeEncoding::ABS_PTR); lsda[2] = 26;
    lsda[3] = 0; lsda[4] = 8;
    lsda[5] = 0; lsda[6] = 4; lsda[7] = 16; lsda[8] = 0;
    lsda[9] = 4; lsda[10] = 4; lsda[11] = 32; lsda[12] = 1;
    lsda[13] = 1; lsda[14] = 0;
    EHTable scanTable(lsda);
    std::printf("EHTABLE %zu %zu %zu %zu %zu %zu %zu\n", sizeof(scanTable), alignof(EHTable),
        static_cast<size_t>(scanTable.callSiteTableStart - lsda),
        static_cast<size_t>(scanTable.callSiteTableEnd - lsda),
        static_cast<size_t>(scanTable.actionTableStart - lsda),
        static_cast<size_t>(scanTable.ttypeEncoding - lsda),
        static_cast<size_t>(scanTable.exceptionTypeStart - lsda));
    uint32_t code[16] = {};
    MapleRuntime::ExceptionWrapper wrapper;
    ScanResult cleanup{};
    scanTable.ScanEHTable(reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(code) + 3),
        wrapper, code, cleanup);
    ScanResult caught{};
    scanTable.ScanEHTable(reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(code) + 6),
        wrapper, code, caught);
    std::printf("EHSCAN %llu %llu %s %llu %llu %s\n",
        static_cast<unsigned long long>(cleanup.typeIndex),
        static_cast<unsigned long long>(cleanup.landingPad - reinterpret_cast<uintptr_t>(code)),
        cleanup.isCaught ? "true" : "false", static_cast<unsigned long long>(caught.typeIndex),
        static_cast<unsigned long long>(caught.landingPad - reinterpret_cast<uintptr_t>(code)),
        caught.isCaught ? "true" : "false");
    std::printf("CALLEE_CONTEXT %zu %zu\n", sizeof(MapleRuntime::CalleeSavedRegisterContext),
        alignof(MapleRuntime::CalleeSavedRegisterContext));
    return 0;
}
