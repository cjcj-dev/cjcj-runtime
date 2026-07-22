#include <cstdio>
#include <vector>

#define private public
#define protected public
#include "Heap/Allocator/RegionInfo.h"
#include "Heap/Allocator/RegionList.h"
#undef protected
#undef private

using namespace MapleRuntime;

static long long Idx(RegionInfo* region)
{
    return region == nullptr ? -1 : static_cast<long long>(region->GetUnitIdx());
}

static RegionInfo* MakeRegion(size_t idx, size_t allocated)
{
    RegionInfo* region = RegionInfo::InitRegion(idx, 1, RegionInfo::UnitRole::SMALL_SIZED_UNITS);
    region->metadata.allocPtr += allocated;
    return region;
}

int main()
{
    std::printf("REGIONLIST_LAYOUT sizeof=%zu align=%zu mutex=%zu count=%zu units=%zu "
        "head=%zu tail=%zu name=%zu cache=%zu active=%zu\n", sizeof(RegionList),
        alignof(RegionList), offsetof(RegionList, listMutex), offsetof(RegionList, regionCount),
        offsetof(RegionList, unitCount), offsetof(RegionList, listHead),
        offsetof(RegionList, listTail), offsetof(RegionList, listName), sizeof(RegionCache),
        offsetof(RegionCache, active));

    constexpr size_t count = 12;
    std::vector<uint8_t> arena(count * sizeof(RegionInfo::UnitInfo) +
        count * RegionInfo::UNIT_SIZE, 0);
    uintptr_t heap = reinterpret_cast<uintptr_t>(arena.data() + count * sizeof(RegionInfo::UnitInfo));
    RegionInfo::Initialize(count, heap);

    RegionList list("list");
    list.PrependRegion(nullptr, RegionInfo::RegionType::FROM_REGION);
    RegionInfo* r0 = MakeRegion(0, 10);
    RegionInfo* r1 = MakeRegion(1, 20);
    list.PrependRegion(r0, RegionInfo::RegionType::RECENT_FULL_REGION);
    list.PrependRegion(r1, RegionInfo::RegionType::RECENT_FULL_REGION);
#ifdef MRT_DEBUG
    list.DumpRegionList("list");
#endif
    std::printf("PREPEND regions=%zu units=%zu head=%lld tail=%lld\n", list.GetRegionCount(),
        list.GetUnitCount(), Idx(list.GetHeadRegion()), Idx(list.GetTailRegion()));

    bool wrong = list.TryDeleteRegion(r1, RegionInfo::RegionType::FROM_REGION,
        RegionInfo::RegionType::TO_REGION);
    bool removed = list.TryDeleteRegion(r1, RegionInfo::RegionType::RECENT_FULL_REGION,
        RegionInfo::RegionType::TO_REGION);
    RegionInfo* taken = list.TakeHeadRegion(RegionInfo::RegionType::FROM_REGION);
    std::printf("DELETE wrong=%u removed=%u taken=%lld type=%u remaining=%zu\n",
        unsigned(wrong), unsigned(removed), Idx(taken), unsigned(taken->GetRegionType()),
        list.GetRegionCount());

    RegionList src("src");
    RegionList dst("dst");
    src.PrependRegion(MakeRegion(2, 30), RegionInfo::RegionType::RECENT_FULL_REGION);
    src.PrependRegion(MakeRegion(3, 40), RegionInfo::RegionType::RECENT_FULL_REGION);
    dst.PrependRegion(MakeRegion(6, 70), RegionInfo::RegionType::LARGE_REGION);
    dst.MergeRegionList(src, RegionInfo::RegionType::FROM_REGION);
    std::printf("MERGE regions=%zu src=%zu head=%lld tail=%lld bytes=%zu counted=%zu\n",
        dst.GetRegionCount(), src.GetRegionCount(), Idx(dst.GetHeadRegion()),
        Idx(dst.GetTailRegion()), dst.GetAllocatedSize(), dst.GetAllocatedSize(true));

    size_t visitCount = 0;
    size_t visitSum = 0;
    dst.VisitAllRegions([&](RegionInfo* region) {
        ++visitCount;
        visitSum += region->GetUnitIdx() + 1;
        RemoveRegionLocked(&dst, region);
    });
    std::printf("VISIT count=%zu sum=%zu remaining=%zu\n", visitCount, visitSum,
        dst.GetRegionCount());

    RegionInfo* r7 = MakeRegion(7, 80);
    RegionCache cache("cache");
    bool inactive = cache.TryPrependRegion(r7, RegionInfo::RegionType::RECENT_FULL_REGION);
    cache.ActivateRegionCache();
    bool active = cache.TryPrependRegion(r7, RegionInfo::RegionType::RECENT_FULL_REGION);
    r7->SetTraceRegionFlag(1);
    cache.DeactivateRegionCache();
    size_t cacheRegions = cache.GetRegionCount();
    RegionInfo* cacheTaken = cache.TakeHeadRegion();
    std::printf("CACHE inactive=%u active=%u regions=%zu trace=%u take=%lld\n",
        unsigned(inactive), unsigned(active), cacheRegions,
        unsigned(r7->IsTraceRegion()), Idx(cacheTaken));
    std::puts("REGIONLIST_PARITY PASS");
    return 0;
}
