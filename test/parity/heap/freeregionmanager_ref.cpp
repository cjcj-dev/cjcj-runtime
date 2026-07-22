#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <sys/mman.h>

#define private public
#include "Heap/Allocator/FreeRegionManager.h"
#include "Heap/Allocator/RegionManager.h"
#undef private

using namespace MapleRuntime;

int main()
{
    constexpr size_t units = 24;
    const size_t metadata = RoundUp<size_t>(units * sizeof(RegionInfo), RegionInfo::UNIT_SIZE);
    const size_t mapSize = metadata + units * RegionInfo::UNIT_SIZE;
    void* mapping = mmap(nullptr, mapSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED) return 2;
    uintptr_t heap = reinterpret_cast<uintptr_t>(mapping) + metadata;
    RegionInfo::Initialize(units, heap);

    alignas(RegionManager) unsigned char ownerStorage[sizeof(RegionManager)]{};
    auto& owner = *reinterpret_cast<RegionManager*>(ownerStorage);
    FreeRegionManager manager(owner);
    manager.Initialize(units);

    manager.AddGarbageUnits(2, 4);
    manager.AddGarbageUnits(10, 2);
    manager.AddReleaseUnits(16, 3);
    *reinterpret_cast<uint8_t*>(heap + 2 * RegionInfo::UNIT_SIZE) = 0xa5;
    *reinterpret_cast<uint8_t*>(heap + 16 * RegionInfo::UNIT_SIZE) = 0x5a;
    RegionInfo* dirty = manager.TakeRegion(2, RegionInfo::UnitRole::SMALL_SIZED_UNITS, false);
    bool dirtyFirst = dirty != nullptr && dirty->GetUnitIdx() == 2 &&
        *reinterpret_cast<uint8_t*>(heap + 2 * RegionInfo::UNIT_SIZE) == 0;
    RegionInfo* released = manager.TakeRegion(3, RegionInfo::UnitRole::LARGE_SIZED_UNITS, false);
    bool releasedFallback = released != nullptr && released->GetUnitIdx() == 16 &&
        *reinterpret_cast<uint8_t*>(heap + 16 * RegionInfo::UNIT_SIZE) == 0x5a;

    manager.AddReleaseUnits(20, 2);
    *reinterpret_cast<uint8_t*>(heap + 20 * RegionInfo::UNIT_SIZE) = 0x7c;
    RegionInfo* prepared = manager.TakeRegion(2, RegionInfo::UnitRole::SMALL_SIZED_UNITS, true);
    bool physical = prepared != nullptr && prepared->GetUnitIdx() == 20 &&
        *reinterpret_cast<uint8_t*>(heap + 20 * RegionInfo::UNIT_SIZE) == 0;

    const auto dirtyBefore = manager.GetDirtyUnitCount();
    const auto dirtyMax = manager.GetDirtyMaxBlock();
    const auto dirtyNodes = manager.GetDirtyNodeCount();
    const size_t moved = manager.ReleaseGarbageRegions(RegionInfo::UNIT_SIZE);
    bool release = moved == dirtyBefore * RegionInfo::UNIT_SIZE && manager.GetDirtyUnitCount() == 0 &&
        manager.GetReleasedUnitCount() == dirtyBefore && manager.GetReleasedMaxBlock() == dirtyMax &&
        manager.GetReleasedNodeCount() == dirtyNodes;

    std::printf("FREE_REGION_LAYOUT size=%zu align=%zu owner=%zu released_mutex=%zu released_tree=%zu dirty_mutex=%zu dirty_tree=%zu\n",
        sizeof(FreeRegionManager), alignof(FreeRegionManager), offsetof(FreeRegionManager, regionManager),
        offsetof(FreeRegionManager, releasedUnitTreeMutex), offsetof(FreeRegionManager, releasedUnitTree),
        offsetof(FreeRegionManager, dirtyUnitTreeMutex), offsetof(FreeRegionManager, dirtyUnitTree));
    std::printf("FREE_REGION_PARITY dirty_first=%u released_fallback=%u physical=%u release=%u dirty_before=%u dirty_max=%u dirty_nodes=%zu moved=%zu\n",
        dirtyFirst, releasedFallback, physical, release, dirtyBefore, dirtyMax, dirtyNodes, moved);
    munmap(mapping, mapSize);
    return dirtyFirst && releasedFallback && physical && release ? 0 : 1;
}
