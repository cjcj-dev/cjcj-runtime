package cjthreadcreatesource.noheap

import rt.sched.CJThreadCreateSource
import rt.sched.CJTHREAD_CREATE_SOURCE_DEFAULT
import rt.sched.CJTHREAD_CREATE_SOURCE_SIGNAL
import rt.sched.CJTHREAD_CREATE_SOURCE_FINALIZER

foreign func CJThreadCreateSourceObserve(sourceDefault: UInt32, signal: UInt32,
    finalizer: UInt32, aliasSize: UIntNative, aliasAlign: UIntNative,
    aliasSigned: UInt32): Int32

// schedule.h:403-410,624-626,646-648. This fixed root carries only the three
// unsigned by-value ABI values; no owner, allocation, or lifecycle is present.
@C
public func CJRT_CJThreadCreateSourceRun(): Int32 {
    return unsafe {
        CJThreadCreateSourceObserve(CJTHREAD_CREATE_SOURCE_DEFAULT,
            CJTHREAD_CREATE_SOURCE_SIGNAL, CJTHREAD_CREATE_SOURCE_FINALIZER,
            sizeOf<CJThreadCreateSource>(), alignOf<CJThreadCreateSource>(), 0u32)
    }
}
