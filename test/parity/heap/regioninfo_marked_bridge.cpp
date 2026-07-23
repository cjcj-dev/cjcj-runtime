#include <cstdint>
#include <cstring>
#include <new>

#include "Heap/Allocator/RegionInfo.h"
#include "Heap/Collector/LiveInfo.h"

using namespace MapleRuntime;

extern "C" void* CJRT_TestSetupMarkedRegion(void* arena, void* liveInfoStorage,
    void* bitmapStorage, uint8_t large, int64_t markedOffset)
{
    auto heapStart = reinterpret_cast<uintptr_t>(arena) + sizeof(RegionInfo);
    RegionInfo::Initialize(1, heapStart);
    auto role = large != 0 ? RegionInfo::UnitRole::LARGE_SIZED_UNITS : RegionInfo::UnitRole::SMALL_SIZED_UNITS;
    RegionInfo* region = RegionInfo::InitRegion(0, 1, role);
    if (large != 0) {
        region->SetMarkedRegionFlag(markedOffset >= 0 ? 1 : 0);
    } else if (markedOffset >= 0) {
        auto* liveInfo = new (liveInfoStorage) LiveInfo();
        auto* bitmap = new (bitmapStorage) RegionBitmap(RegionInfo::UNIT_SIZE);
        bitmap->MarkBits(static_cast<size_t>(markedOffset), 8, RegionInfo::UNIT_SIZE);
        liveInfo->bindedRegion = region;
        liveInfo->markBitmap = bitmap;
        std::memcpy(reinterpret_cast<uint8_t*>(region) + 32, &liveInfo, sizeof(liveInfo));
    }
    return region;
}

extern "C" uint8_t CJRT_TestIsMarkedObjectAddress(void* region, void* object)
{
    return static_cast<RegionInfo*>(region)->IsMarkedObject(static_cast<BaseObject*>(object));
}

extern "C" uint8_t CJRT_TestIsMarkedObjectOffset(void* region, uintptr_t offset)
{
    return static_cast<RegionInfo*>(region)->IsMarkedObject(offset);
}
