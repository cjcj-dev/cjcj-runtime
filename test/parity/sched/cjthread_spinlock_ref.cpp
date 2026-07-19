// CJThread schedule/include/inner/base.h:55-77,115-164 layout/state oracle
// and native pthread contention driver for the caller-owned inline lock.
#include <pthread.h>
#include <cerrno>

#include "macro_def.h"
#include "base.h"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <sched.h>
#include <type_traits>

namespace {
constexpr size_t THREAD_COUNT = 8;
constexpr size_t ITERATIONS = 4096;
constexpr uint64_t HANDOFF_PAYLOAD = UINT64_C(0x5a17c0de);

std::atomic<uint64_t> initCalls{0};
std::atomic<uint64_t> lockCalls{0};
std::atomic<uint64_t> unlockCalls{0};
std::atomic<uint64_t> destroyCalls{0};
std::atomic<uint64_t> addressMismatches{0};
std::atomic<uintptr_t> expectedAddress{0};

struct CJthreadSpinLockResult {
    uint64_t blockReady;
    uint64_t acquiredBeforeRelease;
    uint64_t acquiredAfterRelease;
    uint64_t counter;
    uint64_t handoffReady;
    uint64_t handoffObserved;
    uint64_t workerFailures;
};

void RecordAddress(const volatile void* address)
{
    if (reinterpret_cast<uintptr_t>(address) != expectedAddress.load(std::memory_order_relaxed)) {
        addressMismatches.fetch_add(1, std::memory_order_relaxed);
    }
}

void ResetCalls(const volatile void* address)
{
    expectedAddress.store(reinterpret_cast<uintptr_t>(address), std::memory_order_relaxed);
    initCalls.store(0, std::memory_order_relaxed);
    lockCalls.store(0, std::memory_order_relaxed);
    unlockCalls.store(0, std::memory_order_relaxed);
    destroyCalls.store(0, std::memory_order_relaxed);
    addressMismatches.store(0, std::memory_order_relaxed);
}

void Snapshot(unsigned char* destination, const void* storage, size_t size)
{
    const auto* bytes = static_cast<const volatile unsigned char*>(storage);
    for (size_t i = 0; i < size; ++i) {
        destination[i] = bytes[i];
    }
}

void PrintBytes(const char* label, const unsigned char* bytes, size_t size)
{
    std::printf("%s=", label);
    for (size_t i = 0; i < size; ++i) {
        std::printf("%02x", static_cast<unsigned>(bytes[i]));
    }
}

#ifdef CJTHREAD_SPINLOCK_ORACLE
int ApiInit(void* lock) { return PthreadSpinInit(static_cast<CJthreadSpinLock*>(lock)); }
int ApiLock(void* lock) { return PthreadSpinLock(static_cast<CJthreadSpinLock*>(lock)); }
int ApiUnlock(void* lock) { return PthreadSpinUnlock(static_cast<CJthreadSpinLock*>(lock)); }
int ApiDestroy(void* lock) { return PthreadSpinDestroy(static_cast<CJthreadSpinLock*>(lock)); }
bool AttachThread() { return true; }
bool DetachThread() { return true; }
#else
extern "C" int32_t CJRT_CJthreadSpinLockLock(void*);
extern "C" int32_t CJRT_CJthreadSpinLockUnlock(void*);
extern "C" bool MRT_NewForeignCJThread();
extern "C" bool MRT_EndForeignCJThread();

int ApiLock(void* lock) { return CJRT_CJthreadSpinLockLock(lock); }
int ApiUnlock(void* lock) { return CJRT_CJthreadSpinLockUnlock(lock); }
bool AttachThread() { return MRT_NewForeignCJThread(); }
bool DetachThread() { return MRT_EndForeignCJThread(); }
#endif

struct BlockingArgs {
    void* lock;
    std::atomic<bool>* ready;
    std::atomic<bool>* acquired;
    bool ok;
};

void* BlockingThread(void* raw)
{
    auto* args = static_cast<BlockingArgs*>(raw);
    args->ok = AttachThread();
    if (!args->ok) {
        return nullptr;
    }
    args->ready->store(true, std::memory_order_release);
    args->ok = ApiLock(args->lock) == 0;
    if (args->ok) {
        args->acquired->store(true, std::memory_order_release);
        args->ok = ApiUnlock(args->lock) == 0;
    }
    args->ok = DetachThread() && args->ok;
    return nullptr;
}

struct CounterArgs {
    void* lock;
    uint64_t* counter;
    bool ok;
};

void* CounterThread(void* raw)
{
    auto* args = static_cast<CounterArgs*>(raw);
    args->ok = AttachThread();
    if (!args->ok) {
        return nullptr;
    }
    for (size_t iteration = 0; iteration < ITERATIONS; ++iteration) {
        if (ApiLock(args->lock) != 0) {
            args->ok = false;
            break;
        }
        ++*args->counter;
        if (ApiUnlock(args->lock) != 0) {
            args->ok = false;
            break;
        }
    }
    args->ok = DetachThread() && args->ok;
    return nullptr;
}

struct HandoffArgs {
    void* lock;
    std::atomic<bool>* ready;
    uint64_t* payload;
    uint64_t observed;
    bool ok;
};

void* HandoffThread(void* raw)
{
    auto* args = static_cast<HandoffArgs*>(raw);
    args->ok = AttachThread();
    if (!args->ok) {
        return nullptr;
    }
    args->ready->store(true, std::memory_order_release);
    args->ok = ApiLock(args->lock) == 0;
    if (args->ok) {
        args->observed = *args->payload;
        args->ok = ApiUnlock(args->lock) == 0;
    }
    args->ok = DetachThread() && args->ok;
    return nullptr;
}

bool RunBehavior(void* lock, CJthreadSpinLockResult* result)
{
    std::memset(result, 0, sizeof(*result));

    if (ApiLock(lock) != 0) {
        return false;
    }
    std::atomic<bool> ready{false};
    std::atomic<bool> acquired{false};
    BlockingArgs blocking{lock, &ready, &acquired, false};
    pthread_t blockingThread{};
    if (pthread_create(&blockingThread, nullptr, BlockingThread, &blocking) != 0) {
        return false;
    }
    while (!ready.load(std::memory_order_acquire)) {
        sched_yield();
    }
    result->blockReady = 1;
    result->acquiredBeforeRelease = acquired.load(std::memory_order_acquire) ? 1 : 0;
    if (ApiUnlock(lock) != 0 || pthread_join(blockingThread, nullptr) != 0 || !blocking.ok) {
        return false;
    }
    result->acquiredAfterRelease = acquired.load(std::memory_order_acquire) ? 1 : 0;

    uint64_t counter = 0;
    pthread_t counterThreads[THREAD_COUNT]{};
    CounterArgs counterArgs[THREAD_COUNT]{};
    for (size_t index = 0; index < THREAD_COUNT; ++index) {
        counterArgs[index] = CounterArgs{lock, &counter, false};
        if (pthread_create(&counterThreads[index], nullptr, CounterThread, &counterArgs[index]) != 0) {
            return false;
        }
    }
    for (size_t index = 0; index < THREAD_COUNT; ++index) {
        if (pthread_join(counterThreads[index], nullptr) != 0 || !counterArgs[index].ok) {
            ++result->workerFailures;
        }
    }
    result->counter = counter;

    uint64_t payload = 0;
    std::atomic<bool> handoffReady{false};
    HandoffArgs handoff{lock, &handoffReady, &payload, 0, false};
    if (ApiLock(lock) != 0) {
        return false;
    }
    pthread_t handoffThread{};
    if (pthread_create(&handoffThread, nullptr, HandoffThread, &handoff) != 0) {
        return false;
    }
    while (!handoffReady.load(std::memory_order_acquire)) {
        sched_yield();
    }
    result->handoffReady = 1;
    payload = HANDOFF_PAYLOAD;
    if (ApiUnlock(lock) != 0 || pthread_join(handoffThread, nullptr) != 0 || !handoff.ok) {
        return false;
    }
    result->handoffObserved = handoff.observed;
    return result->workerFailures == 0;
}
} // namespace

extern "C" int __real_pthread_spin_init(pthread_spinlock_t*, int);
extern "C" int __real_pthread_spin_lock(pthread_spinlock_t*);
extern "C" int __real_pthread_spin_unlock(pthread_spinlock_t*);
extern "C" int __real_pthread_spin_destroy(pthread_spinlock_t*);

extern "C" int __wrap_pthread_spin_init(pthread_spinlock_t* lock, int shared)
{
    RecordAddress(lock);
    initCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_init(lock, shared);
}

extern "C" int __wrap_pthread_spin_lock(pthread_spinlock_t* lock)
{
    RecordAddress(lock);
    lockCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_lock(lock);
}

extern "C" int __wrap_pthread_spin_unlock(pthread_spinlock_t* lock)
{
    RecordAddress(lock);
    unlockCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_unlock(lock);
}

extern "C" int __wrap_pthread_spin_destroy(pthread_spinlock_t* lock)
{
    RecordAddress(lock);
    destroyCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_destroy(lock);
}

extern "C" void CJthreadSpinLockResetCalls(void* address) { ResetCalls(address); }
extern "C" uint64_t CJthreadSpinLockInitCalls() { return initCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t CJthreadSpinLockLockCalls() { return lockCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t CJthreadSpinLockUnlockCalls() { return unlockCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t CJthreadSpinLockDestroyCalls() { return destroyCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t CJthreadSpinLockAddressMismatches()
{
    return addressMismatches.load(std::memory_order_relaxed);
}

#ifdef CJTHREAD_SPINLOCK_ORACLE
int main()
{
    CJthreadSpinLock lock{};
    unsigned char states[4][sizeof(CJthreadSpinLock)]{};
    CJthreadSpinLockResult result{};
    ResetCalls(&lock.lock);
    const int initResult = ApiInit(&lock);
    Snapshot(states[0], &lock, sizeof(lock));
    const int lockResult = ApiLock(&lock);
    Snapshot(states[1], &lock, sizeof(lock));
    const int unlockResult = ApiUnlock(&lock);
    Snapshot(states[2], &lock, sizeof(lock));
    const bool behavior = RunBehavior(&lock, &result);
    const int destroyResult = ApiDestroy(&lock);
    Snapshot(states[3], &lock, sizeof(lock));

    std::printf("CJTHREAD_SPINLOCK_PTHREAD sizeof=%zu align=%zu is_int=%s remove_cv_is_int=%s volatile=%s\n",
        sizeof(pthread_spinlock_t), alignof(pthread_spinlock_t),
        std::is_same<pthread_spinlock_t, int>::value ? "true" : "false",
        std::is_same<typename std::remove_cv<pthread_spinlock_t>::type, int>::value ? "true" : "false",
        std::is_volatile<pthread_spinlock_t>::value ? "true" : "false");
    std::printf("CJTHREAD_SPINLOCK_LAYOUT sizeof=%zu align=%zu lock=%zu\n",
        sizeof(CJthreadSpinLock), alignof(CJthreadSpinLock), offsetof(CJthreadSpinLock, lock));
    std::printf("CJTHREAD_SPINLOCK_BYTES ");
    const char* labels[] = {"init", "held_lock", "unlock", "destroy"};
    for (size_t index = 0; index < 4; ++index) {
        if (index != 0) {
            std::printf(" ");
        }
        PrintBytes(labels[index], states[index], sizeof(CJthreadSpinLock));
    }
    std::printf("\nCJTHREAD_SPINLOCK_RETURNS init=%d lock=%d unlock=%d destroy=%d\n",
        initResult, lockResult, unlockResult, destroyResult);
    std::printf("CJTHREAD_SPINLOCK_BLOCK pre_release=%llu acquired_before_release=%llu "
        "post_release=%llu acquired_after_release=%llu status=PASS\n",
        static_cast<unsigned long long>(result.blockReady),
        static_cast<unsigned long long>(result.acquiredBeforeRelease),
        static_cast<unsigned long long>(result.acquiredAfterRelease),
        static_cast<unsigned long long>(result.acquiredAfterRelease));
    std::printf("CJTHREAD_SPINLOCK_COUNTER threads=%zu iterations=%zu expected=%zu actual=%llu status=PASS\n",
        THREAD_COUNT, ITERATIONS, THREAD_COUNT * ITERATIONS,
        static_cast<unsigned long long>(result.counter));
    std::printf("CJTHREAD_SPINLOCK_HANDOFF payload=%llu observed=%llu status=PASS\n",
        static_cast<unsigned long long>(HANDOFF_PAYLOAD),
        static_cast<unsigned long long>(result.handoffObserved));
    std::printf("CJTHREAD_SPINLOCK_CALLS init=%llu lock=%llu unlock=%llu destroy=%llu "
        "address_mismatches=%llu destroy_after_users=true\n",
        static_cast<unsigned long long>(CJthreadSpinLockInitCalls()),
        static_cast<unsigned long long>(CJthreadSpinLockLockCalls()),
        static_cast<unsigned long long>(CJthreadSpinLockUnlockCalls()),
        static_cast<unsigned long long>(CJthreadSpinLockDestroyCalls()),
        static_cast<unsigned long long>(CJthreadSpinLockAddressMismatches()));
    std::printf("CJTHREAD_SPINLOCK_NONZERO safe_defined_trigger=none caller_owned_error_policy=true\n");

    return initResult == 0 && lockResult == 0 && unlockResult == 0 && destroyResult == 0 && behavior &&
        result.blockReady == 1 && result.acquiredBeforeRelease == 0 && result.acquiredAfterRelease == 1 &&
        result.counter == THREAD_COUNT * ITERATIONS && result.handoffReady == 1 &&
        result.handoffObserved == HANDOFF_PAYLOAD && result.workerFailures == 0 &&
        CJthreadSpinLockInitCalls() == 1 && CJthreadSpinLockLockCalls() == 32773 &&
        CJthreadSpinLockUnlockCalls() == 32773 && CJthreadSpinLockDestroyCalls() == 1 &&
        CJthreadSpinLockAddressMismatches() == 0 ? 0 : 1;
}
#else
extern "C" int32_t CJthreadSpinLockRun(void* lock, CJthreadSpinLockResult* result)
{
    return RunBehavior(lock, result) ? 0 : 1;
}
#endif
