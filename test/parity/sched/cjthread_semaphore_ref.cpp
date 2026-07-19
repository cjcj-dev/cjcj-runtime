// CJThread schedule/include/inner/base.h:10-53,79-113 Semaphore layout/state
// oracle and native pthread/signal driver for the caller-owned inline value.
#include <atomic>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>
#include <signal.h>
#include <unistd.h>

#include "macro_def.h"
#include "base.h"

#ifdef MRT_MACOS
#error "the executable oracle must select the non-Mac Semaphore branch"
#endif

namespace {
constexpr size_t THREAD_COUNT = 8;
constexpr size_t ITERATIONS = 4096;
constexpr uint64_t HANDOFF_PAYLOAD = UINT64_C(0x5a17c0de);

std::atomic<uint64_t> initCalls{0};
std::atomic<uint64_t> waitCalls{0};
std::atomic<uint64_t> waitReturns{0};
std::atomic<uint64_t> waitEintr{0};
std::atomic<uint64_t> postCalls{0};
std::atomic<uint64_t> destroyCalls{0};
std::atomic<uint64_t> addressMismatches{0};
std::atomic<uintptr_t> expectedAddress{0};
std::atomic<int32_t> observedPshared{-1};
std::atomic<uint32_t> observedValue{UINT32_MAX};
volatile sig_atomic_t signalHandlerCalls = 0;

struct SemaphoreResult {
    unsigned char states[4][sizeof(Semaphore)];
    int32_t initResult;
    int32_t initErrno;
    int32_t waitResult;
    int32_t waitErrno;
    int32_t waitEintrResult;
    int32_t waitEintrErrno;
    int32_t waitNoIntrResult;
    int32_t waitNoIntrErrno;
    int32_t postResult;
    int32_t postErrno;
    int32_t destroyResult;
    int32_t destroyErrno;
    uint64_t blockedBeforePost;
    uint64_t completedAfterPost;
    uint64_t noIntrBlockedBeforePost;
    uint64_t noIntrCompletedAfterPost;
    uint64_t counter;
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
    waitCalls.store(0, std::memory_order_relaxed);
    waitReturns.store(0, std::memory_order_relaxed);
    waitEintr.store(0, std::memory_order_relaxed);
    postCalls.store(0, std::memory_order_relaxed);
    destroyCalls.store(0, std::memory_order_relaxed);
    addressMismatches.store(0, std::memory_order_relaxed);
    observedPshared.store(-1, std::memory_order_relaxed);
    observedValue.store(UINT32_MAX, std::memory_order_relaxed);
    signalHandlerCalls = 0;
}

void Snapshot(unsigned char* destination, const void* storage)
{
    const auto* bytes = static_cast<const volatile unsigned char*>(storage);
    for (size_t i = 0; i < sizeof(Semaphore); ++i) {
        destination[i] = bytes[i];
    }
}

void PrintBytes(const char* label, const unsigned char* bytes)
{
    std::printf("%s=", label);
    for (size_t i = 0; i < sizeof(Semaphore); ++i) {
        std::printf("%02x", static_cast<unsigned>(bytes[i]));
    }
}

bool WaitForAtLeast(const std::atomic<uint64_t>& value, uint64_t expected)
{
    for (size_t spin = 0; spin < 2000000; ++spin) {
        if (value.load(std::memory_order_acquire) >= expected) {
            usleep(20000);
            return true;
        }
        sched_yield();
    }
    return false;
}

void SignalHandler(int) { ++signalHandlerCalls; }

#ifdef CJTHREAD_SEMAPHORE_ORACLE
int ApiWait(void* sem) { return SemaphoreWait(static_cast<Semaphore*>(sem)); }
int ApiWaitNoIntr(void* sem) { return SemaphoreWaitNoIntr(static_cast<Semaphore*>(sem)); }
int ApiPost(void* sem) { return SemaphorePost(static_cast<Semaphore*>(sem)); }
int ApiDestroy(void* sem) { return SemaphoreDestroy(static_cast<Semaphore*>(sem)); }
bool AttachThread() { return true; }
bool DetachThread() { return true; }
#else
extern "C" int32_t CJRT_CJthreadSemaphoreWait(void*);
extern "C" int32_t CJRT_CJthreadSemaphoreWaitNoIntr(void*);
extern "C" int32_t CJRT_CJthreadSemaphorePost(void*);
extern "C" int32_t CJRT_CJthreadSemaphoreDestroy(void*);
extern "C" bool MRT_NewForeignCJThread();
extern "C" bool MRT_EndForeignCJThread();

int ApiWait(void* sem) { return CJRT_CJthreadSemaphoreWait(sem); }
int ApiWaitNoIntr(void* sem) { return CJRT_CJthreadSemaphoreWaitNoIntr(sem); }
int ApiPost(void* sem) { return CJRT_CJthreadSemaphorePost(sem); }
int ApiDestroy(void* sem) { return CJRT_CJthreadSemaphoreDestroy(sem); }
bool AttachThread() { return MRT_NewForeignCJThread(); }
bool DetachThread() { return MRT_EndForeignCJThread(); }
#endif

struct WaitArgs {
    void* sem;
    bool noIntr;
    std::atomic<bool> ready;
    std::atomic<bool> done;
    int32_t result;
    int32_t observedErrno;
    bool ok;
};

void* WaitThread(void* raw)
{
    auto* args = static_cast<WaitArgs*>(raw);
    args->ok = AttachThread();
    if (!args->ok) {
        args->done.store(true, std::memory_order_release);
        return nullptr;
    }
    args->ready.store(true, std::memory_order_release);
    errno = 0;
    args->result = args->noIntr ? ApiWaitNoIntr(args->sem) : ApiWait(args->sem);
    args->observedErrno = errno;
    args->done.store(true, std::memory_order_release);
    args->ok = DetachThread() && args->ok;
    return nullptr;
}

struct CounterArgs {
    void* sem;
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
        if (ApiWait(args->sem) != 0) {
            args->ok = false;
            break;
        }
        ++*args->counter;
        if (ApiPost(args->sem) != 0) {
            args->ok = false;
            break;
        }
    }
    args->ok = DetachThread() && args->ok;
    return nullptr;
}

struct HandoffArgs {
    void* sem;
    uint64_t* payload;
    std::atomic<bool> ready;
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
    args->ready.store(true, std::memory_order_release);
    args->ok = ApiWait(args->sem) == 0;
    if (args->ok) {
        args->observed = *args->payload;
    }
    args->ok = DetachThread() && args->ok;
    return nullptr;
}

bool RunAfterInit(void* sem, int32_t initResult, int32_t initErrno, SemaphoreResult* result)
{
    std::memset(result, 0, sizeof(*result));
    result->initResult = initResult;
    result->initErrno = initErrno;
    Snapshot(result->states[0], sem);

    struct sigaction action {};
    struct sigaction previousAction {};
    action.sa_handler = SignalHandler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (sigaction(SIGUSR2, &action, &previousAction) != 0) {
        return false;
    }

    WaitArgs blocked {};
    blocked.sem = sem;
    blocked.noIntr = false;
    const uint64_t blockedTarget = waitCalls.load(std::memory_order_relaxed) + 1;
    pthread_t blockedThread {};
    if (pthread_create(&blockedThread, nullptr, WaitThread, &blocked) != 0 ||
        !WaitForAtLeast(waitCalls, blockedTarget)) {
        return false;
    }
    result->blockedBeforePost = blocked.done.load(std::memory_order_acquire) ? 0 : 1;
    Snapshot(result->states[1], sem);
    errno = 0;
    result->postResult = ApiPost(sem);
    result->postErrno = errno;
    if (pthread_join(blockedThread, nullptr) != 0 || !blocked.ok) {
        return false;
    }
    result->waitResult = blocked.result;
    result->waitErrno = blocked.observedErrno;
    result->completedAfterPost = blocked.done.load(std::memory_order_acquire) ? 1 : 0;
    Snapshot(result->states[2], sem);

    WaitArgs interrupted {};
    interrupted.sem = sem;
    interrupted.noIntr = false;
    const uint64_t interruptedTarget = waitCalls.load(std::memory_order_relaxed) + 1;
    pthread_t interruptedThread {};
    if (pthread_create(&interruptedThread, nullptr, WaitThread, &interrupted) != 0 ||
        !WaitForAtLeast(waitCalls, interruptedTarget) || pthread_kill(interruptedThread, SIGUSR2) != 0 ||
        pthread_join(interruptedThread, nullptr) != 0 || !interrupted.ok) {
        return false;
    }
    result->waitEintrResult = interrupted.result;
    result->waitEintrErrno = interrupted.observedErrno;

    WaitArgs noIntr {};
    noIntr.sem = sem;
    noIntr.noIntr = true;
    const uint64_t noIntrFirstTarget = waitCalls.load(std::memory_order_relaxed) + 1;
    const uint64_t noIntrSecondTarget = noIntrFirstTarget + 1;
    const uint64_t eintrTarget = waitEintr.load(std::memory_order_relaxed) + 1;
    pthread_t noIntrThread {};
    if (pthread_create(&noIntrThread, nullptr, WaitThread, &noIntr) != 0 ||
        !WaitForAtLeast(waitCalls, noIntrFirstTarget) || pthread_kill(noIntrThread, SIGUSR2) != 0 ||
        !WaitForAtLeast(waitEintr, eintrTarget) || !WaitForAtLeast(waitCalls, noIntrSecondTarget)) {
        return false;
    }
    result->noIntrBlockedBeforePost = noIntr.done.load(std::memory_order_acquire) ? 0 : 1;
    if (ApiPost(sem) != 0 || pthread_join(noIntrThread, nullptr) != 0 || !noIntr.ok) {
        return false;
    }
    result->waitNoIntrResult = noIntr.result;
    result->waitNoIntrErrno = noIntr.observedErrno;
    result->noIntrCompletedAfterPost = noIntr.done.load(std::memory_order_acquire) ? 1 : 0;

    if (ApiPost(sem) != 0) {
        return false;
    }
    uint64_t counter = 0;
    pthread_t counterThreads[THREAD_COUNT] {};
    CounterArgs counterArgs[THREAD_COUNT] {};
    for (size_t index = 0; index < THREAD_COUNT; ++index) {
        counterArgs[index] = CounterArgs{sem, &counter, false};
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

    if (ApiWait(sem) != 0) {
        return false;
    }
    uint64_t payload = 0;
    HandoffArgs handoff {};
    handoff.sem = sem;
    handoff.payload = &payload;
    const uint64_t handoffTarget = waitCalls.load(std::memory_order_relaxed) + 1;
    pthread_t handoffThread {};
    if (pthread_create(&handoffThread, nullptr, HandoffThread, &handoff) != 0 ||
        !WaitForAtLeast(waitCalls, handoffTarget)) {
        return false;
    }
    payload = HANDOFF_PAYLOAD;
    if (ApiPost(sem) != 0 || pthread_join(handoffThread, nullptr) != 0 || !handoff.ok) {
        return false;
    }
    result->handoffObserved = handoff.observed;

    errno = 0;
    result->destroyResult = ApiDestroy(sem);
    result->destroyErrno = errno;
    Snapshot(result->states[3], sem);
    if (sigaction(SIGUSR2, &previousAction, nullptr) != 0) {
        return false;
    }
    return true;
}

bool CheckAndPrint(const SemaphoreResult& result)
{
    const bool valid = result.initResult == 0 && result.initErrno == 0 &&
        result.waitResult == 0 && result.waitErrno == 0 &&
        result.waitEintrResult == -1 && result.waitEintrErrno == EINTR &&
        result.waitNoIntrResult == 0 && result.waitNoIntrErrno == EINTR &&
        result.postResult == 0 && result.postErrno == 0 &&
        result.destroyResult == 0 && result.destroyErrno == 0 &&
        result.blockedBeforePost == 1 && result.completedAfterPost == 1 &&
        result.noIntrBlockedBeforePost == 1 && result.noIntrCompletedAfterPost == 1 &&
        result.counter == THREAD_COUNT * ITERATIONS && result.handoffObserved == HANDOFF_PAYLOAD &&
        result.workerFailures == 0 && signalHandlerCalls == 2 &&
        initCalls.load() == 1 && waitCalls.load() == 32774 && waitReturns.load() == 32774 &&
        waitEintr.load() == 2 && postCalls.load() == 32772 && destroyCalls.load() == 1 &&
        addressMismatches.load() == 0 && observedPshared.load() == 0 && observedValue.load() == 0;
    if (!valid) {
        return false;
    }

    std::printf("CJTHREAD_SEMAPHORE_SEM_T sizeof=%zu align=%zu\n", sizeof(sem_t), alignof(sem_t));
    std::printf("CJTHREAD_SEMAPHORE_LAYOUT sizeof=%zu align=%zu sem=%zu\n",
        sizeof(Semaphore), alignof(Semaphore), offsetof(Semaphore, sem));
    std::printf("CJTHREAD_SEMAPHORE_BYTES ");
    const char* labels[] = {"init", "blocked", "consumed", "destroy"};
    for (size_t index = 0; index < 4; ++index) {
        if (index != 0) {
            std::printf(" ");
        }
        PrintBytes(labels[index], result.states[index]);
    }
    std::printf("\nCJTHREAD_SEMAPHORE_RETURNS init=%d wait=%d wait_eintr=%d wait_no_intr=%d post=%d destroy=%d\n",
        result.initResult, result.waitResult, result.waitEintrResult,
        result.waitNoIntrResult, result.postResult, result.destroyResult);
    std::printf("CJTHREAD_SEMAPHORE_ERRNO init=%d wait=%d wait_eintr=%d wait_no_intr=%d post=%d destroy=%d\n",
        result.initErrno, result.waitErrno, result.waitEintrErrno,
        result.waitNoIntrErrno, result.postErrno, result.destroyErrno);
    std::printf("CJTHREAD_SEMAPHORE_BLOCK blocked_before_post=%llu completed_after_post=%llu status=PASS\n",
        static_cast<unsigned long long>(result.blockedBeforePost),
        static_cast<unsigned long long>(result.completedAfterPost));
    std::printf("CJTHREAD_SEMAPHORE_NOINTR real_eintr=1 retries=1 blocked_before_post=%llu "
        "completed_after_post=%llu non_eintr_defined_trigger=none status=PASS\n",
        static_cast<unsigned long long>(result.noIntrBlockedBeforePost),
        static_cast<unsigned long long>(result.noIntrCompletedAfterPost));
    std::printf("CJTHREAD_SEMAPHORE_COUNTER threads=%zu iterations=%zu expected=%zu actual=%llu status=PASS\n",
        THREAD_COUNT, ITERATIONS, THREAD_COUNT * ITERATIONS,
        static_cast<unsigned long long>(result.counter));
    std::printf("CJTHREAD_SEMAPHORE_HANDOFF payload=%llu observed=%llu status=PASS\n",
        static_cast<unsigned long long>(HANDOFF_PAYLOAD),
        static_cast<unsigned long long>(result.handoffObserved));
    std::printf("CJTHREAD_SEMAPHORE_CALLS init=%llu wait=%llu wait_returns=%llu wait_eintr=%llu "
        "post=%llu destroy=%llu pshared=%d value=%u address_mismatches=%llu destroy_after_users=true\n",
        static_cast<unsigned long long>(initCalls.load()),
        static_cast<unsigned long long>(waitCalls.load()),
        static_cast<unsigned long long>(waitReturns.load()),
        static_cast<unsigned long long>(waitEintr.load()),
        static_cast<unsigned long long>(postCalls.load()),
        static_cast<unsigned long long>(destroyCalls.load()), observedPshared.load(), observedValue.load(),
        static_cast<unsigned long long>(addressMismatches.load()));
    return true;
}
} // namespace

extern "C" int __real_sem_init(sem_t*, int, unsigned);
extern "C" int __real_sem_wait(sem_t*);
extern "C" int __real_sem_post(sem_t*);
extern "C" int __real_sem_destroy(sem_t*);

extern "C" int __wrap_sem_init(sem_t* sem, int pshared, unsigned value)
{
    RecordAddress(sem);
    initCalls.fetch_add(1, std::memory_order_relaxed);
    observedPshared.store(pshared, std::memory_order_relaxed);
    observedValue.store(value, std::memory_order_relaxed);
    return __real_sem_init(sem, pshared, value);
}

extern "C" int __wrap_sem_wait(sem_t* sem)
{
    RecordAddress(sem);
    waitCalls.fetch_add(1, std::memory_order_release);
    const int result = __real_sem_wait(sem);
    const int observedErrno = errno;
    waitReturns.fetch_add(1, std::memory_order_release);
    if (result != 0 && observedErrno == EINTR) {
        waitEintr.fetch_add(1, std::memory_order_release);
    }
    errno = observedErrno;
    return result;
}

extern "C" int __wrap_sem_post(sem_t* sem)
{
    RecordAddress(sem);
    postCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_sem_post(sem);
}

extern "C" int __wrap_sem_destroy(sem_t* sem)
{
    RecordAddress(sem);
    destroyCalls.fetch_add(1, std::memory_order_relaxed);
    return __real_sem_destroy(sem);
}

extern "C" void CJthreadSemaphoreResetCalls(void* address) { ResetCalls(address); }
extern "C" void CJthreadSemaphoreSetErrno(int32_t value) { errno = value; }
extern "C" int32_t CJthreadSemaphoreGetErrno() { return errno; }

#ifdef CJTHREAD_SEMAPHORE_ORACLE
int main()
{
    Semaphore sem {};
    SemaphoreResult result {};
    ResetCalls(&sem.sem);
    errno = 0;
    const int initResult = SemaphoreInit(&sem, 0, 0);
    const int initErrno = errno;
    return RunAfterInit(&sem, initResult, initErrno, &result) && CheckAndPrint(result) ? 0 : 1;
}
#else
extern "C" int32_t CJthreadSemaphoreRunAfterInit(void* sem, int32_t initResult, int32_t initErrno)
{
    SemaphoreResult result {};
    return RunAfterInit(sem, initResult, initErrno, &result) && CheckAndPrint(result) ? 0 : 1;
}
#endif
