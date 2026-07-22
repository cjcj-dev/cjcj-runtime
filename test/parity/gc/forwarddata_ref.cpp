#include <cstdio>
#include <cstddef>
#include <sys/mman.h>

#include "Base/ImmortalWrapper.h"
#include "Heap/Heap.h"
#include "Base/Log.h"
#include "Base/LogFile.h"
#include "Base/MemUtils.h"
#include "Base/SysCall.h"
#include "Heap/Collector/LiveInfo.h"
#include "Base/AtomicSpinLock.h"
#define class struct
#define private public
#include "Heap/Collector/ForwardDataManager.h"
#undef private
#undef class
#include "Heap/Allocator/RegionInfo.h"

using namespace MapleRuntime;

namespace MapleRuntime {
extern const size_t MRT_PAGE_SIZE = 4096;
}

int main()
{
    using Space = ForwardDataManager::ForwardDataSpace;
    using Zone = Space::Zone;
    ForwardDataManager manager;
    size_t raw = manager.GetLiveInfoDataSize(8192);
    size_t perSpace = RoundUp(raw, MRT_PAGE_SIZE);
    manager.forwardDataSize = perSpace * 2;
    void* mapping = mmap(nullptr, manager.forwardDataSize, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED) return 2;
    manager.forwardDataStart = reinterpret_cast<uintptr_t>(mapping);
    manager.liveInfoData[0].InitializeMemory(manager.forwardDataStart, perSpace, manager.regionUnitCount);
    manager.liveInfoData[1].InitializeMemory(manager.forwardDataStart + perSpace, perSpace, manager.regionUnitCount);

    LiveInfo* live = manager.AllocateLiveInfo();
    RegionBitmap* bitmap0 = manager.AllocateRegionBitmap(8192);
    RegionBitmap* bitmap1 = manager.AllocateRegionBitmap(8192);
    bool first = bitmap0->MarkBits(0, 16, 8192);
    RegionInfo region;
    *reinterpret_cast<LiveInfo**>(reinterpret_cast<uint8_t*>(&region) + 32) = live;
    *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(&region) + 24) = 77;
    live->bindedRegion = &region;
    manager.SetTagID(1);
    manager.UnbindPreviousLiveInfo();

    std::printf("FORWARDDATA_LAYOUT zone=%zu/%zu space=%zu/%zu manager=%zu/%zu\n",
        sizeof(Zone), alignof(Zone), sizeof(Space), alignof(Space),
        sizeof(ForwardDataManager), alignof(ForwardDataManager));
    std::printf("CAP heap=8192 units=%zu raw=%zu per_space=%zu total=%zu\n",
        manager.regionUnitCount, raw, perSpace, manager.forwardDataSize);
    std::printf("ALLOC live=%zu bitmap0=%zu bitmap1=%zu bitmap_size=%zu\n",
        reinterpret_cast<uintptr_t>(live) - manager.forwardDataStart,
        reinterpret_cast<uintptr_t>(bitmap0) - manager.forwardDataStart,
        reinterpret_cast<uintptr_t>(bitmap1) - manager.forwardDataStart,
        RegionBitmap::GetRegionBitmapSize(8192));
    std::printf("MARK first=%d live=%zu previous=%u\n", first, bitmap0->GetLiveBytes(),
        manager.GetPreviousTagID());
    std::printf("UNBIND live_null=%d bytes=%u\n",
        *reinterpret_cast<LiveInfo**>(reinterpret_cast<uint8_t*>(&region) + 32) == nullptr,
        *reinterpret_cast<uint32_t*>(reinterpret_cast<uint8_t*>(&region) + 24));
    manager.ClearPreviousForwardData();
    std::printf("RESET live=%zu bitmap=%zu\n",
        manager.liveInfoData[0].allocZone[Zone::LIVE_INFO].zonePosition.load() - manager.forwardDataStart,
        manager.liveInfoData[0].allocZone[Zone::BIT_MAP].zonePosition.load() - manager.forwardDataStart);
    return 0;
}
