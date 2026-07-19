// Base/SpinLock.h:15-39 executable layout/state oracle and native pthread driver.
#include <pthread.h>
#include "Base/Macros.h"
#define private public
#include "Base/SpinLock.h"
#undef private

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <new>
#include <sched.h>
#include <type_traits>

namespace {
constexpr size_t THREAD_COUNT = 4;
constexpr size_t ITERATIONS = 4096;
constexpr uint64_t HANDOFF_PAYLOAD = UINT64_C(0x5a17c0de);

std::atomic<uint64_t> initCalls{0};
std::atomic<uint64_t> destroyCalls{0};
std::atomic<uint64_t> lockCalls{0};
std::atomic<uint64_t> unlockCalls{0};
std::atomic<uint64_t> tryCalls{0};

struct SpinLockResult {
    uint64_t blockReady;
    uint64_t acquiredBeforeRelease;
    uint64_t acquiredAfterRelease;
    uint64_t counter;
    uint64_t counterFinalState;
    uint64_t handoffReady;
    uint64_t handoffObserved;
    uint64_t handoffFinalState;
};

void ResetCounts()
{
    initCalls.store(0, std::memory_order_relaxed);
    destroyCalls.store(0, std::memory_order_relaxed);
    lockCalls.store(0, std::memory_order_relaxed);
    unlockCalls.store(0, std::memory_order_relaxed);
    tryCalls.store(0, std::memory_order_relaxed);
}

#ifdef SPINLOCK_ORACLE
void PrintBytes(const char* label, const void* object, size_t size)
{
    std::printf("%s=", label);
    const auto* bytes = static_cast<const unsigned char*>(object);
    for (size_t i = 0; i < size; ++i) {
        std::printf("%02x", static_cast<unsigned>(bytes[i]));
    }
}
void SnapshotBytes(unsigned char* destination, const void* storage, size_t size)
{
    const auto* bytes = static_cast<const volatile unsigned char*>(storage);
    for (size_t i = 0; i < size; ++i) {
        destination[i] = bytes[i];
    }
}
#endif

#ifdef SPINLOCK_ORACLE
using MapleRuntime::ScopedEnterSpinLock;
using MapleRuntime::SpinLock;

void ApiInit(void* storage) { new (storage) SpinLock(); }
void ApiDestroy(void* lock) { static_cast<SpinLock*>(lock)->~SpinLock(); }
void ApiLock(void* lock) { static_cast<SpinLock*>(lock)->Lock(); }
void ApiUnlock(void* lock) { static_cast<SpinLock*>(lock)->Unlock(); }
bool ApiTryLock(void* lock) { return static_cast<SpinLock*>(lock)->TryLock(); }
bool AttachThread() { return true; }
bool DetachThread() { return true; }
#else
extern "C" void CJRT_SpinLockLock(void*);
extern "C" void CJRT_SpinLockUnlock(void*);
extern "C" bool MRT_NewForeignCJThread();
extern "C" bool MRT_EndForeignCJThread();

void ApiLock(void* lock) { CJRT_SpinLockLock(lock); }
void ApiUnlock(void* lock) { CJRT_SpinLockUnlock(lock); }
bool AttachThread() { return MRT_NewForeignCJThread(); }
bool DetachThread() { return MRT_EndForeignCJThread(); }
#endif

struct BlockingArgs {
    void* lock;
    std::atomic<bool>* ready;
    std::atomic<bool>* acquired;
    bool attached;
};

void* BlockingThread(void* raw)
{
    auto* args = static_cast<BlockingArgs*>(raw);
    args->attached = AttachThread();
    if (!args->attached) {
        return nullptr;
    }
    args->ready->store(true, std::memory_order_release);
    ApiLock(args->lock);
    args->acquired->store(true, std::memory_order_release);
    ApiUnlock(args->lock);
    args->attached = DetachThread();
    return nullptr;
}

struct CounterArgs {
    void* lock;
    uint64_t* counter;
    bool attached;
};

void* CounterThread(void* raw)
{
    auto* args = static_cast<CounterArgs*>(raw);
    args->attached = AttachThread();
    if (!args->attached) {
        return nullptr;
    }
    for (size_t iteration = 0; iteration < ITERATIONS; ++iteration) {
        ApiLock(args->lock);
        ++*args->counter;
        ApiUnlock(args->lock);
    }
    args->attached = DetachThread();
    return nullptr;
}

struct HandoffArgs {
    void* lock;
    std::atomic<bool>* ready;
    uint64_t* payload;
    uint64_t observed;
    bool attached;
};

void* HandoffThread(void* raw)
{
    auto* args = static_cast<HandoffArgs*>(raw);
    args->attached = AttachThread();
    if (!args->attached) {
        return nullptr;
    }
    args->ready->store(true, std::memory_order_release);
    ApiLock(args->lock);
    args->observed = *args->payload;
    ApiUnlock(args->lock);
    args->attached = DetachThread();
    return nullptr;
}

__attribute__((unused)) bool RunBehavior(void* lock, SpinLockResult* result)
{
    std::memset(result, 0, sizeof(*result));

    ApiLock(lock);
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
    ApiUnlock(lock);
    if (pthread_join(blockingThread, nullptr) != 0 || !blocking.attached) {
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
        if (pthread_join(counterThreads[index], nullptr) != 0 || !counterArgs[index].attached) {
            return false;
        }
    }
    result->counter = counter;
    result->counterFinalState = *static_cast<uint32_t*>(lock);

    uint64_t payload = 0;
    std::atomic<bool> handoffReady{false};
    HandoffArgs handoff{lock, &handoffReady, &payload, 0, false};
    ApiLock(lock);
    pthread_t handoffThread{};
    if (pthread_create(&handoffThread, nullptr, HandoffThread, &handoff) != 0) {
        return false;
    }
    while (!handoffReady.load(std::memory_order_acquire)) {
        sched_yield();
    }
    result->handoffReady = 1;
    payload = HANDOFF_PAYLOAD;
    ApiUnlock(lock);
    if (pthread_join(handoffThread, nullptr) != 0 || !handoff.attached) {
        return false;
    }
    result->handoffObserved = handoff.observed;
    result->handoffFinalState = *static_cast<uint32_t*>(lock);
    return true;
}

#ifdef SPINLOCK_ORACLE
void PrintBehavior(const SpinLockResult& result)
{
    std::printf("SPINLOCK_BLOCK pre_release=%llu acquired_before_release=%llu "
        "post_release=%llu acquired_after_release=%llu status=PASS\n",
        static_cast<unsigned long long>(result.blockReady),
        static_cast<unsigned long long>(result.acquiredBeforeRelease),
        static_cast<unsigned long long>(result.acquiredAfterRelease),
        static_cast<unsigned long long>(result.acquiredAfterRelease));
    std::printf("SPINLOCK_COUNTER threads=%zu iterations=%zu expected=%zu actual=%llu "
        "final=%llu status=PASS\n", THREAD_COUNT, ITERATIONS, THREAD_COUNT * ITERATIONS,
        static_cast<unsigned long long>(result.counter),
        static_cast<unsigned long long>(result.counterFinalState));
    std::printf("SPINLOCK_HANDOFF payload=%llu observed=%llu final=%llu status=PASS\n",
        static_cast<unsigned long long>(HANDOFF_PAYLOAD),
        static_cast<unsigned long long>(result.handoffObserved),
        static_cast<unsigned long long>(result.handoffFinalState));
}
#endif

#ifdef SPINLOCK_ORACLE
void GuardEarlyReturn(SpinLock& lock)
{
    ScopedEnterSpinLock guard(lock);
    return;
}

void GuardUnwind(SpinLock& lock)
{
    ScopedEnterSpinLock guard(lock);
    throw 7;
}
#endif
} // namespace

extern "C" int __real_pthread_spin_init(pthread_spinlock_t*, int);
extern "C" int __real_pthread_spin_destroy(pthread_spinlock_t*);
extern "C" int __real_pthread_spin_lock(pthread_spinlock_t*);
extern "C" int __real_pthread_spin_unlock(pthread_spinlock_t*);
extern "C" int __real_pthread_spin_trylock(pthread_spinlock_t*);

extern "C" int __wrap_pthread_spin_init(pthread_spinlock_t* lock, int shared)
{
    initCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_init(lock, shared);
}

extern "C" int __wrap_pthread_spin_destroy(pthread_spinlock_t* lock)
{
    destroyCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_destroy(lock);
}

extern "C" int __wrap_pthread_spin_lock(pthread_spinlock_t* lock)
{
    lockCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_lock(lock);
}

extern "C" int __wrap_pthread_spin_unlock(pthread_spinlock_t* lock)
{
    unlockCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_unlock(lock);
}

extern "C" int __wrap_pthread_spin_trylock(pthread_spinlock_t* lock)
{
    tryCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_pthread_spin_trylock(lock);
}

extern "C" void SpinLockResetPthreadCounts() { ResetCounts(); }
extern "C" uint64_t SpinLockInitCalls() { return initCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t SpinLockDestroyCalls() { return destroyCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t SpinLockLockCalls() { return lockCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t SpinLockUnlockCalls() { return unlockCalls.load(std::memory_order_relaxed); }
extern "C" uint64_t SpinLockTryCalls() { return tryCalls.load(std::memory_order_relaxed); }

#ifdef SPINLOCK_ORACLE
int main(int argc, char** argv)
{
    using MapleRuntime::ScopedEnterSpinLock;
    using MapleRuntime::SpinLock;
    const bool partial = argc == 2 && std::strcmp(argv[1], "--partial") == 0;
    alignas(SpinLock) unsigned char storage[sizeof(SpinLock)]{};
    unsigned char states[7][sizeof(SpinLock)]{};
    ResetCounts();
    ApiInit(storage);
    auto* lock = reinterpret_cast<SpinLock*>(storage);
    SnapshotBytes(states[0], storage, sizeof(storage));
    ApiLock(lock);
    SnapshotBytes(states[1], storage, sizeof(storage));
    const bool failed = ApiTryLock(lock);
    SnapshotBytes(states[2], storage, sizeof(storage));
    ApiUnlock(lock);
    SnapshotBytes(states[3], storage, sizeof(storage));
    const bool succeeded = ApiTryLock(lock);
    SnapshotBytes(states[4], storage, sizeof(storage));
    ApiUnlock(lock);
    SnapshotBytes(states[5], storage, sizeof(storage));
    if (!partial) {
        ApiDestroy(lock);
        SnapshotBytes(states[6], storage, sizeof(storage));
    }

    std::printf("SPINLOCK_PTHREAD sizeof=%zu align=%zu is_int=%s remove_cv_is_int=%s volatile=%s\n",
        sizeof(pthread_spinlock_t), alignof(pthread_spinlock_t),
        std::is_same<pthread_spinlock_t, int>::value ? "true" : "false",
        std::is_same<typename std::remove_cv<pthread_spinlock_t>::type, int>::value ? "true" : "false",
        std::is_volatile<pthread_spinlock_t>::value ? "true" : "false");
    std::printf("SPINLOCK_LAYOUT sizeof=%zu align=%zu spinlock=%zu\n", sizeof(SpinLock),
        alignof(SpinLock), offsetof(SpinLock, spinlock));
    if (!partial) {
        std::printf("SCOPED_SPINLOCK_LAYOUT sizeof=%zu align=%zu spinLock=%zu\n",
            sizeof(ScopedEnterSpinLock), alignof(ScopedEnterSpinLock),
            __builtin_offsetof(ScopedEnterSpinLock, spinLock));
    }
    std::printf("SPINLOCK_BYTES ");
    const char* labels[] = {"init", "held_lock", "failed_try", "unlock", "successful_try",
        "final_unlock", "destroy"};
    const size_t stateCount = partial ? 6 : 7;
    for (size_t i = 0; i < stateCount; ++i) {
        if (i != 0) {
            std::printf(" ");
        }
        PrintBytes(labels[i], states[i], sizeof(SpinLock));
    }
    std::printf("\nSPINLOCK_TRY clear=%s held=%s status=PASS\n",
        succeeded ? "true" : "false", failed ? "true" : "false");
    std::printf("SPINLOCK_CALLS init=%llu destroy=%llu lock=%llu unlock=%llu try=%llu\n",
        static_cast<unsigned long long>(SpinLockInitCalls()),
        static_cast<unsigned long long>(SpinLockDestroyCalls()),
        static_cast<unsigned long long>(SpinLockLockCalls()),
        static_cast<unsigned long long>(SpinLockUnlockCalls()),
        static_cast<unsigned long long>(SpinLockTryCalls()));

    if (partial) {
        SpinLockResult result{};
        const bool behavior = RunBehavior(lock, &result);
        PrintBehavior(result);
        ApiDestroy(lock);
        return behavior && !failed && succeeded && result.blockReady == 1 &&
            result.acquiredBeforeRelease == 0 && result.acquiredAfterRelease == 1 &&
            result.counter == THREAD_COUNT * ITERATIONS && result.counterFinalState == 1 &&
            result.handoffReady == 1 && result.handoffObserved == HANDOFF_PAYLOAD &&
            result.handoffFinalState == 1 ? 0 : 1;
    }

    SpinLock guardLock;
    const auto beforeGuardLock = lockCalls.load(std::memory_order_relaxed);
    const auto beforeGuardUnlock = unlockCalls.load(std::memory_order_relaxed);
    {
        ScopedEnterSpinLock guard(guardLock);
        if (guardLock.TryLock()) {
            return 2;
        }
    }
    const bool lexicalReleased = guardLock.TryLock();
    guardLock.Unlock();
    GuardEarlyReturn(guardLock);
    const bool earlyReleased = guardLock.TryLock();
    guardLock.Unlock();
    try {
        GuardUnwind(guardLock);
    } catch (int) {
    }
    const bool unwindReleased = guardLock.TryLock();
    guardLock.Unlock();
    std::printf("SCOPED_SPINLOCK_RAII lexical=%s early_return=%s unwind=%s lock_delta=%llu "
        "unlock_delta=%llu status=PASS\n", lexicalReleased ? "true" : "false",
        earlyReleased ? "true" : "false", unwindReleased ? "true" : "false",
        static_cast<unsigned long long>(lockCalls.load(std::memory_order_relaxed) - beforeGuardLock),
        static_cast<unsigned long long>(unlockCalls.load(std::memory_order_relaxed) - beforeGuardUnlock));
    return (!failed && succeeded && lexicalReleased && earlyReleased && unwindReleased) ? 0 : 1;
}
#else
extern "C" int32_t SpinLockRun(void* lock, SpinLockResult* result)
{
    return RunBehavior(lock, result) ? 0 : 1;
}
#endif
