package cjthreadsemaphore.noheap

import rt.sched.Semaphore
import rt.sched.SemaphoreInit
import rt.sched.SemaphoreWait
import rt.sched.SemaphoreWaitNoIntr
import rt.sched.SemaphorePost
import rt.sched.SemaphoreDestroy

// CJThread schedule/include/inner/base.h:86-89.
public func Init(sem: CPointer<Semaphore>, pshared: Int32, value: UInt32): Int32 {
    return SemaphoreInit(sem, pshared, value)
}

// CJThread schedule/include/inner/base.h:91-94.
public func Wait(sem: CPointer<Semaphore>): Int32 {
    return SemaphoreWait(sem)
}

// CJThread schedule/include/inner/base.h:96-103.
public func WaitNoIntr(sem: CPointer<Semaphore>): Int32 {
    return SemaphoreWaitNoIntr(sem)
}

// CJThread schedule/include/inner/base.h:105-108.
public func Post(sem: CPointer<Semaphore>): Int32 {
    return SemaphorePost(sem)
}

// CJThread schedule/include/inner/base.h:110-113.
public func Destroy(sem: CPointer<Semaphore>): Int32 {
    return SemaphoreDestroy(sem)
}
