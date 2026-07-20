package cjthreadstatehook.noheap

import rt.sched.CJThreadStateHook
import rt.sched.CJTHREAD_BEFORE_PARK
import rt.sched.CJTHREAD_AFTER_PARK
import rt.sched.CJTHREAD_BEFORE_RESCHED
import rt.sched.CJTHREAD_AFTER_RESCHED
import rt.sched.CJTHREAD_STATE_HOOK_BUTT

foreign func CJThreadStateHookObserve(beforePark: UInt32, afterPark: UInt32,
    beforeResched: UInt32, afterResched: UInt32, hookButt: UInt32,
    aliasSize: UIntNative, aliasAlign: UIntNative, aliasSigned: UInt32): Int32

// schedule.h:344-353. This fixed root carries only the five unsigned ABI values;
// the real C++ owner oracle independently validates ScheduleManager:212.
@C
public func CJRT_CJThreadStateHookRun(): Int32 {
    return unsafe {
        CJThreadStateHookObserve(CJTHREAD_BEFORE_PARK, CJTHREAD_AFTER_PARK,
            CJTHREAD_BEFORE_RESCHED, CJTHREAD_AFTER_RESCHED,
            CJTHREAD_STATE_HOOK_BUTT, sizeOf<CJThreadStateHook>(),
            alignOf<CJThreadStateHook>(), 0u32)
    }
}
