#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

#include "Heap/Allocator/RegionInfo.h"
#include "Heap/Collector/LiveInfo.h"

using namespace MapleRuntime;

namespace MapleRuntime {
const size_t RegionInfo::UNIT_SIZE = 4096;
const size_t RegionInfo::LARGE_OBJECT_DEFAULT_THRESHOLD = 8 * RegionInfo::UNIT_SIZE;
size_t RegionInfo::UnitInfo::totalUnitCount = 0;
uintptr_t RegionInfo::UnitInfo::heapStartAddress = 0;
}

static void CheckMarked(bool large, int64_t markedOffset, size_t queryOffset)
{
    constexpr size_t unitCount = 10;
    // RegionInfo.h:65: sizeof(RegionInfo) must equal sizeof(UnitInfo).
    const size_t metadataSize = unitCount * sizeof(RegionInfo);
    auto* arena = static_cast<uint8_t*>(std::malloc(metadataSize + unitCount * RegionInfo::UNIT_SIZE));
    std::memset(arena, 0, metadataSize + unitCount * RegionInfo::UNIT_SIZE);
    const uintptr_t heapStart = reinterpret_cast<uintptr_t>(arena + metadataSize);
    RegionInfo::Initialize(unitCount, heapStart);
    auto role = large ? RegionInfo::UnitRole::LARGE_SIZED_UNITS : RegionInfo::UnitRole::SMALL_SIZED_UNITS;
    RegionInfo* region = RegionInfo::InitRegion(4, 1, role);

    alignas(LiveInfo) uint8_t liveInfoStorage[sizeof(LiveInfo)]{};
    alignas(RegionBitmap) uint8_t bitmapStorage[128]{};
    if (large) {
        region->SetMarkedRegionFlag(markedOffset >= 0 ? 1 : 0);
    } else if (markedOffset >= 0) {
        auto* liveInfo = new (liveInfoStorage) LiveInfo();
        auto* bitmap = new (bitmapStorage) RegionBitmap(RegionInfo::UNIT_SIZE);
        bitmap->MarkBits(static_cast<size_t>(markedOffset), 8, RegionInfo::UNIT_SIZE);
        liveInfo->bindedRegion = region;
        liveInfo->markBitmap = bitmap;
        std::memcpy(reinterpret_cast<uint8_t*>(region) + 32, &liveInfo, sizeof(liveInfo));
    }

    auto* object = reinterpret_cast<BaseObject*>(heapStart + 4 * RegionInfo::UNIT_SIZE + queryOffset);
    std::printf("REGIONINFO_MARKED large=%u marked=%lld query=%zu address=%u offset=%u\n",
        large ? 1U : 0U, static_cast<long long>(markedOffset), queryOffset,
        region->IsMarkedObject(object) ? 1U : 0U, region->IsMarkedObject(queryOffset) ? 1U : 0U);
    std::free(arena);
}

int main()
{
    CheckMarked(true, -1, 0);
    CheckMarked(true, 0, 24);
    CheckMarked(false, -1, 0);
    CheckMarked(false, 24, 0);
    CheckMarked(false, 24, 24);
    CheckMarked(false, 520, 520);
    return 0;
}
