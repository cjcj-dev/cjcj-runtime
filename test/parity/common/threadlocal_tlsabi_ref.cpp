// Mutator/ThreadLocal.h:18-102 executable oracle and Cangjie helper driver.
#include "Mutator/ThreadLocal.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <pthread.h>

using MapleRuntime::ThreadLocal;
using MapleRuntime::ThreadLocalData;
using MapleRuntime::ThreadType;

extern "C" uintptr_t MRT_GetThreadLocalData();
extern "C" void CJ_MCC_CheckThreadLocalDataOffset();
extern "C" bool MRT_NewForeignCJThread();
extern "C" bool MRT_EndForeignCJThread();

#ifndef THREADLOCAL_ORACLE
extern "C" uintptr_t CJRT_ThreadLocalGetAddress();
extern "C" void CJRT_ThreadLocalCheckOffset();
extern "C" uint64_t CJRT_ThreadLocalExercise(uintptr_t);
#endif

namespace {
constexpr size_t THREAD_COUNT = 8;
constexpr size_t RECORD_SIZE = 88;

struct ThreadResult {
    uintptr_t address;
    bool helpers;
    bool adjacent;
    bool restored;
    bool isolated;
};

std::array<ThreadResult, THREAD_COUNT> results{};
pthread_barrier_t cacheBarrier;

uintptr_t ApiAddress()
{
#ifdef THREADLOCAL_ORACLE
    return reinterpret_cast<uintptr_t>(ThreadLocal::GetThreadLocalData());
#else
    return CJRT_ThreadLocalGetAddress();
#endif
}

void ApiCheckOffset()
{
#ifdef THREADLOCAL_ORACLE
    CJ_MCC_CheckThreadLocalDataOffset();
#else
    CJRT_ThreadLocalCheckOffset();
#endif
}

#ifdef THREADLOCAL_ORACLE
uintptr_t ApiSetPointer(int32_t field, uintptr_t value)
{
#ifdef THREADLOCAL_ORACLE
    void* pointer = reinterpret_cast<void*>(value);
    switch (field) {
        case 0:
            ThreadLocal::SetAllocBuffer(reinterpret_cast<MapleRuntime::AllocBuffer*>(pointer));
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetAllocBuffer());
        case 1:
            ThreadLocal::SetMutator(reinterpret_cast<MapleRuntime::Mutator*>(pointer));
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetMutator());
        case 2:
            ThreadLocal::SetProtectAddr(reinterpret_cast<uint8_t*>(pointer));
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetThreadLocalData()->protectAddr);
        case 3:
            ThreadLocal::SetForeignCJThread(pointer);
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetForeignCJThread());
        case 4:
            ThreadLocal::SetCJThread(pointer);
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetThreadLocalData()->cjthread);
        case 5:
            ThreadLocal::SetSchedule(pointer);
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetSchedule());
        default:
            return reinterpret_cast<uintptr_t>(ThreadLocal::SetThreadCache(pointer));
    }
#else
    return CJRT_ThreadLocalSetPointer(field, value);
#endif
}

uintptr_t ApiGetPointer(int32_t field)
{
#ifdef THREADLOCAL_ORACLE
    switch (field) {
        case 0:
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetAllocBuffer());
        case 1:
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetMutator());
        case 2:
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetPreemptFlag());
        case 3:
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetForeignCJThread());
        case 4:
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetSchedule());
        default:
            return reinterpret_cast<uintptr_t>(ThreadLocal::GetThreadCache());
    }
#else
    return CJRT_ThreadLocalGetPointer(field);
#endif
}

void ApiSetThreadType(int32_t value)
{
#ifdef THREADLOCAL_ORACLE
    ThreadLocal::SetThreadType(static_cast<ThreadType>(value));
#else
    CJRT_ThreadLocalSetThreadType(value);
#endif
}

int32_t ApiGetThreadType()
{
#ifdef THREADLOCAL_ORACLE
    return static_cast<int32_t>(ThreadLocal::GetThreadType());
#else
    return CJRT_ThreadLocalGetThreadType();
#endif
}

void ApiSetProcessorFlag(bool value)
{
#ifdef THREADLOCAL_ORACLE
    ThreadLocal::SetCJProcessorFlag(value);
#else
    CJRT_ThreadLocalSetProcessorFlag(value);
#endif
}

bool ApiIsProcessor()
{
#ifdef THREADLOCAL_ORACLE
    return ThreadLocal::IsCJProcessor();
#else
    return CJRT_ThreadLocalIsProcessor();
#endif
}

bool OutsideFieldUnchanged(const unsigned char* before, const unsigned char* after,
    size_t offset, size_t width)
{
    for (size_t index = 0; index < RECORD_SIZE; ++index) {
        if ((index < offset || index >= offset + width) && before[index] != after[index]) {
            return false;
        }
    }
    return true;
}

void RestoreField(unsigned char* record, const unsigned char* original, size_t offset, size_t width)
{
    std::memcpy(record + offset, original + offset, width);
}

bool CheckPointerField(unsigned char* record, size_t offset, int32_t setField,
    int32_t getField, uintptr_t sentinel, bool& adjacent)
{
    unsigned char before[RECORD_SIZE];
    unsigned char after[RECORD_SIZE];
    unsigned char originalField[sizeof(uintptr_t)];
    std::memcpy(before, record, RECORD_SIZE);
    std::memcpy(originalField, record + offset, sizeof(originalField));
    uintptr_t returned = ApiSetPointer(setField, sentinel);
    std::memcpy(after, record, RECORD_SIZE);
    uintptr_t stored = 0;
    std::memcpy(&stored, record + offset, sizeof(stored));
    adjacent = adjacent && OutsideFieldUnchanged(before, after, offset, sizeof(uintptr_t));
    bool pass = returned == sentinel && stored == sentinel;
    if (getField >= 0) {
        std::memcpy(before, record, RECORD_SIZE);
        pass = pass && ApiGetPointer(getField) == sentinel;
        std::memcpy(after, record, RECORD_SIZE);
        adjacent = adjacent && std::memcmp(before, after, RECORD_SIZE) == 0;
    }
    std::memcpy(record + offset, originalField, sizeof(originalField));
    return pass;
}
#endif

void* RunThread(void* argument)
{
    size_t index = reinterpret_cast<uintptr_t>(argument);
    ThreadResult result{0, true, true, false, false};
#ifndef THREADLOCAL_ORACLE
    if (!MRT_NewForeignCJThread()) {
        result.helpers = false;
        results[index] = result;
        return nullptr;
    }
    result.address = ApiAddress();
    uint64_t exercise = CJRT_ThreadLocalExercise(index);
    result.helpers = (exercise & UINT64_C(1)) != 0 &&
        result.address == MRT_GetThreadLocalData();
    result.adjacent = (exercise & UINT64_C(2)) != 0;
    result.restored = (exercise & UINT64_C(4)) != 0;
    result.isolated = (exercise & UINT64_C(8)) != 0;
    result.helpers = result.helpers && (exercise & UINT64_C(16)) != 0 &&
        MRT_EndForeignCJThread();
    results[index] = result;
    return nullptr;
#endif
#ifdef THREADLOCAL_ORACLE
    result.address = ApiAddress();
    auto* record = reinterpret_cast<unsigned char*>(result.address);
    if (record == nullptr || result.address != MRT_GetThreadLocalData()) {
        result.helpers = false;
#ifndef THREADLOCAL_ORACLE
        MRT_EndForeignCJThread();
#endif
        results[index] = result;
        return nullptr;
    }

    unsigned char original[RECORD_SIZE];
    unsigned char before[RECORD_SIZE];
    unsigned char after[RECORD_SIZE];
    std::memcpy(original, record, RECORD_SIZE);
    std::memcpy(before, record, RECORD_SIZE);
    result.helpers = result.helpers && ApiAddress() == result.address;
    std::memcpy(after, record, RECORD_SIZE);
    result.adjacent = result.adjacent && std::memcmp(before, after, RECORD_SIZE) == 0;

    for (int32_t field = 0; field <= 5; ++field) {
        static const size_t offsets[] = {0, 8, 40, 64, 16, 24};
        static const int32_t getters[] = {0, 1, -1, 3, -1, 4};
        uintptr_t sentinel = static_cast<uintptr_t>(0x10000000) + (index << 16) +
            (static_cast<uintptr_t>(field) << 8) + static_cast<uintptr_t>(0x5a);
        result.helpers = result.helpers && CheckPointerField(record, offsets[field], field,
            getters[field], sentinel, result.adjacent);
    }

    uintptr_t preemptSentinel = static_cast<uintptr_t>(0x20000000) + (index << 16) +
        static_cast<uintptr_t>(0x5a);
    std::memcpy(record + offsetof(ThreadLocalData, preemptFlag), &preemptSentinel,
        sizeof(preemptSentinel));
    std::memcpy(before, record, RECORD_SIZE);
    result.helpers = result.helpers && ApiGetPointer(2) == preemptSentinel;
    std::memcpy(after, record, RECORD_SIZE);
    result.adjacent = result.adjacent && std::memcmp(before, after, RECORD_SIZE) == 0;
    RestoreField(record, original, offsetof(ThreadLocalData, preemptFlag), sizeof(uintptr_t));

    int32_t typeSentinel = INT32_C(0x30000000) + static_cast<int32_t>(index);
    std::memcpy(before, record, RECORD_SIZE);
    ApiSetThreadType(typeSentinel);
    std::memcpy(after, record, RECORD_SIZE);
    result.adjacent = result.adjacent && OutsideFieldUnchanged(before, after,
        offsetof(ThreadLocalData, threadType), sizeof(int32_t));
    result.helpers = result.helpers && ApiGetThreadType() == typeSentinel;
    RestoreField(record, original, offsetof(ThreadLocalData, threadType), sizeof(int32_t));

    std::memcpy(before, record, RECORD_SIZE);
    ApiSetProcessorFlag(true);
    std::memcpy(after, record, RECORD_SIZE);
    result.adjacent = result.adjacent && OutsideFieldUnchanged(before, after,
        offsetof(ThreadLocalData, isCJProcessor), sizeof(bool));
    result.helpers = result.helpers && ApiIsProcessor();
    RestoreField(record, original, offsetof(ThreadLocalData, isCJProcessor), sizeof(bool));

    uintptr_t cacheSentinel = static_cast<uintptr_t>(0x40000000) + (index << 16) +
        static_cast<uintptr_t>(0x5a);
    result.helpers = result.helpers && CheckPointerField(record,
        offsetof(ThreadLocalData, threadCache), 6, -1, cacheSentinel, result.adjacent);
    result.helpers = result.helpers && ApiSetPointer(6, cacheSentinel) == cacheSentinel;
    pthread_barrier_wait(&cacheBarrier);
    result.isolated = ApiGetPointer(5) == cacheSentinel;
    pthread_barrier_wait(&cacheBarrier);

    std::memcpy(record, original, RECORD_SIZE);
    result.restored = std::memcmp(record, original, RECORD_SIZE) == 0;
#ifndef THREADLOCAL_ORACLE
    result.helpers = result.helpers && MRT_EndForeignCJThread();
#endif
    results[index] = result;
    return nullptr;
#endif
}

int RunProbe()
{
    static_assert(sizeof(ThreadType) == 4 && alignof(ThreadType) == 4, "ThreadType ABI");
    static_assert(sizeof(ThreadLocalData) == 88 && alignof(ThreadLocalData) == 8,
        "ThreadLocalData ABI");
    static_assert(offsetof(ThreadLocalData, buffer) == 0 &&
        offsetof(ThreadLocalData, mutator) == 8 && offsetof(ThreadLocalData, cjthread) == 16 &&
        offsetof(ThreadLocalData, schedule) == 24 && offsetof(ThreadLocalData, preemptFlag) == 32 &&
        offsetof(ThreadLocalData, protectAddr) == 40 &&
        offsetof(ThreadLocalData, safepointState) == 48 && offsetof(ThreadLocalData, tid) == 56 &&
        offsetof(ThreadLocalData, foreignCJThread) == 64 &&
        offsetof(ThreadLocalData, threadType) == 72 &&
        offsetof(ThreadLocalData, isCJProcessor) == 76 &&
        offsetof(ThreadLocalData, threadCache) == 80, "ThreadLocalData offsets");

#ifdef THREADLOCAL_ORACLE
    constexpr size_t layoutSize = sizeof(ThreadLocalData);
    constexpr size_t layoutAlign = alignof(ThreadLocalData);
    constexpr size_t layoutBuffer = offsetof(ThreadLocalData, buffer);
    constexpr size_t layoutMutator = offsetof(ThreadLocalData, mutator);
    constexpr size_t layoutCJThread = offsetof(ThreadLocalData, cjthread);
    constexpr size_t layoutSchedule = offsetof(ThreadLocalData, schedule);
    constexpr size_t layoutPreempt = offsetof(ThreadLocalData, preemptFlag);
    constexpr size_t layoutProtect = offsetof(ThreadLocalData, protectAddr);
    constexpr size_t layoutSafepoint = offsetof(ThreadLocalData, safepointState);
    constexpr size_t layoutTid = offsetof(ThreadLocalData, tid);
    constexpr size_t layoutForeign = offsetof(ThreadLocalData, foreignCJThread);
    constexpr size_t layoutType = offsetof(ThreadLocalData, threadType);
    constexpr size_t layoutProcessor = offsetof(ThreadLocalData, isCJProcessor);
    constexpr size_t layoutCache = offsetof(ThreadLocalData, threadCache);
#else
    constexpr size_t layoutSize = CJ_TLS_SIZE;
    constexpr size_t layoutAlign = CJ_TLS_ALIGN;
    constexpr size_t layoutBuffer = CJ_TLS_BUFFER;
    constexpr size_t layoutMutator = CJ_TLS_MUTATOR;
    constexpr size_t layoutCJThread = CJ_TLS_CJTHREAD;
    constexpr size_t layoutSchedule = CJ_TLS_SCHEDULE;
    constexpr size_t layoutPreempt = CJ_TLS_PREEMPT;
    constexpr size_t layoutProtect = CJ_TLS_PROTECT;
    constexpr size_t layoutSafepoint = CJ_TLS_SAFEPOINT;
    constexpr size_t layoutTid = CJ_TLS_TID;
    constexpr size_t layoutForeign = CJ_TLS_FOREIGN;
    constexpr size_t layoutType = CJ_TLS_TYPE;
    constexpr size_t layoutProcessor = CJ_TLS_PROCESSOR;
    constexpr size_t layoutCache = CJ_TLS_CACHE;
#endif
    std::printf("ThreadLocalData sizeof=%zu align=%zu buffer=%zu mutator=%zu cjthread=%zu "
        "schedule=%zu preemptFlag=%zu protectAddr=%zu safepointState=%zu tid=%zu "
        "foreignCJThread=%zu threadType=%zu isCJProcessor=%zu threadCache=%zu\n",
        layoutSize, layoutAlign, layoutBuffer, layoutMutator, layoutCJThread, layoutSchedule,
        layoutPreempt, layoutProtect, layoutSafepoint, layoutTid, layoutForeign, layoutType,
        layoutProcessor, layoutCache);
    std::printf("THREADTYPE CJ_PROCESSOR=%d GC_THREAD=%d FP_THREAD=%d HOT_UPDATE_THREAD=%d "
        "sizeof=%zu align=%zu\n", static_cast<int>(ThreadType::CJ_PROCESSOR),
        static_cast<int>(ThreadType::GC_THREAD), static_cast<int>(ThreadType::FP_THREAD),
        static_cast<int>(ThreadType::HOT_UPDATE_THREAD), sizeof(ThreadType), alignof(ThreadType));

    ApiCheckOffset();
    bool runtimeCallable = ApiAddress() != 0 && MRT_GetThreadLocalData() != 0;
    std::printf("THREADLOCAL_RUNTIME static_assert=PASS mrt_get_callable=%d\n",
        runtimeCallable ? 1 : 0);
    if (!runtimeCallable || pthread_barrier_init(&cacheBarrier, nullptr, THREAD_COUNT) != 0) {
        return 1;
    }

    std::array<pthread_t, THREAD_COUNT> threads{};
    for (size_t index = 0; index < THREAD_COUNT; ++index) {
        if (pthread_create(&threads[index], nullptr, RunThread,
                reinterpret_cast<void*>(index)) != 0) {
            return 2;
        }
    }
    for (pthread_t thread : threads) {
        if (pthread_join(thread, nullptr) != 0) {
            return 3;
        }
    }
    pthread_barrier_destroy(&cacheBarrier);

    size_t nonnull = 0;
    size_t distinctPairs = 0;
    size_t isolated = 0;
    bool pass = true;
    for (size_t index = 0; index < THREAD_COUNT; ++index) {
        nonnull += results[index].address != 0 ? 1 : 0;
        isolated += results[index].isolated ? 1 : 0;
        pass = pass && results[index].helpers && results[index].adjacent &&
            results[index].restored && results[index].isolated;
        for (size_t other = index + 1; other < THREAD_COUNT; ++other) {
            distinctPairs += results[index].address != results[other].address ? 1 : 0;
        }
        std::printf("THREADLOCAL_THREAD index=%zu helpers=%s adjacent=%s restore=%s "
            "threadCache=%s\n", index, results[index].helpers ? "PASS" : "FAIL",
            results[index].adjacent ? "PASS" : "FAIL",
            results[index].restored ? "PASS" : "FAIL",
            results[index].isolated ? "PASS" : "FAIL");
    }
    pass = pass && nonnull == THREAD_COUNT && distinctPairs == 28 && isolated == THREAD_COUNT;
    std::printf("THREADLOCAL_TLS threads=%zu nonnull=%zu pairwise_distinct=%zu "
        "threadCache_isolated=%zu status=%s\n", THREAD_COUNT, nonnull, distinctPairs,
        isolated, pass ? "PASS" : "FAIL");
    std::printf("THREADLOCAL_BEHAVIOR helpers=18 transcript=deterministic status=%s\n",
        pass ? "PASS" : "FAIL");
    return pass ? 0 : 4;
}
} // namespace

#ifndef THREADLOCAL_ORACLE
extern "C" void ThreadLocalTLSABIBarrier()
{
    pthread_barrier_wait(&cacheBarrier);
}
#endif

#ifdef THREADLOCAL_ORACLE
int main()
{
    return RunProbe();
}
#else
extern "C" int ThreadLocalTLSABIProbeMain()
{
    return RunProbe();
}
#endif
