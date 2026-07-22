#include <cstdio>
#include <cstdlib>
#include <new>
#include "Heap/Collector/LiveInfo.h"

using namespace MapleRuntime;

static RegionBitmap* Make(size_t regionSize)
{
    void* storage = std::calloc(1, RegionBitmap::GetRegionBitmapSize(regionSize));
    return new (storage) RegionBitmap(regionSize);
}

int main()
{
    constexpr size_t regionSize = 8192;
    auto* first = Make(regionSize);
    auto* second = Make(regionSize);
    std::printf("REGIONBITMAP_LAYOUT bitmap=%zu/%zu bits=%zu/%zu pre=%zu/%zu liveinfo=%zu/%zu size=%zu\n",
        sizeof(RegionBitmap), alignof(RegionBitmap), sizeof(RegionBitmap::BitMaskInfo),
        alignof(RegionBitmap::BitMaskInfo), sizeof(RegionBitmap::PreMaskInfo),
        alignof(RegionBitmap::PreMaskInfo), sizeof(LiveInfo), alignof(LiveInfo),
        RegionBitmap::GetRegionBitmapSize(regionSize));
    bool firstMark = first->MarkBits(480, 552, regionSize);
    bool repeat = first->MarkBits(480, 552, regionSize);
    RegionBitmap::PreMaskInfo pre{};
    RegionBitmap::GetPreMaskInfo(1032, regionSize, pre);
    std::printf("MARK first=%d repeat=%d marked480=%d marked1024=%d live=%zu recompute=%zu pre=%llu\n",
        firstMark, repeat, first->IsMarked(480), first->IsMarked(1024), first->GetLiveBytes(),
        first->RecomputeLiveBytes(), static_cast<unsigned long long>(first->GetPreLiveBytes(pre)));
    second->MarkBits(0, 8, regionSize);
    LiveInfo live{};
    live.markBitmap = first;
    live.resurrectBitmap = second;
    std::printf("LIVE survived0=%d survived480=%d survived2048=%d bytes=%zu recompute=%zu pre=%llu\n",
        live.IsSurvivedObject(0), live.IsSurvivedObject(480), live.IsSurvivedObject(2048),
        live.GetBitmapLiveBytes(), live.RecomputeBitmapLiveBytes(),
        static_cast<unsigned long long>(live.GetPreLiveBytes(1032, regionSize)));
    std::printf("REGIONBITMAP_PARITY PASS\n");
    std::free(first);
    std::free(second);
}
