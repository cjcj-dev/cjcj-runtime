package cjthreadstate.noheap

import rt.sched.LuaCJThread
import rt.sched.LuaCJThreadState
import rt.sched.LUA_CJTHREAD_INIT
import rt.sched.LUA_CJTHREAD_SUSPENDING
import rt.sched.LUA_CJTHREAD_RUNNING
import rt.sched.LUA_CJTHREAD_DONE

foreign func memset(destination: CPointer<Unit>, value: Int32, count: UIntNative): CPointer<Unit>
foreign func CJThreadStateObserve(owner: CPointer<LuaCJThread>, stateInit: Int32,
    suspending: Int32, running: Int32, done: Int32, aliasSize: UIntNative,
    aliasAlign: UIntNative, signedMinusOne: Int32): Int32

// schedule.h:415-420 and cjthread.h:160-168. Constants cross this fixed root as
// signed int storage values; the complete caller-owned descriptor remains AS0.
@C
public func CJRT_CJThreadStateRun(): Int32 {
    var owner = LuaCJThread()
    let ownerPointer = unsafe { CPointer<LuaCJThread>(inout owner) }
    unsafe { memset(CPointer<Unit>(ownerPointer), 0, sizeOf<LuaCJThread>()) }
    return unsafe {
        CJThreadStateObserve(ownerPointer, LUA_CJTHREAD_INIT, LUA_CJTHREAD_SUSPENDING,
            LUA_CJTHREAD_RUNNING, LUA_CJTHREAD_DONE, sizeOf<LuaCJThreadState>(),
            alignOf<LuaCJThreadState>(), -1)
    }
}
