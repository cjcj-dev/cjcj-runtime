#define _GNU_SOURCE

#include <dirent.h>
#include <dlfcn.h>
#include <elf.h>
#include <inttypes.h>
#include <limits.h>
#include <link.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

struct InstanceParam {
    size_t thStackSize;
    size_t coStackSize;
    uint32_t processorNum;
};

typedef void* (*TaskFunc)(void*);
typedef void* (*InstanceNewFunc)(const struct InstanceParam*);
typedef void* (*InstanceRunFunc)(void*, TaskFunc, void*);
typedef int (*InstanceStopFunc)(void*);
typedef const void* (*OfficialNewFunc)(void);
typedef void* (*OfficialRunFunc)(TaskFunc, void*, void*);
typedef int8_t (*OfficialStopFunc)(void*);
typedef int (*GetTaskRetFunc)(const void*, void**);
typedef void (*ReleaseHandleFunc)(const void*);
typedef uintptr_t (*GetThreadLocalDataFunc)(void);
typedef int (*GetCJThreadStateFunc)(void*);

static void* runtimeImageHandle;

struct ThreadLocalDataPrefix {
    void* buffer;
    void* mutator;
    void* cjthread;
    void* schedule;
};

enum ContractMode {
    CONTRACT_S4 = 0,
    CONTRACT_OFFICIAL = 1,
};

static void* Resolve(const char* name)
{
    dlerror();
    void* address = dlsym(runtimeImageHandle == NULL ? RTLD_DEFAULT : runtimeImageHandle, name);
    const char* error = dlerror();
    if (address == NULL || error != NULL) {
        fprintf(stderr, "MANAGED_CONTRACT FAIL stage=dlsym symbol=%s detail=%s\n",
            name, error == NULL ? "null" : error);
        fflush(stderr);
        return NULL;
    }
    return address;
}

static int ParsePositiveEnv(const char* name, int fallback)
{
    const char* value = getenv(name);
    if (value == NULL || *value == '\0') {
        return fallback;
    }
    char* end = NULL;
    long parsed = strtol(value, &end, 10);
    if (end == value || *end != '\0' || parsed <= 0 || parsed > INT32_MAX) {
        return -1;
    }
    return (int)parsed;
}

int32_t CJRT_ContractMode(void)
{
    const char* mode = getenv("CJCJ_CONTRACT_MODE");
    if (mode == NULL || strcmp(mode, "s4") == 0) {
        return CONTRACT_S4;
    }
    if (strcmp(mode, "official") == 0) {
        return CONTRACT_OFFICIAL;
    }
    return -1;
}

int32_t CJRT_ContractCycles(void)
{
    return ParsePositiveEnv("CJCJ_CONTRACT_CYCLES", 1);
}

void* CJRT_ContractNew(int32_t mode, const struct InstanceParam* param)
{
    if (mode == CONTRACT_S4) {
        InstanceNewFunc instanceNew = (InstanceNewFunc)Resolve("CJCJ_MRT_InstanceNew");
        return instanceNew == NULL ? NULL : instanceNew(param);
    }
    OfficialNewFunc officialNew = (OfficialNewFunc)Resolve("MRT_RuntimeNewSubScheduler");
    return officialNew == NULL ? NULL : (void*)officialNew();
}

void* CJRT_ContractRun(int32_t mode, void* instance, void* callback, void* argument)
{
    if (mode == CONTRACT_S4) {
        InstanceRunFunc instanceRun = (InstanceRunFunc)Resolve("CJCJ_MRT_InstanceRunTask");
        return instanceRun == NULL ? NULL : instanceRun(instance, (TaskFunc)callback, argument);
    }
    OfficialRunFunc officialRun = (OfficialRunFunc)Resolve("RunCJTaskToSchedule");
    return officialRun == NULL ? NULL : officialRun((TaskFunc)callback, argument, instance);
}

int32_t CJRT_ContractStop(int32_t mode, void* instance)
{
    if (mode == CONTRACT_S4) {
        InstanceStopFunc instanceStop = (InstanceStopFunc)Resolve("CJCJ_MRT_InstanceStop");
        return instanceStop == NULL ? -1 : instanceStop(instance);
    }
    OfficialStopFunc officialStop = (OfficialStopFunc)Resolve("MRT_StopSubScheduler");
    return officialStop == NULL ? -1 : (int32_t)officialStop(instance);
}

int32_t CJRT_ContractGetRetMatches(void* handle, void* expected)
{
    GetTaskRetFunc getTaskRet = (GetTaskRetFunc)Resolve("GetTaskRet");
    void* actual = NULL;
    if (getTaskRet == NULL) {
        return -1;
    }
    int result = getTaskRet(handle, &actual);
    return result == 0 && actual == expected ? 0 : (result == 0 ? -2 : result);
}

int32_t CJRT_ContractReleaseAndReject(void* handle)
{
    ReleaseHandleFunc releaseHandle = (ReleaseHandleFunc)Resolve("ReleaseHandle");
    GetTaskRetFunc getTaskRet = (GetTaskRetFunc)Resolve("GetTaskRet");
    void* ignored = NULL;
    if (releaseHandle == NULL || getTaskRet == NULL) {
        return -1;
    }
    releaseHandle(handle);
    return getTaskRet(handle, &ignored) == 0 ? -2 : 0;
}

void* CJRT_ContractToken(int32_t cycle)
{
    return (void*)(uintptr_t)((uint32_t)cycle + 1U);
}

static struct ThreadLocalDataPrefix* CurrentThreadLocalData(void)
{
    GetThreadLocalDataFunc getThreadLocalData =
        (GetThreadLocalDataFunc)Resolve("MRT_GetThreadLocalData");
    return getThreadLocalData == NULL ? NULL :
        (struct ThreadLocalDataPrefix*)getThreadLocalData();
}

uintptr_t CJRT_ContractCurrentSchedule(void)
{
    struct ThreadLocalDataPrefix* threadLocal = CurrentThreadLocalData();
    return threadLocal == NULL ? 0 : (uintptr_t)threadLocal->schedule;
}

uintptr_t CJRT_ContractCurrentCJThread(void)
{
    struct ThreadLocalDataPrefix* threadLocal = CurrentThreadLocalData();
    return threadLocal == NULL ? 0 : (uintptr_t)threadLocal->cjthread;
}

int32_t CJRT_ContractCurrentCJThreadState(void)
{
    struct ThreadLocalDataPrefix* threadLocal = CurrentThreadLocalData();
    GetCJThreadStateFunc getState = (GetCJThreadStateFunc)Resolve("CJThreadGetState");
    return threadLocal == NULL || getState == NULL ? -1 : getState(threadLocal->cjthread);
}

uint64_t CJRT_ContractCurrentOSThread(void)
{
    return (uint64_t)syscall(SYS_gettid);
}

int32_t CJRT_ContractDriverCount(void)
{
    DIR* tasks = opendir("/proc/self/task");
    if (tasks == NULL) {
        return -1;
    }
    int32_t count = 0;
    struct dirent* entry;
    while ((entry = readdir(tasks)) != NULL) {
        if (entry->d_name[0] == '.') {
            continue;
        }
        char path[128];
        char name[32] = {0};
        snprintf(path, sizeof(path), "/proc/self/task/%s/comm", entry->d_name);
        FILE* stream = fopen(path, "r");
        if (stream != NULL) {
            if (fgets(name, sizeof(name), stream) != NULL && strncmp(name, "sub-schedule", 12) == 0) {
                ++count;
            }
            fclose(stream);
        }
    }
    closedir(tasks);
    return count;
}

uint64_t CJRT_ContractResidentBytes(void)
{
    FILE* statm = fopen("/proc/self/statm", "r");
    unsigned long pages = 0;
    unsigned long resident = 0;
    if (statm == NULL || fscanf(statm, "%lu %lu", &pages, &resident) != 2) {
        if (statm != NULL) {
            fclose(statm);
        }
        return 0;
    }
    fclose(statm);
    long pageSize = sysconf(_SC_PAGESIZE);
    return pageSize <= 0 ? 0 : (uint64_t)resident * (uint64_t)pageSize;
}

#define MAX_RUNTIME_IMAGES 8
#define MAX_BUILD_ID_BYTES 64

struct RuntimeImageIdentity {
    dev_t device;
    ino_t inode;
    uintptr_t base;
    char buildId[MAX_BUILD_ID_BYTES * 2 + 1];
    char path[PATH_MAX];
};

struct RuntimeImageAudit {
    int imageCount;
    int failed;
    struct RuntimeImageIdentity images[MAX_RUNTIME_IMAGES];
};

static size_t AlignNote(size_t value)
{
    return (value + 3U) & ~3U;
}

static int ReadBuildId(const struct dl_phdr_info* info, char* output, size_t outputSize)
{
    for (ElfW(Half) index = 0; index < info->dlpi_phnum; ++index) {
        const ElfW(Phdr)* header = &info->dlpi_phdr[index];
        if (header->p_type != PT_NOTE) {
            continue;
        }
        const unsigned char* cursor =
            (const unsigned char*)(info->dlpi_addr + header->p_vaddr);
        const unsigned char* end = cursor + header->p_memsz;
        while ((size_t)(end - cursor) >= sizeof(ElfW(Nhdr))) {
            ElfW(Nhdr) note;
            memcpy(&note, cursor, sizeof(note));
            cursor += sizeof(note);
            size_t nameSize = AlignNote(note.n_namesz);
            size_t descriptionSize = AlignNote(note.n_descsz);
            if ((size_t)(end - cursor) < nameSize + descriptionSize) {
                return 0;
            }
            const unsigned char* name = cursor;
            const unsigned char* description = cursor + nameSize;
            if (note.n_type == NT_GNU_BUILD_ID && note.n_namesz == 4 &&
                memcmp(name, "GNU", 4) == 0 && note.n_descsz <= MAX_BUILD_ID_BYTES &&
                outputSize > (size_t)note.n_descsz * 2U) {
                for (ElfW(Word) byte = 0; byte < note.n_descsz; ++byte) {
                    snprintf(output + byte * 2U, outputSize - byte * 2U, "%02x", description[byte]);
                }
                return 1;
            }
            cursor += nameSize + descriptionSize;
        }
    }
    snprintf(output, outputSize, "<none>");
    return 1;
}

static int SameIdentity(const struct RuntimeImageIdentity* left,
    const struct RuntimeImageIdentity* right)
{
    return left->device == right->device && left->inode == right->inode &&
        strcmp(left->buildId, right->buildId) == 0;
}

static int CountRuntimeImages(struct dl_phdr_info* info, size_t size, void* data)
{
    (void)size;
    struct RuntimeImageAudit* audit = (struct RuntimeImageAudit*)data;
    if (info->dlpi_name == NULL) {
        return 0;
    }
    const char* basename = strrchr(info->dlpi_name, '/');
    basename = basename == NULL ? info->dlpi_name : basename + 1;
    if (strcmp(basename, "libcangjie-runtime.so") != 0) {
        return 0;
    }

    struct RuntimeImageIdentity identity = {0};
    char* canonical = realpath(info->dlpi_name, identity.path);
    struct stat status;
    if (canonical == NULL || stat(identity.path, &status) != 0 ||
        !ReadBuildId(info, identity.buildId, sizeof(identity.buildId))) {
        audit->failed = 1;
        return 1;
    }
    identity.device = status.st_dev;
    identity.inode = status.st_ino;
    identity.base = (uintptr_t)info->dlpi_addr;
    for (int index = 0; index < audit->imageCount; ++index) {
        if (SameIdentity(&audit->images[index], &identity)) {
            return 0;
        }
    }
    if (audit->imageCount >= MAX_RUNTIME_IMAGES) {
        audit->failed = 1;
        return 1;
    }
    audit->images[audit->imageCount++] = identity;
    printf("MANAGED_IMAGE runtime device=%ju inode=%ju build_id=%s base=0x%" PRIxPTR
           " path=%s\n", (uintmax_t)identity.device, (uintmax_t)identity.inode,
        identity.buildId, identity.base, identity.path);
    return 0;
}

static int SameImage(const char* expected, const char* actual)
{
    struct stat expectedStat;
    struct stat actualStat;
    return stat(expected, &expectedStat) == 0 && stat(actual, &actualStat) == 0 &&
        expectedStat.st_dev == actualStat.st_dev && expectedStat.st_ino == actualStat.st_ino;
}

int32_t CJRT_ContractVerifyRuntimeImage(void* callback)
{
    const char* wakeSymbols[] = {
        "MRT_ResumeAll",
        "CJ_WaitqueueWakeAll",
        "CJ_CJThreadReady",
        "CJ_ProcessorWake",
        "MRT_GetThreadLocalData",
        "GetTaskRet",
        "ReleaseHandle",
    };
    const char* ownershipSymbolsS4[] = {
        "InitCJRuntime",
        "RunCJTaskToSchedule",
        "MRT_StopSubScheduler",
        "CJCJ_MRT_InstanceNew",
        "CJCJ_MRT_InstanceRunTask",
        "CJCJ_MRT_InstanceStop",
    };
    const char* ownershipSymbolsOfficial[] = {
        "InitCJRuntime",
        "RunCJTaskToSchedule",
        "MRT_StopSubScheduler",
        "MRT_RuntimeNewSubScheduler",
    };
    const char* runtimePath = getenv("CJCJ_CONTRACT_RUNTIME_IMAGE");
    if (runtimePath == NULL || *runtimePath == '\0') {
        fprintf(stderr, "MANAGED_CONTRACT FAIL stage=runtime_image_path\n");
        return 1;
    }
    runtimeImageHandle = dlopen(runtimePath, RTLD_NOW | RTLD_LOCAL);
    if (runtimeImageHandle == NULL) {
        fprintf(stderr, "MANAGED_CONTRACT FAIL stage=runtime_image_open path=%s detail=%s\n",
            runtimePath, dlerror());
        return 1;
    }

    struct RuntimeImageAudit audit = {0};
    dl_iterate_phdr(CountRuntimeImages, &audit);
    if (audit.failed || audit.imageCount != 1) {
        fprintf(stderr, "MANAGED_CONTRACT FAIL stage=runtime_image_count count=%d\n", audit.imageCount);
        return 1;
    }

    Dl_info callbackInfo;
    if (dladdr(callback, &callbackInfo) == 0) {
        return 1;
    }
    printf("MANAGED_IMAGE callback=%p image=%s\n", callback,
        callbackInfo.dli_fname == NULL ? "<unknown>" : callbackInfo.dli_fname);

    const char* runtimeImage = audit.images[0].path;
    int32_t mode = CJRT_ContractMode();
    const char** ownershipSymbols = mode == CONTRACT_S4 ? ownershipSymbolsS4 : ownershipSymbolsOfficial;
    size_t ownershipSymbolCount = mode == CONTRACT_S4 ?
        sizeof(ownershipSymbolsS4) / sizeof(ownershipSymbolsS4[0]) :
        sizeof(ownershipSymbolsOfficial) / sizeof(ownershipSymbolsOfficial[0]);
    const char* negativeSymbol = getenv("CJCJ_CONTRACT_NEGATIVE_SYMBOL");
    for (size_t index = 0; index < ownershipSymbolCount; ++index) {
        void* address = negativeSymbol != NULL && strcmp(negativeSymbol, ownershipSymbols[index]) == 0 ?
            callback : Resolve(ownershipSymbols[index]);
        Dl_info info;
        if (address == NULL || dladdr(address, &info) == 0 || info.dli_fname == NULL) {
            return 1;
        }
        if (!SameImage(runtimeImage, info.dli_fname)) {
            fprintf(stderr, "MANAGED_CONTRACT FAIL stage=runtime_symbol_image symbol=%s image=%s expected=%s\n",
                ownershipSymbols[index], info.dli_fname, runtimeImage);
            return 1;
        }
        printf("MANAGED_IMAGE symbol=%s address=%p image=%s\n",
            ownershipSymbols[index], address, info.dli_fname);
    }

    for (size_t index = 0; index < sizeof(wakeSymbols) / sizeof(wakeSymbols[0]); ++index) {
        void* address = Resolve(wakeSymbols[index]);
        Dl_info info;
        if (address == NULL || dladdr(address, &info) == 0 || info.dli_fname == NULL ||
            !SameImage(runtimeImage, info.dli_fname)) {
            fprintf(stderr, "MANAGED_CONTRACT FAIL stage=runtime_symbol_image symbol=%s\n", wakeSymbols[index]);
            return 1;
        }
        printf("MANAGED_IMAGE symbol=%s address=%p image=%s\n",
            wakeSymbols[index], address, info.dli_fname);
    }

    struct ThreadLocalDataPrefix* threadLocal = CurrentThreadLocalData();
    if (threadLocal == NULL || threadLocal->schedule == NULL) {
        fprintf(stderr, "MANAGED_CONTRACT FAIL stage=runtime_singleton_owner\n");
        return 1;
    }
    printf("MANAGED_SINGLETON schedule=%p cjthread=%p image=%s\n",
        threadLocal->schedule, threadLocal->cjthread, runtimeImage);
    fflush(stdout);
    return 0;
}

void CJRT_ContractStage(int32_t stage, int32_t cycle, uintptr_t schedule,
    uintptr_t cjthread, int32_t state, uint64_t osThread)
{
    static const char* names[] = {
        "invalid",
        "waiter_ready",
        "instance_created",
        "task_submitted",
        "waiter_pending",
        "callback_entered",
        "state_updated",
        "notify_entered",
        "notify_returned",
        "waiter_resumed",
        "return_matched",
        "handle_released",
        "instance_stopped",
    };
    const char* name = stage > 0 && (size_t)stage < sizeof(names) / sizeof(names[0]) ?
        names[stage] : names[0];
    printf("MANAGED_STAGE stage=%s cycle=%d schedule=0x%" PRIxPTR
           " cjthread=0x%" PRIxPTR " state=%d os_tid=%" PRIu64 "\n",
        name, cycle, schedule, cjthread, state, osThread);
    fflush(stdout);
}

void CJRT_ContractPass(int32_t mode, int32_t cycles, uint64_t rssBefore, uint64_t rssAfter)
{
    uint64_t growth = rssAfter > rssBefore ? rssAfter - rssBefore : 0;
    printf("MANAGED_CONTRACT PASS mode=%s cycles=%d condition=notifyAll distinct_schedule=PASS "
           "return_identity=PASS handle_release=PASS stop=PASS rss_before=%" PRIu64
           " rss_after=%" PRIu64 " rss_growth=%" PRIu64 " rss_limit=%u\n",
        mode == CONTRACT_S4 ? "s4" : "official", cycles, rssBefore, rssAfter, growth,
        8U * 1024U * 1024U);
    fflush(stdout);
}
