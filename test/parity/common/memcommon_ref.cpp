#include "Common/MemCommon.h"

#include <cinttypes>
#include <cstdio>

int main()
{
    const size_t values[] = {1, 8, 9, 128, 129, 1024, 1025, 8192, 8193, 65536, 65537, 262144, 262145};
    for (size_t value : values) {
        std::printf("SIZE %zu %zu %zu\n", value, MapleRuntime::SizeManager::RoundUp(value),
            MapleRuntime::SizeManager::Index(value));
    }
    std::printf("MEMCOMMON %zu %zu %zu %zu %d\n", MapleRuntime::MAX_NPAGES, MapleRuntime::PAGE_SHIFT,
        MapleRuntime::MAX_BYTES, MapleRuntime::NFREELIST, MapleRuntime::MIN_ALIGN_NUM);
    return 0;
}
