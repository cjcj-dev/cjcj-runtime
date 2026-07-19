package threadsemaphore.noheap

import rt.sched.*

foreign func ThreadSemaphorePrepare(
    thread: CPointer<Thread>, threadSem: CPointer<Semaphore>,
    lua: CPointer<LuaCJThread>, luaSem: CPointer<Semaphore>
): Int32
foreign func ThreadSemaphoreSnapshot(stage: Int32): Int32
foreign func ThreadSemaphoreFinish(
    threadInit: Int32, luaInit: Int32, threadWait: Int32, luaPost: Int32,
    threadPost: Int32, luaWait: Int32, threadDestroy: Int32, luaDestroy: Int32
): Int32

// thread.h:52-80 and cjthread.h:160-168. Both owners are caller-owned stack
// @C values. The actual embedded members are addressed directly with inout;
// no integer offset, accessor, owner allocation, copy, or shadow pointer exists.
@C
public func CJRT_ThreadOwnerRun(): Int32 {
    var thread = Thread()
    var lua = LuaCJThread()

    // thread.h:64,68-76 and cjthread.h:166. Nonzero scalars make the complete
    // C++ transcript sensitive to field order, widths, and implicit padding.
    thread.state = THREAD_SLEEP
    thread.tid = 0x01020304
    thread.osThread = 0x0102030405060708u64
    thread.context.rsp = 1u64
    thread.context.rbp = 2u64
    thread.context.rbx = 3u64
    thread.context.rip = 4u64
    thread.context.r12 = 5u64
    thread.context.r13 = 6u64
    thread.context.r14 = 7u64
    thread.context.r15 = 8u64
    thread.context.mxcsr = 9u32
    thread.context.fpuCw = 10u16
    thread.isSearching = true
    lua.state = 0x11223344

    let threadPointer = unsafe { CPointer<Thread>(inout thread) }
    let threadSem = unsafe { CPointer<Semaphore>(inout thread.sem) }
    let luaPointer = unsafe { CPointer<LuaCJThread>(inout lua) }
    let luaSem = unsafe { CPointer<Semaphore>(inout lua.sem) }
    if (unsafe { ThreadSemaphorePrepare(threadPointer, threadSem, luaPointer, luaSem) } != 0 ||
        unsafe { ThreadSemaphoreSnapshot(0) } != 0) {
        return 10
    }

    // base.h:86-89. Use distinct initial counts so the full owner snapshots
    // also prove that each operation mutates the intended embedded object.
    let threadInit = SemaphoreInit(threadSem, 0, 1u32)
    let luaInit = SemaphoreInit(luaSem, 0, 0u32)
    if (unsafe { ThreadSemaphoreSnapshot(1) } != 0) {
        return 11
    }

    // base.h:96-108. Consume Thread's token and produce LuaCJThread's token.
    let threadWait = SemaphoreWaitNoIntr(threadSem)
    let luaPost = SemaphorePost(luaSem)
    if (unsafe { ThreadSemaphoreSnapshot(2) } != 0) {
        return 12
    }

    // base.h:91-94,105-108. Restore Thread and consume LuaCJThread without
    // blocking; both calls still receive the exact original member addresses.
    let threadPost = SemaphorePost(threadSem)
    let luaWait = SemaphoreWait(luaSem)
    if (unsafe { ThreadSemaphoreSnapshot(3) } != 0) {
        return 13
    }

    // base.h:110-113. Destroy only after both embedded semaphores have no users.
    let threadDestroy = SemaphoreDestroy(threadSem)
    let luaDestroy = SemaphoreDestroy(luaSem)
    if (unsafe { ThreadSemaphoreSnapshot(4) } != 0) {
        return 14
    }
    return unsafe {
        ThreadSemaphoreFinish(threadInit, luaInit, threadWait, luaPost,
            threadPost, luaWait, threadDestroy, luaDestroy)
    }
}
