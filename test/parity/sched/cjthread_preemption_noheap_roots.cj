package cjthreadpreemption.noheap

import rt.sched.CJThreadPreemptOffCntAdd
import rt.sched.CJThreadPreemptOffCntSub
import rt.sched.CJThreadResched

foreign func CJThreadPreemptionObserve(addResult: Int32, subResult: Int32,
    reschedResult: Int32): Int32

// Execute all three entries in a real managed CJThread. CJThreadResched has a
// specified constant-zero return contract even though it may yield once.
@C
public func CJRT_CJThreadPreemptionRun(): Int32 {
    let addResult = CJThreadPreemptOffCntAdd()
    let subResult = CJThreadPreemptOffCntSub()
    let reschedResult = CJThreadResched()
    return unsafe {
        CJThreadPreemptionObserve(addResult, subResult, reschedResult)
    }
}
