// Contract probe for RT_ISOLATE_API_SPEC.md section 5, slice 1.
// This file is intentionally GNU C and resolves every runtime entry through dlsym.

#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "cjcj_rt_instance.h"

#ifndef PROBE_SYMBOL
#define PROBE_SYMBOL "CJCJ_MRT_InstanceNew"
#endif

#ifndef PROBE_CYCLES
#define PROBE_CYCLES 1
#endif

#if defined(__linux__)
#define RSS_GROWTH_LIMIT_BYTES (8ULL * 1024ULL * 1024ULL)
#else
#error "Define a measured RSS_GROWTH_LIMIT_BYTES for this contract-probe platform"
#endif

typedef enum RTErrorCode (*InitCJRuntimeFn)(const struct RuntimeParam*);
typedef enum RTErrorCode (*FiniCJRuntimeFn)(void);
typedef CjcjRtInstanceHandle (*InstanceNewFn)(const struct CjcjRtInstanceParam*);
typedef CJThreadHandle (*InstanceRunTaskFn)(CjcjRtInstanceHandle, const CJTaskFunc, void*);
typedef int (*InstanceStopFn)(CjcjRtInstanceHandle);
typedef int (*GetTaskRetFn)(const CJThreadHandle, void**);
typedef void (*ReleaseHandleFn)(const CJThreadHandle);

static volatile uintptr_t stackSink;

__attribute__((noinline)) static void ConsumeStack(unsigned int depth)
{
    volatile uint8_t frame[8192];
    frame[0] = (uint8_t)depth;
    frame[sizeof(frame) - 1] = (uint8_t)(depth >> 1);
    if (depth != 0) {
        ConsumeStack(depth - 1);
    }
    stackSink += frame[0] + frame[sizeof(frame) - 1];
}

static void* StackTask(void* arg)
{
    ConsumeStack(384);
    return arg;
}

static void* DelayedTask(void* arg)
{
    usleep(20000);
    return arg;
}

static int ResidentBytes(uint64_t* result)
{
    FILE* statm = fopen("/proc/self/statm", "r");
    unsigned long pages;
    unsigned long resident;
    long pageSize;
    if (statm == NULL || fscanf(statm, "%lu %lu", &pages, &resident) != 2) {
        if (statm != NULL) {
            fclose(statm);
        }
        return 0;
    }
    fclose(statm);
    pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) {
        return 0;
    }
    *result = (uint64_t)resident * (uint64_t)pageSize;
    return 1;
}

static void* Resolve(void* image, const char* symbol)
{
    void* address;
    dlerror();
    address = dlsym(image, symbol);
    if (address == NULL || dlerror() != NULL) {
        fprintf(stderr, "CONTRACT %s FAIL stage=dlsym symbol=%s\n", PROBE_SYMBOL, symbol);
        exit(1);
    }
    return address;
}

int main(int argc, char** argv)
{
    void* image;
    InitCJRuntimeFn initCJRuntime;
    FiniCJRuntimeFn finiCJRuntime;
    InstanceNewFn instanceNew;
    InstanceRunTaskFn instanceRunTask;
    InstanceStopFn instanceStop;
    GetTaskRetFn getTaskRet;
    ReleaseHandleFn releaseHandle;
    struct RuntimeParam runtimeParam = {0};
    struct CjcjRtInstanceParam instanceParam = {1024, 4 * 1024, 1};
    uint64_t rssBefore;
    uint64_t rssAfter;
    uint64_t rssGrowth;
    unsigned int cycle;

    if (argc != 2) {
        fprintf(stderr, "usage: %s /absolute/path/to/libcangjie-runtime.so\n", argv[0]);
        return 2;
    }
    image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (image == NULL) {
        fprintf(stderr, "CONTRACT %s FAIL stage=dlopen detail=%s\n", PROBE_SYMBOL, dlerror());
        return 1;
    }

    initCJRuntime = (InitCJRuntimeFn)Resolve(image, "InitCJRuntime");
    finiCJRuntime = (FiniCJRuntimeFn)Resolve(image, "FiniCJRuntime");
    instanceNew = (InstanceNewFn)Resolve(image, "CJCJ_MRT_InstanceNew");
    instanceRunTask = (InstanceRunTaskFn)Resolve(image, "CJCJ_MRT_InstanceRunTask");
    instanceStop = (InstanceStopFn)Resolve(image, "CJCJ_MRT_InstanceStop");
    getTaskRet = (GetTaskRetFn)Resolve(image, "GetTaskRet");
    releaseHandle = (ReleaseHandleFn)Resolve(image, "ReleaseHandle");

    runtimeParam.heapParam.regionSize = 64;
    runtimeParam.heapParam.heapSize = 64 * 1024;
    runtimeParam.logParam.logLevel = RTLOG_ERROR;
    runtimeParam.coParam.thStackSize = 1024;
    runtimeParam.coParam.coStackSize = 128;
    runtimeParam.coParam.processorNum = 2;
    if (initCJRuntime(&runtimeParam) != E_OK) {
        printf("CONTRACT %s FAIL stage=init\n", PROBE_SYMBOL);
        return 1;
    }
    if (!ResidentBytes(&rssBefore)) {
        printf("CONTRACT %s FAIL stage=rss_before\n", PROBE_SYMBOL);
        return 1;
    }

    for (cycle = 0; cycle < PROBE_CYCLES; ++cycle) {
        CjcjRtInstanceHandle instance = instanceNew(&instanceParam);
        void* expected = (void*)(uintptr_t)(cycle + 1);
        CJThreadHandle task = instanceRunTask(instance, StackTask, expected);
        void* actual = NULL;
        int get = getTaskRet(task, &actual);
        int stop;
        int stopAgain;
        releaseHandle(task);
        stop = instanceStop(instance);
        stopAgain = instanceStop(instance);
        if (instance == NULL || task == NULL || get != E_OK || actual != expected ||
            stop != 0 || stopAgain == 0) {
            printf("CONTRACT %s FAIL cycle=%u instance=%d task=%d get=%d ret=%d stop=%d stop_again=%d\n",
                PROBE_SYMBOL, cycle, instance != NULL, task != NULL, get, actual == expected, stop, stopAgain);
            return 1;
        }
    }

    {
        CjcjRtInstanceHandle liveInstance = instanceNew(&instanceParam);
        void* liveExpected = (void*)(uintptr_t)(PROBE_CYCLES + 1);
        CJThreadHandle liveTask = instanceRunTask(liveInstance, DelayedTask, liveExpected);
        int liveStop = instanceStop(liveInstance);
        void* liveActual = NULL;
        int liveGet = getTaskRet(liveTask, &liveActual);
        releaseHandle(liveTask);
        if (liveInstance == NULL || liveTask == NULL || liveStop != 0 ||
            liveGet != E_OK || liveActual != liveExpected) {
            printf("CONTRACT %s FAIL stage=live_stop instance=%d task=%d stop=%d get=%d ret=%d\n",
                PROBE_SYMBOL, liveInstance != NULL, liveTask != NULL, liveStop, liveGet,
                liveActual == liveExpected);
            return 1;
        }
    }

    if (!ResidentBytes(&rssAfter)) {
        printf("CONTRACT %s FAIL stage=rss_after\n", PROBE_SYMBOL);
        return 1;
    }
    rssGrowth = rssAfter > rssBefore ? rssAfter - rssBefore : 0;
    if (rssGrowth >= RSS_GROWTH_LIMIT_BYTES) {
        printf("CONTRACT %s FAIL stage=rss_limit rss_before=%" PRIu64 " rss_after=%" PRIu64
               " rss_growth=%" PRIu64 " rss_limit=%" PRIu64 "\n",
            PROBE_SYMBOL, rssBefore, rssAfter, rssGrowth, (uint64_t)RSS_GROWTH_LIMIT_BYTES);
        return 1;
    }
    if (finiCJRuntime() != E_OK) {
        printf("CONTRACT %s FAIL stage=fini\n", PROBE_SYMBOL);
        return 1;
    }
    if (dlclose(image) != 0) {
        printf("CONTRACT %s FAIL stage=dlclose\n", PROBE_SYMBOL);
        return 1;
    }

    printf("CONTRACT %s PASS cycles=%u stack_bytes=%u live_stop=PASS rss_before=%" PRIu64
           " rss_after=%" PRIu64 " rss_growth=%" PRIu64 " rss_limit=%" PRIu64 "\n",
        PROBE_SYMBOL, PROBE_CYCLES, 384U * 8192U, rssBefore, rssAfter, rssGrowth,
        (uint64_t)RSS_GROWTH_LIMIT_BYTES);
    return 0;
}
