// CJThread schedule/include/inner/thread.h:40-46,52-80,
// schedule/include/inner/cjthread.h:157-168, util/list/include/list.h:22-28,
// gas/x86/x86_64/cjthread_context.h:17-60, and schedule.h:262-292,383-393.
// This is a test-only oracle/observer for caller-owned Thread/LuaCJThread values.
#include <atomic>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <pthread.h>

#include "schedule.h"
#include "thread.h"
#include "cjthread.h"

size_t g_pageSize = 0;
void LogWrite(ThreadLogLevel, unsigned int, const char*, unsigned short, const char*, ...) {}

namespace {
constexpr size_t SNAPSHOTS = 5;

Thread* observedThread = nullptr;
LuaCJThread* observedLua = nullptr;
Semaphore* expectedThreadSem = nullptr;
Semaphore* expectedLuaSem = nullptr;
unsigned char threadBaseline[sizeof(Thread)] {};
unsigned char luaBaseline[sizeof(LuaCJThread)] {};
unsigned char threadSnapshots[SNAPSHOTS][sizeof(Thread)] {};
unsigned char luaSnapshots[SNAPSHOTS][sizeof(LuaCJThread)] {};
uint64_t nativeCalls[5] {};
uint64_t libcCalls[5] {};
uint64_t nativeAddressMismatches = 0;
uint64_t libcAddressMismatches = 0;
size_t snapshotCount = 0;

enum Operation : size_t { INIT = 0, WAIT = 1, WAIT_NO_INTR = 2, POST = 3, DESTROY = 4 };

bool IsExpected(const void* address)
{
    return address == expectedThreadSem || address == expectedLuaSem;
}

void Observe(uint64_t* counts, uint64_t& mismatches, Operation operation, const void* address)
{
    ++counts[operation];
    if (!IsExpected(address)) {
        ++mismatches;
    }
}

bool OutsideSemaphoreUnchanged(const unsigned char* current, const unsigned char* baseline,
                               size_t ownerSize, size_t semaphoreOffset)
{
    for (size_t i = 0; i < ownerSize; ++i) {
        if ((i < semaphoreOffset || i >= semaphoreOffset + sizeof(Semaphore)) &&
            current[i] != baseline[i]) {
            return false;
        }
    }
    return true;
}

void PrintBytes(const char* owner, size_t stage, const unsigned char* bytes, size_t size)
{
    std::printf("THREAD_SEMAPHORE_OWNER_BYTES owner=%s stage=%zu bytes=", owner, stage);
    for (size_t i = 0; i < size; ++i) {
        std::printf("%02x", static_cast<unsigned>(bytes[i]));
    }
    std::puts("");
}

template <class T>
void PrintObjectBytes(const T& value)
{
    const auto* bytes = reinterpret_cast<const unsigned char*>(&value);
    for (size_t i = 0; i < sizeof(T); ++i) {
        std::printf("%02x", static_cast<unsigned>(bytes[i]));
    }
}

void PrintRepresentations()
{
    std::printf("THREAD_SEMAPHORE_ENUM init=%d close=%d running=%d pre_sleep=%d sleep=%d\n",
        THREAD_INIT, THREAD_CLOSE, THREAD_RUNNING, THREAD_PRE_SLEEP, THREAD_SLEEP);
    std::printf("THREAD_SEMAPHORE_ATOMIC size=%zu align=%zu values=", sizeof(std::atomic<ThreadState>),
        alignof(std::atomic<ThreadState>));
    for (int value = THREAD_INIT; value <= THREAD_SLEEP; ++value) {
        std::atomic<ThreadState> state {static_cast<ThreadState>(value)};
        if (value != THREAD_INIT) {
            std::printf(",");
        }
        PrintObjectBytes(state);
    }
    std::puts("");

    pid_t pidZero = 0;
    pid_t pidNonzero = static_cast<pid_t>(0x01020304);
    pthread_t pthreadZero {};
    pthread_t pthreadNonzero = static_cast<pthread_t>(UINT64_C(0x0102030405060708));
    bool boolZero = false;
    bool boolNonzero = true;
    uintptr_t pointerBits = UINT64_C(0x0102030405060708);
    void* dataZero = nullptr;
    void* dataNonzero = nullptr;
    LuaCJThreadFunc functionZero = nullptr;
    LuaCJThreadFunc functionNonzero = nullptr;
    static_assert(sizeof(pointerBits) == sizeof(dataNonzero), "data pointer width changed");
    static_assert(sizeof(pointerBits) == sizeof(functionNonzero), "function pointer width changed");
    std::memcpy(&dataNonzero, &pointerBits, sizeof(dataNonzero));
    std::memcpy(&functionNonzero, &pointerBits, sizeof(functionNonzero));

    std::printf("THREAD_SEMAPHORE_REP pid=%zu/%zu/", sizeof(pid_t), alignof(pid_t));
    PrintObjectBytes(pidZero);
    std::printf("/");
    PrintObjectBytes(pidNonzero);
    std::printf(" pthread=%zu/%zu/", sizeof(pthread_t), alignof(pthread_t));
    PrintObjectBytes(pthreadZero);
    std::printf("/");
    PrintObjectBytes(pthreadNonzero);
    std::printf(" bool=%zu/%zu/", sizeof(bool), alignof(bool));
    PrintObjectBytes(boolZero);
    std::printf("/");
    PrintObjectBytes(boolNonzero);
    std::printf(" data_pointer=%zu/%zu/", sizeof(void*), alignof(void*));
    PrintObjectBytes(dataZero);
    std::printf("/");
    PrintObjectBytes(dataNonzero);
    std::printf(" function_pointer=%zu/%zu/", sizeof(LuaCJThreadFunc), alignof(LuaCJThreadFunc));
    PrintObjectBytes(functionZero);
    std::printf("/");
    PrintObjectBytes(functionNonzero);
    std::puts("");
}

bool CheckFields()
{
    const Thread& thread = *observedThread;
    const LuaCJThread& lua = *observedLua;
    ThreadState state;
    std::memcpy(&state, &thread.state, sizeof(state));
    return thread.link2schd.prev == nullptr && thread.link2schd.next == nullptr &&
        thread.cjthread == nullptr && thread.cjthread0 == nullptr &&
        thread.preemptFlag == nullptr && thread.preemptRequest == nullptr && state == THREAD_SLEEP &&
        thread.processor == nullptr && thread.oldProcessor == nullptr && thread.tid == 0x1020304 &&
        static_cast<uint64_t>(thread.osThread) == UINT64_C(0x0102030405060708) &&
        thread.context.rsp == 1 && thread.context.rbp == 2 && thread.context.rbx == 3 &&
        thread.context.rip == 4 && thread.context.r12 == 5 && thread.context.r13 == 6 &&
        thread.context.r14 == 7 && thread.context.r15 == 8 && thread.context.mxcsr == 9 &&
        thread.context.fpuCw == 10 && thread.isSearching && thread.boundCJThread == nullptr &&
        thread.nextProcessor == nullptr && thread.allThreadDulink.prev == nullptr &&
        thread.allThreadDulink.next == nullptr && lua.cjthread == nullptr && lua.func == nullptr &&
        lua.arg == nullptr && lua.result == nullptr && lua.state == 0x11223344;
}

void PrintLayouts()
{
    std::printf("THREAD_LAYOUT sizeof=%zu align=%zu link2schd=%zu cjthread=%zu cjthread0=%zu "
        "preemptFlag=%zu preemptRequest=%zu state=%zu processor=%zu oldProcessor=%zu sem=%zu "
        "tid=%zu osThread=%zu context=%zu isSearching=%zu boundCJThread=%zu nextProcessor=%zu "
        "allThreadDulink=%zu\n", sizeof(Thread), alignof(Thread), offsetof(Thread, link2schd),
        offsetof(Thread, cjthread), offsetof(Thread, cjthread0), offsetof(Thread, preemptFlag),
        offsetof(Thread, preemptRequest), offsetof(Thread, state), offsetof(Thread, processor),
        offsetof(Thread, oldProcessor), offsetof(Thread, sem), offsetof(Thread, tid),
        offsetof(Thread, osThread), offsetof(Thread, context), offsetof(Thread, isSearching),
        offsetof(Thread, boundCJThread), offsetof(Thread, nextProcessor),
        offsetof(Thread, allThreadDulink));
    std::printf("LUA_CJTHREAD_LAYOUT sizeof=%zu align=%zu cjthread=%zu func=%zu arg=%zu result=%zu "
        "sem=%zu state=%zu attrUser=%zu\n", sizeof(LuaCJThread), alignof(LuaCJThread),
        offsetof(LuaCJThread, cjthread), offsetof(LuaCJThread, func), offsetof(LuaCJThread, arg),
        offsetof(LuaCJThread, result), offsetof(LuaCJThread, sem), offsetof(LuaCJThread, state),
        offsetof(LuaCJThread, attrUser));
    std::printf("DULINK_LAYOUT sizeof=%zu align=%zu prev=%zu next=%zu\n", sizeof(Dulink),
        alignof(Dulink), offsetof(Dulink, prev), offsetof(Dulink, next));
    std::printf("CJTHREAD_CONTEXT_LAYOUT sizeof=%zu align=%zu rsp=%zu rbp=%zu rbx=%zu rip=%zu "
        "r12=%zu r13=%zu r14=%zu r15=%zu mxcsr=%zu fpuCw=%zu\n", sizeof(CJThreadContext),
        alignof(CJThreadContext), offsetof(CJThreadContext, rsp), offsetof(CJThreadContext, rbp),
        offsetof(CJThreadContext, rbx), offsetof(CJThreadContext, rip), offsetof(CJThreadContext, r12),
        offsetof(CJThreadContext, r13), offsetof(CJThreadContext, r14), offsetof(CJThreadContext, r15),
        offsetof(CJThreadContext, mxcsr), offsetof(CJThreadContext, fpuCw));
    std::printf("CJTHREAD_ATTR_LAYOUT sizeof=%zu align=%zu attr=%zu\n", sizeof(CJThreadAttr),
        alignof(CJThreadAttr), offsetof(CJThreadAttr, attr));
}

void SetOracleFields(Thread& thread, LuaCJThread& lua)
{
    std::memset(&thread, 0, sizeof(thread));
    std::memset(&lua, 0, sizeof(lua));
    ThreadState state = THREAD_SLEEP;
    std::memcpy(&thread.state, &state, sizeof(state));
    thread.tid = 0x1020304;
    thread.osThread = static_cast<pthread_t>(UINT64_C(0x0102030405060708));
    thread.context.rsp = 1;
    thread.context.rbp = 2;
    thread.context.rbx = 3;
    thread.context.rip = 4;
    thread.context.r12 = 5;
    thread.context.r13 = 6;
    thread.context.r14 = 7;
    thread.context.r15 = 8;
    thread.context.mxcsr = 9;
    thread.context.fpuCw = 10;
    thread.isSearching = true;
    lua.state = 0x11223344;
}

int ApiInit(Semaphore* sem, int pshared, unsigned value)
{
#ifdef THREAD_SEMAPHORE_LAYOUT_ORACLE
    Observe(nativeCalls, nativeAddressMismatches, INIT, sem);
    return SemaphoreInit(sem, pshared, value);
#else
    extern int32_t CJRT_ThreadSemaphoreInit(Semaphore*, int32_t, uint32_t);
    return CJRT_ThreadSemaphoreInit(sem, pshared, value);
#endif
}

int ApiWait(Semaphore* sem)
{
#ifdef THREAD_SEMAPHORE_LAYOUT_ORACLE
    Observe(nativeCalls, nativeAddressMismatches, WAIT, sem);
    return SemaphoreWait(sem);
#else
    extern int32_t CJRT_ThreadSemaphoreWait(Semaphore*);
    return CJRT_ThreadSemaphoreWait(sem);
#endif
}

int ApiWaitNoIntr(Semaphore* sem)
{
#ifdef THREAD_SEMAPHORE_LAYOUT_ORACLE
    Observe(nativeCalls, nativeAddressMismatches, WAIT_NO_INTR, sem);
    return SemaphoreWaitNoIntr(sem);
#else
    extern int32_t CJRT_ThreadSemaphoreWaitNoIntr(Semaphore*);
    return CJRT_ThreadSemaphoreWaitNoIntr(sem);
#endif
}

int ApiPost(Semaphore* sem)
{
#ifdef THREAD_SEMAPHORE_LAYOUT_ORACLE
    Observe(nativeCalls, nativeAddressMismatches, POST, sem);
    return SemaphorePost(sem);
#else
    extern int32_t CJRT_ThreadSemaphorePost(Semaphore*);
    return CJRT_ThreadSemaphorePost(sem);
#endif
}

int ApiDestroy(Semaphore* sem)
{
#ifdef THREAD_SEMAPHORE_LAYOUT_ORACLE
    Observe(nativeCalls, nativeAddressMismatches, DESTROY, sem);
    return SemaphoreDestroy(sem);
#else
    extern int32_t CJRT_ThreadSemaphoreDestroy(Semaphore*);
    return CJRT_ThreadSemaphoreDestroy(sem);
#endif
}
} // namespace

extern "C" int __real_sem_init(sem_t*, int, unsigned);
extern "C" int __real_sem_wait(sem_t*);
extern "C" int __real_sem_post(sem_t*);
extern "C" int __real_sem_destroy(sem_t*);

extern "C" int __wrap_sem_init(sem_t* sem, int pshared, unsigned value)
{
    Observe(libcCalls, libcAddressMismatches, INIT, sem);
    return __real_sem_init(sem, pshared, value);
}
extern "C" int __wrap_sem_wait(sem_t* sem)
{
    const Operation operation = libcCalls[WAIT_NO_INTR] < nativeCalls[WAIT_NO_INTR] ? WAIT_NO_INTR : WAIT;
    Observe(libcCalls, libcAddressMismatches, operation, sem);
    return __real_sem_wait(sem);
}
extern "C" int __wrap_sem_post(sem_t* sem)
{
    Observe(libcCalls, libcAddressMismatches, POST, sem);
    return __real_sem_post(sem);
}
extern "C" int __wrap_sem_destroy(sem_t* sem)
{
    Observe(libcCalls, libcAddressMismatches, DESTROY, sem);
    return __real_sem_destroy(sem);
}

#ifndef THREAD_SEMAPHORE_LAYOUT_ORACLE
extern "C" int __real_cj_cjthread_semaphore_init(uint64_t*, int32_t, uint32_t);
extern "C" int __real_cj_cjthread_semaphore_wait(uint64_t*);
extern "C" int __real_cj_cjthread_semaphore_wait_no_intr(uint64_t*);
extern "C" int __real_cj_cjthread_semaphore_post(uint64_t*);
extern "C" int __real_cj_cjthread_semaphore_destroy(uint64_t*);

extern "C" int __wrap_cj_cjthread_semaphore_init(uint64_t* sem, int32_t pshared, uint32_t value)
{
    Observe(nativeCalls, nativeAddressMismatches, INIT, sem);
    return __real_cj_cjthread_semaphore_init(sem, pshared, value);
}
extern "C" int __wrap_cj_cjthread_semaphore_wait(uint64_t* sem)
{
    Observe(nativeCalls, nativeAddressMismatches, WAIT, sem);
    return __real_cj_cjthread_semaphore_wait(sem);
}
extern "C" int __wrap_cj_cjthread_semaphore_wait_no_intr(uint64_t* sem)
{
    Observe(nativeCalls, nativeAddressMismatches, WAIT_NO_INTR, sem);
    return __real_cj_cjthread_semaphore_wait_no_intr(sem);
}
extern "C" int __wrap_cj_cjthread_semaphore_post(uint64_t* sem)
{
    Observe(nativeCalls, nativeAddressMismatches, POST, sem);
    return __real_cj_cjthread_semaphore_post(sem);
}
extern "C" int __wrap_cj_cjthread_semaphore_destroy(uint64_t* sem)
{
    Observe(nativeCalls, nativeAddressMismatches, DESTROY, sem);
    return __real_cj_cjthread_semaphore_destroy(sem);
}
#endif

extern "C" int32_t ThreadSemaphorePrepare(Thread* thread, Semaphore* threadSem,
                                            LuaCJThread* lua, Semaphore* luaSem)
{
    observedThread = thread;
    observedLua = lua;
    expectedThreadSem = threadSem;
    expectedLuaSem = luaSem;
    std::memset(nativeCalls, 0, sizeof(nativeCalls));
    std::memset(libcCalls, 0, sizeof(libcCalls));
    nativeAddressMismatches = 0;
    libcAddressMismatches = 0;
    snapshotCount = 0;
    std::memcpy(threadBaseline, thread, sizeof(Thread));
    std::memcpy(luaBaseline, lua, sizeof(LuaCJThread));
    std::fprintf(stderr,
        "THREAD_SEMAPHORE_RAW_ADDRESS owner=Thread owner_address=%p cangjie_field=%p cpp_field=%p\n",
        static_cast<void*>(thread), static_cast<void*>(threadSem), static_cast<void*>(&thread->sem));
    std::fprintf(stderr,
        "THREAD_SEMAPHORE_RAW_ADDRESS owner=LuaCJThread owner_address=%p cangjie_field=%p cpp_field=%p\n",
        static_cast<void*>(lua), static_cast<void*>(luaSem), static_cast<void*>(&lua->sem));
    return threadSem == &thread->sem && luaSem == &lua->sem &&
        reinterpret_cast<uintptr_t>(threadSem) - reinterpret_cast<uintptr_t>(thread) ==
            offsetof(Thread, sem) &&
        reinterpret_cast<uintptr_t>(luaSem) - reinterpret_cast<uintptr_t>(lua) ==
            offsetof(LuaCJThread, sem) && CheckFields() ? 0 : 1;
}

extern "C" int32_t ThreadSemaphoreSnapshot(int32_t stage)
{
    if (stage < 0 || static_cast<size_t>(stage) != snapshotCount || snapshotCount >= SNAPSHOTS) {
        return 1;
    }
    std::memcpy(threadSnapshots[snapshotCount], observedThread, sizeof(Thread));
    std::memcpy(luaSnapshots[snapshotCount], observedLua, sizeof(LuaCJThread));
    if (!OutsideSemaphoreUnchanged(threadSnapshots[snapshotCount], threadBaseline, sizeof(Thread),
            offsetof(Thread, sem)) ||
        !OutsideSemaphoreUnchanged(luaSnapshots[snapshotCount], luaBaseline, sizeof(LuaCJThread),
            offsetof(LuaCJThread, sem))) {
        return 2;
    }
    ++snapshotCount;
    return 0;
}

extern "C" int32_t ThreadSemaphoreFinish(int32_t threadInit, int32_t luaInit,
                                           int32_t threadWait, int32_t luaPost,
                                           int32_t threadPost, int32_t luaWait,
                                           int32_t threadDestroy, int32_t luaDestroy)
{
    const bool returnsOk = threadInit == 0 && luaInit == 0 && threadWait == 0 && luaPost == 0 &&
        threadPost == 0 && luaWait == 0 && threadDestroy == 0 && luaDestroy == 0;
    const bool callsOk = nativeCalls[INIT] == 2 && nativeCalls[WAIT] == 1 &&
        nativeCalls[WAIT_NO_INTR] == 1 && nativeCalls[POST] == 2 && nativeCalls[DESTROY] == 2 &&
        libcCalls[INIT] == 2 && libcCalls[WAIT] == 1 && libcCalls[WAIT_NO_INTR] == 1 &&
        libcCalls[POST] == 2 && libcCalls[DESTROY] == 2;
    if (!returnsOk || !callsOk || nativeAddressMismatches != 0 || libcAddressMismatches != 0 ||
        snapshotCount != SNAPSHOTS || !CheckFields()) {
        return 1;
    }
    PrintLayouts();
    PrintRepresentations();
    std::printf("THREAD_SEMAPHORE_FIELDS thread_state=4 tid=16909060 osThread=72623859790382856 "
        "context=1,2,3,4,5,6,7,8,9,10 isSearching=1 pointers=0,0,0,0,0,0,0,0,0,0 "
        "lua_state=287454020 lua_pointers=0,0,0,0 attr_zero=128\n");
    std::printf("THREAD_SEMAPHORE_FIELD_ADDRESS thread_offset=%zu lua_offset=%zu "
        "cangjie_equals_cpp=2 native_address_mismatches=0 libc_address_mismatches=0 status=PASS\n",
        offsetof(Thread, sem), offsetof(LuaCJThread, sem));
    std::printf("THREAD_SEMAPHORE_RETURNS thread_init=0 lua_init=0 thread_wait_no_intr=0 "
        "lua_post=0 thread_post=0 lua_wait=0 thread_destroy=0 lua_destroy=0\n");
    std::printf("THREAD_SEMAPHORE_LEAVES native_init=2 native_wait=1 native_wait_no_intr=1 "
        "native_post=2 native_destroy=2 libc_init=2 libc_wait=1 libc_wait_no_intr=1 "
        "libc_post=2 libc_destroy=2 original_addresses=2 status=PASS\n");
    std::printf("THREAD_SEMAPHORE_OUTSIDE snapshots=5 thread_unchanged=5 lua_unchanged=5 status=PASS\n");
    for (size_t stage = 0; stage < SNAPSHOTS; ++stage) {
        PrintBytes("Thread", stage, threadSnapshots[stage], sizeof(Thread));
        PrintBytes("LuaCJThread", stage, luaSnapshots[stage], sizeof(LuaCJThread));
    }
    return 0;
}

#ifdef THREAD_SEMAPHORE_LAYOUT_ORACLE
int main()
{
    Thread thread;
    LuaCJThread lua;
    SetOracleFields(thread, lua);
    if (ThreadSemaphorePrepare(&thread, &thread.sem, &lua, &lua.sem) != 0 ||
        ThreadSemaphoreSnapshot(0) != 0) {
        return 1;
    }
    const int threadInit = ApiInit(&thread.sem, 0, 1);
    const int luaInit = ApiInit(&lua.sem, 0, 0);
    if (ThreadSemaphoreSnapshot(1) != 0) {
        return 2;
    }
    const int threadWait = ApiWaitNoIntr(&thread.sem);
    const int luaPost = ApiPost(&lua.sem);
    if (ThreadSemaphoreSnapshot(2) != 0) {
        return 3;
    }
    const int threadPost = ApiPost(&thread.sem);
    const int luaWait = ApiWait(&lua.sem);
    if (ThreadSemaphoreSnapshot(3) != 0) {
        return 4;
    }
    const int threadDestroy = ApiDestroy(&thread.sem);
    const int luaDestroy = ApiDestroy(&lua.sem);
    if (ThreadSemaphoreSnapshot(4) != 0) {
        return 5;
    }
    return ThreadSemaphoreFinish(threadInit, luaInit, threadWait, luaPost, threadPost, luaWait,
        threadDestroy, luaDestroy);
}
#endif
