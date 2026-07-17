#define _GNU_SOURCE

#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "Cangjie.h"

typedef enum RTErrorCode (*InitCJRuntimeFunc)(const struct RuntimeParam*);
typedef enum RTErrorCode (*FiniCJRuntimeFunc)(void);
typedef const void* (*RuntimeNewSubSchedulerFunc)(void);
typedef CJThreadHandle (*RunCJTaskToScheduleFunc)(const CJTaskFunc, void*, void*);
typedef int8_t (*StopSubSchedulerFunc)(void*);
typedef int (*GetTaskRetFunc)(const CJThreadHandle, void**);
typedef void (*ReleaseHandleFunc)(const CJThreadHandle);
typedef uintptr_t (*GetThreadLocalDataFunc)(void);
typedef int (*GetCJThreadStateFunc)(void*);

struct ThreadLocalDataPrefix {
    void* buffer;
    void* mutator;
    void* cjthread;
    void* schedule;
};

static GetThreadLocalDataFunc getThreadLocalData;
static GetCJThreadStateFunc getCJThreadState;

static void* Resolve(void* image, const char* symbol)
{
    dlerror();
    void* address = dlsym(image, symbol);
    const char* error = dlerror();
    if (address == NULL || error != NULL) {
        fprintf(stderr, "OFFICIAL_GNU_CONTROL FAIL stage=dlsym symbol=%s detail=%s\n",
            symbol, error == NULL ? "null" : error);
        exit(1);
    }
    return address;
}

static void PrintStage(const char* stage)
{
    struct ThreadLocalDataPrefix* threadLocal =
        (struct ThreadLocalDataPrefix*)getThreadLocalData();
    int state = threadLocal->cjthread == NULL ? -1 : getCJThreadState(threadLocal->cjthread);
    printf("OFFICIAL_GNU_STAGE stage=%s schedule=%p cjthread=%p state=%d os_tid=%ld\n",
        stage, threadLocal->schedule, threadLocal->cjthread, state, syscall(SYS_gettid));
    fflush(stdout);
}

static void* OfficialCallback(void* argument)
{
    PrintStage("callback_entered");
    return argument;
}

int main(int argc, char** argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s /absolute/path/to/libcangjie-runtime.so\n", argv[0]);
        return 2;
    }
    void* image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (image == NULL) {
        fprintf(stderr, "OFFICIAL_GNU_CONTROL FAIL stage=dlopen detail=%s\n", dlerror());
        return 1;
    }

    InitCJRuntimeFunc initCJRuntime = (InitCJRuntimeFunc)Resolve(image, "InitCJRuntime");
    FiniCJRuntimeFunc finiCJRuntime = (FiniCJRuntimeFunc)Resolve(image, "FiniCJRuntime");
    RuntimeNewSubSchedulerFunc newSubScheduler =
        (RuntimeNewSubSchedulerFunc)Resolve(image, "MRT_RuntimeNewSubScheduler");
    RunCJTaskToScheduleFunc runToSchedule =
        (RunCJTaskToScheduleFunc)Resolve(image, "RunCJTaskToSchedule");
    StopSubSchedulerFunc stopSubScheduler =
        (StopSubSchedulerFunc)Resolve(image, "MRT_StopSubScheduler");
    GetTaskRetFunc getTaskRet = (GetTaskRetFunc)Resolve(image, "GetTaskRet");
    ReleaseHandleFunc releaseHandle = (ReleaseHandleFunc)Resolve(image, "ReleaseHandle");
    getThreadLocalData = (GetThreadLocalDataFunc)Resolve(image, "MRT_GetThreadLocalData");
    getCJThreadState = (GetCJThreadStateFunc)Resolve(image, "CJThreadGetState");

    struct RuntimeParam runtimeParam = {0};
    runtimeParam.heapParam.regionSize = 64;
    runtimeParam.heapParam.heapSize = 64 * 1024;
    runtimeParam.logParam.logLevel = RTLOG_ERROR;
    runtimeParam.coParam.thStackSize = 1024;
    runtimeParam.coParam.coStackSize = 128;
    runtimeParam.coParam.processorNum = 2;
    if (initCJRuntime(&runtimeParam) != E_OK) {
        printf("OFFICIAL_GNU_CONTROL FAIL stage=init\n");
        return 1;
    }
    PrintStage("global_runtime_active");

    void* schedule = (void*)newSubScheduler();
    printf("OFFICIAL_GNU_STAGE stage=driver_created target_schedule=%p\n", schedule);
    fflush(stdout);
    void* expected = (void*)(uintptr_t)0x51A7U;
    CJThreadHandle task = runToSchedule(OfficialCallback, expected, schedule);
    printf("OFFICIAL_GNU_STAGE stage=task_submitted target_schedule=%p handle=%p\n", schedule, task);
    fflush(stdout);
    void* actual = NULL;
    int getResult = getTaskRet(task, &actual);
    releaseHandle(task);
    int stopResult = stopSubScheduler(schedule);
    int finiResult = finiCJRuntime();
    int closeResult = dlclose(image);
    if (schedule == NULL || task == NULL || getResult != E_OK || actual != expected ||
        stopResult != 0 || finiResult != E_OK || closeResult != 0) {
        printf("OFFICIAL_GNU_CONTROL FAIL stage=final schedule=%d task=%d get=%d identity=%d "
               "stop=%d fini=%d close=%d\n",
            schedule != NULL, task != NULL, getResult, actual == expected,
            stopResult, finiResult, closeResult);
        return 1;
    }
    printf("OFFICIAL_GNU_CONTROL PASS callback=PASS return_identity=PASS release=PASS stop=PASS\n");
    return 0;
}
