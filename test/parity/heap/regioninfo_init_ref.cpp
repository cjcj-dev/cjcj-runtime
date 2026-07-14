#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <list>
#include <map>
#include <set>
#include <thread>
#include <vector>

// Execute the original production implementation. Exposing the private record
// only lets the oracle print the live layout and every resulting byte.
#define private public
#include "Heap/Allocator/RegionInfo.h"
#undef private

using MapleRuntime::RegionInfo;

namespace MapleRuntime {
const size_t RegionInfo::UNIT_SIZE = 4096;
const size_t RegionInfo::LARGE_OBJECT_DEFAULT_THRESHOLD = 8 * RegionInfo::UNIT_SIZE;
size_t RegionInfo::UnitInfo::totalUnitCount = 0;
uintptr_t RegionInfo::UnitInfo::heapStartAddress = 0;
}

static constexpr uint8_t SENTINEL = 0xa5;
static constexpr size_t TOTAL_UNITS = 10;

static uint8_t* ByteRecord(size_t idx)
{
    return reinterpret_cast<uint8_t*>(RegionInfo::UnitInfo::GetUnitInfo(idx));
}

static uint64_t ReadU64(const uint8_t* address)
{
    uint64_t value;
    std::memcpy(&value, address, sizeof(value));
    return value;
}

static void DumpCanonicalRecord(size_t idx, bool primary, size_t endIdx, int ownerIdx)
{
    const uint8_t* bytes = ByteRecord(idx);
    uint64_t alloc = ReadU64(bytes);
    uint64_t end = ReadU64(bytes + 8);
    uint64_t live = ReadU64(bytes + 32);
    if (primary) {
        alloc = idx;
        end = endIdx;
    }
    if (ownerIdx >= 0) {
        live = static_cast<uint64_t>(ownerIdx);
    }
    std::printf("P %zu %llu %llu %llu\n", idx, static_cast<unsigned long long>(alloc),
                static_cast<unsigned long long>(end), static_cast<unsigned long long>(live));
    for (size_t offset = 16; offset < 32; ++offset) {
        std::printf("B %zu %zu %u\n", idx, offset, bytes[offset]);
    }
    for (size_t offset = 40; offset < sizeof(RegionInfo::UnitMetadata); ++offset) {
        std::printf("B %zu %zu %u\n", idx, offset, bytes[offset]);
    }
}

static void DumpUntouched(size_t idx, bool primary, bool subordinate)
{
    const uint8_t* bytes = ByteRecord(idx);
    for (size_t offset = 0; offset < sizeof(RegionInfo::UnitMetadata); ++offset) {
        bool untouched = false;
        if (primary) {
            untouched = (offset >= 40 && offset <= 75) || offset == 77 || offset >= 80;
        } else if (subordinate) {
            untouched = !(offset >= 32 && offset <= 39) && offset != 76;
        } else {
            untouched = true;
        }
        if (untouched) {
            std::printf("U %zu %zu %u\n", idx, offset, bytes[offset]);
        }
    }
}

static void DumpPrimaryFields(const char* name, size_t idx, size_t endIdx)
{
    auto* region = RegionInfo::GetRegionInfo(static_cast<uint32_t>(idx));
    auto& metadata = reinterpret_cast<RegionInfo::UnitInfo*>(region)->GetMetadata();
    std::printf("F %s alloc %zu\n", name, idx);
    std::printf("F %s end %zu\n", name, endIdx);
    std::printf("F %s next %u\n", name, metadata.nextRegionIdx);
    std::printf("F %s prev %u\n", name, metadata.prevRegionIdx);
    std::printf("F %s liveByteCount %u\n", name, metadata.liveByteCount);
    std::printf("F %s liveInfo %u\n", name, metadata.liveInfo == nullptr ? 0U : 1U);
    std::printf("F %s regionType %u\n", name, static_cast<unsigned>(region->GetRegionType()));
    std::printf("F %s unitRole %u\n", name, static_cast<unsigned>(region->GetUnitRole()));
    std::printf("F %s trace %u\n", name, static_cast<unsigned>(metadata.isTraceRegion));
    std::printf("F %s marked %u\n", name, static_cast<unsigned>(metadata.isMarked));
    std::printf("F %s enqueued %u\n", name, static_cast<unsigned>(metadata.isEnqueued));
    std::printf("F %s resurrected %u\n", name, static_cast<unsigned>(metadata.isResurrected));
    std::printf("F %s raw %d\n", name, metadata.rawPointerObjectCount);
}

int main()
{
    MapleRuntime::BitField<uint8_t> bit8{};
    MapleRuntime::BitField<uint16_t> bit16{};
    MapleRuntime::RwLock rwlock;
    MapleRuntime::RouteInfo route;
    std::printf("REGIONINFO_ABI bit8_size=%zu bit8_align=%zu bit8_fieldVal=%zu bit8_value=%u "
                "bit16_size=%zu bit16_align=%zu bit16_fieldVal=%zu bit16_value=%u "
                "rwlock_size=%zu rwlock_align=%zu rwlock_value=%d "
                "route_size=%zu route_align=%zu route_to1=%zu route_used=%zu route_to2=%zu "
                "unitinfo_size=%zu unitinfo_align=%zu unitinfo_metadata=%zu "
                "regioninfo_size=%zu regioninfo_align=%zu regioninfo_metadata=%zu\n",
                sizeof(bit8), alignof(decltype(bit8)), offsetof(decltype(bit8), fieldVal),
                static_cast<unsigned>(bit8.fieldVal), sizeof(bit16), alignof(decltype(bit16)),
                offsetof(decltype(bit16), fieldVal), static_cast<unsigned>(bit16.fieldVal),
                sizeof(rwlock), alignof(decltype(rwlock)), rwlock.lockCount.load(),
                sizeof(route), alignof(decltype(route)), offsetof(decltype(route), toRegion1StartAddress),
                offsetof(decltype(route), toRegion1UsedBytes), offsetof(decltype(route), toRegion2Idx),
                sizeof(RegionInfo::UnitInfo), alignof(RegionInfo::UnitInfo),
                offsetof(RegionInfo::UnitInfo, metadata), sizeof(RegionInfo), alignof(RegionInfo),
                offsetof(RegionInfo, metadata));
    std::printf("REGIONINFO_LAYOUT sizeof=%zu allocPtr=%zu regionEnd=%zu nextRegionIdx=%zu "
                "prevRegionIdx=%zu liveByteCount=%zu rawPointerObjectCount=%zu liveInfo=%zu "
                "liveInfo0=%zu regionEnd0=%zu routeInfo=%zu nextRegionIdx0=%zu unitRoleBitField=%zu "
                "regionStateBitField=%zu routeState=%zu rwLock=%zu\n",
                sizeof(RegionInfo::UnitMetadata), offsetof(RegionInfo::UnitMetadata, allocPtr),
                offsetof(RegionInfo::UnitMetadata, regionEnd),
                offsetof(RegionInfo::UnitMetadata, nextRegionIdx),
                offsetof(RegionInfo::UnitMetadata, prevRegionIdx),
                offsetof(RegionInfo::UnitMetadata, liveByteCount),
                offsetof(RegionInfo::UnitMetadata, rawPointerObjectCount),
                offsetof(RegionInfo::UnitMetadata, liveInfo),
                offsetof(RegionInfo::UnitMetadata, liveInfo0),
                offsetof(RegionInfo::UnitMetadata, regionEnd0),
                offsetof(RegionInfo::UnitMetadata, routeInfo),
                offsetof(RegionInfo::UnitMetadata, nextRegionIdx0),
                offsetof(RegionInfo::UnitMetadata, unitRoleBitField),
                offsetof(RegionInfo::UnitMetadata, regionStateBitField),
                offsetof(RegionInfo::UnitMetadata, routeState), offsetof(RegionInfo::UnitMetadata, rwLock));

    const size_t metadataBytes = TOTAL_UNITS * sizeof(RegionInfo::UnitInfo);
    const size_t heapBytes = TOTAL_UNITS * RegionInfo::UNIT_SIZE;
    auto* storage = static_cast<uint8_t*>(std::malloc(metadataBytes + heapBytes));
    if (storage == nullptr) {
        return 2;
    }
    std::memset(storage, SENTINEL, metadataBytes + heapBytes);
    const uintptr_t heapAddress = reinterpret_cast<uintptr_t>(storage + metadataBytes);
    RegionInfo::Initialize(TOTAL_UNITS, heapAddress);

    std::puts("C free 1 3");
    RegionInfo::InitFreeRegion(1, 3);
    std::puts("C small 4 2");
    RegionInfo* small = RegionInfo::InitRegion(4, 2, RegionInfo::UnitRole::SMALL_SIZED_UNITS);
    std::puts("C largeAt 7 1");
    RegionInfo* large = RegionInfo::InitRegionAt(heapAddress + 7 * RegionInfo::UNIT_SIZE, 1,
                                                 RegionInfo::UnitRole::LARGE_SIZED_UNITS);

    DumpPrimaryFields("free", 1, 4);
    DumpPrimaryFields("small", 4, 6);
    DumpPrimaryFields("largeAt", 7, 8);
    auto& subordinate = RegionInfo::UnitInfo::GetUnitInfo(5)->GetMetadata();
    const size_t ownerIdx = RegionInfo::UnitInfo::GetUnitIdx(
        reinterpret_cast<RegionInfo::UnitInfo*>(subordinate.ownerRegion));
    std::printf("F subordinate unitRole %u\n", static_cast<unsigned>(subordinate.unitRole));
    std::printf("F subordinate owner %zu\n", ownerIdx);
    std::printf("S 5 %zu %u\n", ownerIdx, static_cast<unsigned>(subordinate.unitRole));

    const size_t records[] = {1, 2, 3, 4, 5, 7, 9};
    for (size_t idx : records) {
        const bool primary = idx == 1 || idx == 4 || idx == 7;
        const bool isSubordinate = idx == 5;
        const size_t endIdx = idx == 1 ? 4 : (idx == 4 ? 6 : 8);
        DumpCanonicalRecord(idx, primary, endIdx, isSubordinate ? 4 : -1);
        DumpUntouched(idx, primary, isSubordinate);
    }

    for (size_t idx : {size_t{1}, size_t{4}, size_t{7}}) {
        auto* region = RegionInfo::GetRegionInfo(static_cast<uint32_t>(idx));
        auto& metadata = reinterpret_cast<RegionInfo::UnitInfo*>(region)->GetMetadata();
        std::printf("A %zu %u %u %u %u\n", idx,
                    static_cast<unsigned>(metadata.unitRoleBitField.fieldVal),
                    static_cast<unsigned>(metadata.regionStateBitField.fieldVal),
                    static_cast<unsigned>(region->GetUnitRole()),
                    static_cast<unsigned>(region->GetRegionType()));
    }

    for (size_t idx : {size_t{1}, size_t{5}, size_t{7}}) {
        const uintptr_t address = RegionInfo::GetUnitAddress(idx);
        const size_t addressIdx = (address - heapAddress) / RegionInfo::UNIT_SIZE;
        const size_t unitIdx = RegionInfo::UnitInfo::GetUnitIdx(RegionInfo::UnitInfo::GetUnitInfo(idx));
        const size_t regionIdx = RegionInfo::UnitInfo::GetUnitIdx(reinterpret_cast<RegionInfo::UnitInfo*>(
            RegionInfo::GetRegionInfoAt(address)));
        std::printf("M %zu %zu %zu %zu\n", idx, addressIdx, unitIdx, regionIdx);
    }

    const unsigned rootResult = static_cast<unsigned>(RegionInfo::GetRegionInfo(1)->GetUnitRole()) +
        static_cast<unsigned>(RegionInfo::GetRegionInfo(1)->GetRegionType()) +
        static_cast<unsigned>(small->GetUnitRole()) + static_cast<unsigned>(small->GetRegionType()) +
        static_cast<unsigned>(large->GetUnitRole()) + static_cast<unsigned>(large->GetRegionType());
    std::printf("ROOT_RESULT %u\n", rootResult);
    std::free(storage);
    return 0;
}
