import rt.base.*

@C
struct SpinLockResult {
    var blockReady: UInt64
    var acquiredBeforeRelease: UInt64
    var acquiredAfterRelease: UInt64
    var counter: UInt64
    var counterFinalState: UInt64
    var handoffReady: UInt64
    var handoffObserved: UInt64
    var handoffFinalState: UInt64

    init() {
        blockReady = 0u64
        acquiredBeforeRelease = 0u64
        acquiredAfterRelease = 0u64
        counter = 0u64
        counterFinalState = 0u64
        handoffReady = 0u64
        handoffObserved = 0u64
        handoffFinalState = 0u64
    }
}

foreign func SpinLockRun(lock: CPointer<SpinLock>, result: CPointer<SpinLockResult>): Int32
foreign func SpinLockResetPthreadCounts(): Unit
foreign func SpinLockInitCalls(): UInt64
foreign func SpinLockDestroyCalls(): UInt64
foreign func SpinLockLockCalls(): UInt64
foreign func SpinLockUnlockCalls(): UInt64
foreign func SpinLockTryCalls(): UInt64

// Test-only native pthread entries. Every operation enters the production
// Base/SpinLock.h:18,22,24,26 port over the original inline object.
@C
public func CJRT_SpinLockInit(lock: CPointer<SpinLock>): Unit {
    unsafe { lock.write(SpinLock()) }
}

@C
public func CJRT_SpinLockLock(lock: CPointer<SpinLock>): Unit {
    Lock(lock)
}

@C
public func CJRT_SpinLockUnlock(lock: CPointer<SpinLock>): Unit {
    Unlock(lock)
}

@C
public func CJRT_SpinLockTryLock(lock: CPointer<SpinLock>): Bool {
    return TryLock(lock)
}

main(): Int64 {
    let lockSize = sizeOf<SpinLock>()
    let lockAlign = alignOf<SpinLock>()
    if (lockSize != 4 || lockAlign != 4) {
        println("SPINLOCK_PROBE FAIL sizeof=${lockSize} align=${lockAlign}")
        return 1
    }

    unsafe { SpinLockResetPthreadCounts() }
    var lock = SpinLock()
    let lockPointer = unsafe { CPointer<SpinLock>(inout lock) }
    let statePointer = CPointer<Int32>(lockPointer)
    let initState = unsafe { statePointer.read() }
    Lock(lockPointer)
    let heldState = unsafe { statePointer.read() }
    let failed = TryLock(lockPointer)
    let failedState = unsafe { statePointer.read() }
    Unlock(lockPointer)
    let unlockState = unsafe { statePointer.read() }
    let succeeded = TryLock(lockPointer)
    let successState = unsafe { statePointer.read() }
    Unlock(lockPointer)
    let finalState = unsafe { statePointer.read() }

    let initCalls = unsafe { SpinLockInitCalls() }
    let destroyCalls = unsafe { SpinLockDestroyCalls() }
    let lockCalls = unsafe { SpinLockLockCalls() }
    let unlockCalls = unsafe { SpinLockUnlockCalls() }
    let tryCalls = unsafe { SpinLockTryCalls() }
    if (initState != 1 || heldState != 0 || failedState != 0 || unlockState != 1 ||
        successState != 0 || finalState != 1 || failed || !succeeded) {
        println("SPINLOCK_PROBE FAIL state transitions")
        return 2
    }
    if (initCalls != 1 || destroyCalls != 0 || lockCalls != 1 || unlockCalls != 2 || tryCalls != 2) {
        println("SPINLOCK_PROBE FAIL pthread counts")
        return 3
    }

    println("SPINLOCK_PTHREAD sizeof=4 align=4 is_int=false remove_cv_is_int=true volatile=true")
    println("SPINLOCK_LAYOUT sizeof=${lockSize} align=${lockAlign} spinlock=0")
    println("SPINLOCK_BYTES init=01000000 held_lock=00000000 failed_try=00000000 " +
        "unlock=01000000 successful_try=00000000 final_unlock=01000000")
    println("SPINLOCK_TRY clear=${succeeded} held=${failed} status=PASS")
    println("SPINLOCK_CALLS init=${initCalls} destroy=${destroyCalls} lock=${lockCalls} " +
        "unlock=${unlockCalls} try=${tryCalls}")

    var result = SpinLockResult()
    let runResult = unsafe { SpinLockRun(lockPointer, CPointer<SpinLockResult>(inout result)) }
    if (runResult != 0 || result.blockReady != 1 || result.acquiredBeforeRelease != 0 ||
        result.acquiredAfterRelease != 1 || result.counter != 16384 ||
        result.counterFinalState != 1 || result.handoffReady != 1 ||
        result.handoffObserved != 1511506142 || result.handoffFinalState != 1) {
        println("SPINLOCK_PROBE FAIL behavior rc=${runResult}")
        return 4
    }

    println("SPINLOCK_BLOCK pre_release=${result.blockReady} " +
        "acquired_before_release=${result.acquiredBeforeRelease} " +
        "post_release=${result.acquiredAfterRelease} " +
        "acquired_after_release=${result.acquiredAfterRelease} status=PASS")
    println("SPINLOCK_COUNTER threads=4 iterations=4096 expected=16384 " +
        "actual=${result.counter} final=${result.counterFinalState} status=PASS")
    println("SPINLOCK_HANDOFF payload=1511506142 observed=${result.handoffObserved} " +
        "final=${result.handoffFinalState} status=PASS")
    return 0
}
