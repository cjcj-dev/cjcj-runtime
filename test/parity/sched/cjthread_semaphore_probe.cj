import rt.sched.*

foreign func CJthreadSemaphoreResetCalls(address: CPointer<UInt64>): Unit
foreign func CJthreadSemaphoreSetErrno(value: Int32): Unit
foreign func CJthreadSemaphoreGetErrno(): Int32
foreign func CJthreadSemaphoreRunAfterInit(
    sem: CPointer<Semaphore>, initResult: Int32, initErrno: Int32
): Int32

// Test-only C entries make native pthread workers enter all five production
// Cangjie operations from CJThread schedule/include/inner/base.h:86-113.
@C
public func CJRT_CJthreadSemaphoreInit(
    sem: CPointer<Semaphore>, pshared: Int32, value: UInt32
): Int32 {
    return SemaphoreInit(sem, pshared, value)
}

@C
public func CJRT_CJthreadSemaphoreWait(sem: CPointer<Semaphore>): Int32 {
    return SemaphoreWait(sem)
}

@C
public func CJRT_CJthreadSemaphoreWaitNoIntr(sem: CPointer<Semaphore>): Int32 {
    return SemaphoreWaitNoIntr(sem)
}

@C
public func CJRT_CJthreadSemaphorePost(sem: CPointer<Semaphore>): Int32 {
    return SemaphorePost(sem)
}

@C
public func CJRT_CJthreadSemaphoreDestroy(sem: CPointer<Semaphore>): Int32 {
    return SemaphoreDestroy(sem)
}

main(): Int64 {
    if (sizeOf<Semaphore>() != 32 || alignOf<Semaphore>() != 8) {
        return 2
    }
    var sem = Semaphore()
    let semPointer = unsafe { CPointer<Semaphore>(inout sem) }
    unsafe {
        CJthreadSemaphoreResetCalls(CPointer<UInt64>(semPointer))
        CJthreadSemaphoreSetErrno(0)
    }
    let initResult = SemaphoreInit(semPointer, 0, 0u32)
    let initErrno = unsafe { CJthreadSemaphoreGetErrno() }
    let runResult = unsafe { CJthreadSemaphoreRunAfterInit(semPointer, initResult, initErrno) }
    return Int64(runResult)
}
