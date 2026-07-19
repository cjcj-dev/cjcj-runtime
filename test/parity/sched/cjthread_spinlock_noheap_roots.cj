package cjthreadspinlock.noheap

import rt.sched.CJthreadSpinLock
import rt.sched.PthreadSpinInit
import rt.sched.PthreadSpinLock
import rt.sched.PthreadSpinUnlock
import rt.sched.PthreadSpinDestroy

// CJThread schedule/include/inner/base.h:120-123,144-147.
public func Init(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinInit(lock)
}

// CJThread schedule/include/inner/base.h:125-128,149-152.
public func Lock(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinLock(lock)
}

// CJThread schedule/include/inner/base.h:130-133,154-157.
public func Unlock(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinUnlock(lock)
}

// CJThread schedule/include/inner/base.h:135-138,159-162.
public func Destroy(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinDestroy(lock)
}
