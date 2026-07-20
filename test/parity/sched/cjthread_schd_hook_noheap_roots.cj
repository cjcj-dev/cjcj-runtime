package cjthreadschdhook.noheap

import rt.sched.CJThreadSchdHook
import rt.sched.SCHD_STOP
import rt.sched.SCHD_CREATE_MUTATOR
import rt.sched.SCHD_DESTROY_MUTATOR
import rt.sched.SCHD_PREEMPT_REQ
import rt.sched.SCHD_NEW_MUTATOR
import rt.sched.SCHD_HOOK_BUTT

foreign func CJThreadSchdHookObserve(stop: UInt32, createMutator: UInt32,
    destroyMutator: UInt32, preemptRequest: UInt32, newMutator: UInt32,
    hookButt: UInt32, aliasSize: UIntNative, aliasAlign: UIntNative,
    aliasSigned: UInt32): Int32

// schedule.h:332-342. This fixed root carries only the six unsigned ABI values;
// the real C++ owner oracle independently validates ScheduleManager:211.
@C
public func CJRT_CJThreadSchdHookRun(): Int32 {
    return unsafe {
        CJThreadSchdHookObserve(SCHD_STOP, SCHD_CREATE_MUTATOR,
            SCHD_DESTROY_MUTATOR, SCHD_PREEMPT_REQ, SCHD_NEW_MUTATOR,
            SCHD_HOOK_BUTT, sizeOf<CJThreadSchdHook>(),
            alignOf<CJThreadSchdHook>(), 0u32)
    }
}
