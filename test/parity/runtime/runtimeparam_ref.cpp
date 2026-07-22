// Cangjie.h:194-341 and CangjieRuntime.h:36,46-49 executable oracle.
#include "Cangjie.h"
#include <cstddef>
#include <cstdio>
#include <cstring>

int main()
{
    std::printf(
        "RUNTIMEPARAM_LAYOUT heap=%zu/%zu gc=%zu/%zu log=%zu/%zu concurrency=%zu/%zu runtime=%zu/%zu "
        "heap_off=%zu gc_off=%zu log_off=%zu concurrency_off=%zu\n",
        sizeof(HeapParam), alignof(HeapParam), sizeof(GCParam), alignof(GCParam),
        sizeof(LogParam), alignof(LogParam), sizeof(ConcurrencyParam), alignof(ConcurrencyParam),
        sizeof(RuntimeParam), alignof(RuntimeParam), offsetof(RuntimeParam, heapParam),
        offsetof(RuntimeParam, gcParam), offsetof(RuntimeParam, logParam), offsetof(RuntimeParam, coParam));

    RuntimeParam value;
    std::memset(&value, 0, sizeof(value));
    value.heapParam.regionSize = 0x0102030405060708ULL;
    value.heapParam.heapSize = 0x1112131415161718ULL;
    value.heapParam.exemptionThreshold = 0.25;
    value.heapParam.heapUtilization = 0.5;
    value.heapParam.heapGrowth = 0.75;
    value.heapParam.allocationRate = 10240.0;
    value.heapParam.allocationWaitTime = 0x2122232425262728ULL;
    value.gcParam.gcThreshold = 0x3132333435363738ULL;
    value.gcParam.garbageThreshold = 0.625;
    value.gcParam.gcInterval = 0x4142434445464748ULL;
    value.gcParam.backupGCInterval = 0x5152535455565758ULL;
    value.gcParam.gcThreads = 0x61626364;
    value.logParam.logLevel = 5;
    value.coParam.thStackSize = 0x7172737475767778ULL;
    value.coParam.coStackSize = 0x8182838485868788ULL;
    value.coParam.processorNum = 0x91929394U;
    std::fwrite(&value, 1, sizeof(value), stdout);
    return 0;
}
