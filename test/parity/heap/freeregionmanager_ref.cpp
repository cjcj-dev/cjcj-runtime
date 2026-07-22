#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <sys/mman.h>

#define private public
#include "Heap/Allocator/FreeRegionManager.h"
#include "Heap/Allocator/RegionManager.h"
#include "Heap/Allocator/CartesianTree.cpp"
#undef private

using namespace MapleRuntime;

namespace MapleRuntime {
const size_t RegionInfo::UNIT_SIZE = 4096;
const size_t RegionInfo::LARGE_OBJECT_DEFAULT_THRESHOLD = 8 * RegionInfo::UNIT_SIZE;
size_t RegionInfo::UnitInfo::totalUnitCount = 0;
uintptr_t RegionInfo::UnitInfo::heapStartAddress = 0;

size_t FreeRegionManager::ReleaseGarbageRegions(size_t targetCachedSize)
{
    size_t dirtyBytes = dirtyUnitTree.GetTotalCount() * RegionInfo::UNIT_SIZE;
    if (dirtyBytes <= targetCachedSize) {
        VLOG(REPORT, "release heap garbage memory 0 bytes, cache %zu(%zu) bytes", dirtyBytes, targetCachedSize);
        return 0;
    }
    size_t releasedBytes = 0;
    while (dirtyBytes > targetCachedSize) {
        std::lock_guard<std::mutex> lock1(dirtyUnitTreeMutex);
        auto node = dirtyUnitTree.RootNode();
        if (node == nullptr) break;
        Index idx = node->GetIndex();
        UnitCount num = node->GetCount();
        dirtyUnitTree.ReleaseRootNode();
        std::lock_guard<std::mutex> lock2(releasedUnitTreeMutex);
        CHECK_DETAIL(releasedUnitTree.MergeInsert(idx, num, true),
            "failed to release garbage units[%u+%u, %u)", idx, num, idx + num);
        releasedBytes += num * RegionInfo::UNIT_SIZE;
        dirtyBytes = dirtyUnitTree.GetTotalCount() * RegionInfo::UNIT_SIZE;
    }
    VLOG(REPORT, "release heap garbage memory %zu bytes, cache %zu(%zu) bytes",
        releasedBytes, dirtyBytes, targetCachedSize);
    return releasedBytes;
}
}

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

    // The standalone oracle has no initialized runtime ThreadLocalData, while
    // Add* faithfully enters ScopedEnterSaferegion(true). Seed the exact two
    // production trees through the private test view; the Cangjie probe and
    // noheap root still exercise the public Add* paths.
    manager.dirtyUnitTree.MergeInsert(2, 4, true);
    manager.releasedUnitTree.MergeInsert(16, 3, true);
    *reinterpret_cast<uint8_t*>(heap + 2 * RegionInfo::UNIT_SIZE) = 0xa5;
    *reinterpret_cast<uint8_t*>(heap + 16 * RegionInfo::UNIT_SIZE) = 0x5a;
    RegionInfo* dirty = manager.TakeRegion(2, RegionInfo::UnitRole::SMALL_SIZED_UNITS, false);
    bool dirtyFirst = dirty != nullptr && dirty->GetUnitIdx() == 2 &&
        *reinterpret_cast<uint8_t*>(heap + 2 * RegionInfo::UNIT_SIZE) == 0;
    const uintptr_t dirtyStart = dirty->GetRegionStart();
    const size_t dirtySize = dirty->GetRegionSize();
    bool allocation = dirty->Alloc(64) == dirtyStart &&
        dirty->Alloc(dirtySize - 64) == dirtyStart + 64 && dirty->Alloc(8) == 0 &&
        dirty->GetRegionAllocPtr() == dirtyStart + dirtySize;
    RegionInfo* released = manager.TakeRegion(3, RegionInfo::UnitRole::LARGE_SIZED_UNITS, false);
    bool releasedFallback = released != nullptr && released->GetUnitIdx() == 16 &&
        *reinterpret_cast<uint8_t*>(heap + 16 * RegionInfo::UNIT_SIZE) == 0x5a;

    const auto dirtyBefore = manager.GetDirtyUnitCount();
    const auto dirtyMax = manager.GetDirtyMaxBlock();
    const auto dirtyNodes = manager.GetDirtyNodeCount();
    const size_t moved = manager.ReleaseGarbageRegions(RegionInfo::UNIT_SIZE);
    bool release = moved == dirtyBefore * RegionInfo::UNIT_SIZE && manager.GetDirtyUnitCount() == 0 &&
        manager.GetReleasedUnitCount() == dirtyBefore && manager.GetReleasedMaxBlock() == dirtyMax &&
        manager.GetReleasedNodeCount() == dirtyNodes;

    *reinterpret_cast<uint8_t*>(heap + 4 * RegionInfo::UNIT_SIZE) = 0x7c;
    RegionInfo* prepared = manager.TakeRegion(2, RegionInfo::UnitRole::SMALL_SIZED_UNITS, true);
    bool physical = prepared != nullptr && prepared->GetUnitIdx() == 4 &&
        *reinterpret_cast<uint8_t*>(heap + 4 * RegionInfo::UNIT_SIZE) == 0;

    std::printf("FREE_REGION_LAYOUT size=%zu align=%zu owner=%zu released_mutex=%zu released_tree=%zu dirty_mutex=%zu dirty_tree=%zu\n",
        sizeof(FreeRegionManager), alignof(FreeRegionManager), offsetof(FreeRegionManager, regionManager),
        offsetof(FreeRegionManager, releasedUnitTreeMutex), offsetof(FreeRegionManager, releasedUnitTree),
        offsetof(FreeRegionManager, dirtyUnitTreeMutex), offsetof(FreeRegionManager, dirtyUnitTree));
    std::printf("FREE_REGION_PARITY dirty_first=%u allocation=%u released_fallback=%u physical=%u release=%u dirty_before=%u dirty_max=%u dirty_nodes=%zu moved=%zu\n",
        dirtyFirst, allocation, releasedFallback, physical, release, dirtyBefore, dirtyMax, dirtyNodes, moved);
    munmap(mapping, mapSize);
    return dirtyFirst && allocation && releasedFallback && physical && release ? 0 : 1;
}
