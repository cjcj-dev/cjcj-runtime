// Base/AtomicSpinLock.h:14-31 executable oracle and Cangjie pthread driver.
#include <atomic>
#include "Base/Macros.h"
#ifdef ATOMICSPINLOCK_ORACLE
#define private public
#include "Base/AtomicSpinLock.h"
#undef private
#endif

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <pthread.h>
#include <sched.h>

namespace {
constexpr size_t THREAD_COUNT = 4;
constexpr size_t ITERATIONS = 4096;
constexpr uint64_t HANDOFF_PAYLOAD = UINT64_C(0x5a17c0de);

struct AtomicSpinLockResult {
    uint64_t blockReady;
    uint64_t acquiredBeforeRelease;
    uint64_t acquiredAfterRelease;
    uint64_t counter;
    uint64_t counterFinalByte;
    uint64_t handoffReady;
    uint64_t handoffObserved;
    uint64_t handoffFinalByte;
};

#ifdef ATOMICSPINLOCK_ORACLE
using MapleRuntime::AtomicSpinLock;

void ApiLock(void* lock) { static_cast<AtomicSpinLock*>(lock)->Lock(); }
void ApiUnlock(void* lock) { static_cast<AtomicSpinLock*>(lock)->Unlock(); }
bool ApiTryLock(void* lock) { return static_cast<AtomicSpinLock*>(lock)->TryLock(); }
bool AttachThread() { return true; }
bool DetachThread() { return true; }
#else
extern "C" void CJRT_AtomicSpinLockLock(void*);
extern "C" void CJRT_AtomicSpinLockUnlock(void*);
extern "C" bool CJRT_AtomicSpinLockTryLock(void*);
extern "C" bool MRT_NewForeignCJThread();
extern "C" bool MRT_EndForeignCJThread();

void ApiLock(void* lock) { CJRT_AtomicSpinLockLock(lock); }
void ApiUnlock(void* lock) { CJRT_AtomicSpinLockUnlock(lock); }
bool ApiTryLock(void* lock) { return CJRT_AtomicSpinLockTryLock(lock); }
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

bool RunBehavior(void* lock, AtomicSpinLockResult* result)
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
    result->counterFinalByte = *static_cast<uint8_t*>(lock);

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
    result->handoffFinalByte = *static_cast<uint8_t*>(lock);
    return true;
}

void PrintBehavior(const AtomicSpinLockResult& result)
{
    std::printf("ATOMICSPINLOCK_BLOCK pre_release=%llu acquired_before_release=%llu "
        "post_release=%llu acquired_after_release=%llu status=PASS\n",
        static_cast<unsigned long long>(result.blockReady),
        static_cast<unsigned long long>(result.acquiredBeforeRelease),
        static_cast<unsigned long long>(result.acquiredAfterRelease),
        static_cast<unsigned long long>(result.acquiredAfterRelease));
    std::printf("ATOMICSPINLOCK_COUNTER threads=%zu iterations=%zu expected=%zu actual=%llu "
        "final=%llu status=PASS\n", THREAD_COUNT, ITERATIONS, THREAD_COUNT * ITERATIONS,
        static_cast<unsigned long long>(result.counter),
        static_cast<unsigned long long>(result.counterFinalByte));
    std::printf("ATOMICSPINLOCK_HANDOFF payload=%llu observed=%llu final=%llu status=PASS\n",
        static_cast<unsigned long long>(HANDOFF_PAYLOAD),
        static_cast<unsigned long long>(result.handoffObserved),
        static_cast<unsigned long long>(result.handoffFinalByte));
}
} // namespace

#ifdef ATOMICSPINLOCK_ORACLE
int main()
{
    AtomicSpinLock lock;
    unsigned char bytes[6][sizeof(lock)]{};
    std::memcpy(bytes[0], &lock, sizeof(lock));
    const bool first = lock.TryLock();
    std::memcpy(bytes[1], &lock, sizeof(lock));
    const bool second = lock.TryLock();
    std::memcpy(bytes[2], &lock, sizeof(lock));
    lock.Unlock();
    std::memcpy(bytes[3], &lock, sizeof(lock));
    lock.Lock();
    std::memcpy(bytes[4], &lock, sizeof(lock));
    lock.Unlock();
    std::memcpy(bytes[5], &lock, sizeof(lock));

    std::printf("ATOMICSPINLOCK_LAYOUT sizeof=%zu align=%zu state=%zu\n", sizeof(lock),
        alignof(AtomicSpinLock), offsetof(AtomicSpinLock, state));
    std::printf("ATOMICSPINLOCK_BYTES construct=%u try_success=%u try_failed=%u unlock=%u "
        "lock=%u final_unlock=%u\n", bytes[0][0], bytes[1][0], bytes[2][0], bytes[3][0],
        bytes[4][0], bytes[5][0]);
    std::printf("ATOMICSPINLOCK_TRY clear=%s held=%s status=PASS\n",
        first ? "true" : "false", second ? "true" : "false");

    AtomicSpinLockResult result{};
    if (!RunBehavior(&lock, &result) || result.blockReady != 1 ||
        result.acquiredBeforeRelease != 0 || result.acquiredAfterRelease != 1 ||
        result.counter != THREAD_COUNT * ITERATIONS || result.counterFinalByte != 0 ||
        result.handoffReady != 1 || result.handoffObserved != HANDOFF_PAYLOAD ||
        result.handoffFinalByte != 0) {
        return 1;
    }
    PrintBehavior(result);
    return 0;
}
#else
extern "C" int32_t AtomicSpinLockRun(void* lock, AtomicSpinLockResult* result)
{
    return RunBehavior(lock, result) ? 0 : 1;
}
#endif
