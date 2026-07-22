package cjthreadpreemption.noheap

import rt.sched.CJThreadPreemptOffCntAdd
import rt.sched.CJThreadPreemptOffCntSub
import rt.sched.CJThreadResched

foreign func CJThreadPreemptionObserve(addResult: Int32, subResult: Int32,
    reschedEntry: CPointer<Unit>): Int32

// Execute add/sub in a real managed CJThread. Resched remains a referenced
// production root because invoking it here would intentionally yield and make
// the parity transcript scheduler-dependent.
@C
public func CJRT_CJThreadPreemptionRun(): Int32 {
    let addResult = CJThreadPreemptOffCntAdd()
    let subResult = CJThreadPreemptOffCntSub()
    return unsafe {
        CJThreadPreemptionObserve(addResult, subResult,
            CPointer<Unit>(CJThreadResched))
    }
}
