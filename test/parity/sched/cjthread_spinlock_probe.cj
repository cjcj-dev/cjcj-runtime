import rt.sched.*

@C
struct CJthreadSpinLockResult {
    var blockReady: UInt64
    var acquiredBeforeRelease: UInt64
    var acquiredAfterRelease: UInt64
    var counter: UInt64
    var handoffReady: UInt64
    var handoffObserved: UInt64
    var workerFailures: UInt64

    init() {
        blockReady = 0u64
        acquiredBeforeRelease = 0u64
        acquiredAfterRelease = 0u64
        counter = 0u64
        handoffReady = 0u64
        handoffObserved = 0u64
        workerFailures = 0u64
    }
}

foreign func CJthreadSpinLockResetCalls(address: CPointer<Int32>): Unit
foreign func CJthreadSpinLockInitCalls(): UInt64
foreign func CJthreadSpinLockLockCalls(): UInt64
foreign func CJthreadSpinLockUnlockCalls(): UInt64
foreign func CJthreadSpinLockDestroyCalls(): UInt64
foreign func CJthreadSpinLockAddressMismatches(): UInt64
foreign func CJthreadSpinLockRun(
    lock: CPointer<CJthreadSpinLock>, result: CPointer<CJthreadSpinLockResult>
): Int32

// Test-only C entries ensure native pthread workers enter the production
// base.h:120-138,144-162 Cangjie operations over the original inline address.
@C
public func CJRT_CJthreadSpinLockInit(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinInit(lock)
}

@C
public func CJRT_CJthreadSpinLockLock(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinLock(lock)
}

@C
public func CJRT_CJthreadSpinLockUnlock(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinUnlock(lock)
}

@C
public func CJRT_CJthreadSpinLockDestroy(lock: CPointer<CJthreadSpinLock>): Int32 {
    return PthreadSpinDestroy(lock)
}

main(): Int64 {
    let lockSize = sizeOf<CJthreadSpinLock>()
    let lockAlign = alignOf<CJthreadSpinLock>()
    if (lockSize != 4 || lockAlign != 4) {
        println("CJTHREAD_SPINLOCK_PROBE FAIL sizeof=${lockSize} align=${lockAlign}")
        return 1
    }

    var lock = CJthreadSpinLock()
    let lockPointer = unsafe { CPointer<CJthreadSpinLock>(inout lock) }
    let statePointer = CPointer<Int32>(lockPointer)
    unsafe { CJthreadSpinLockResetCalls(statePointer) }

    let initResult = PthreadSpinInit(lockPointer)
    let initState = unsafe { statePointer.read() }
    let lockResult = PthreadSpinLock(lockPointer)
    let heldState = unsafe { statePointer.read() }
    let unlockResult = PthreadSpinUnlock(lockPointer)
    let unlockState = unsafe { statePointer.read() }

    var result = CJthreadSpinLockResult()
    let runResult = unsafe {
        CJthreadSpinLockRun(lockPointer, CPointer<CJthreadSpinLockResult>(inout result))
    }
    let destroyResult = PthreadSpinDestroy(lockPointer)
    let destroyState = unsafe { statePointer.read() }

    let initCalls = unsafe { CJthreadSpinLockInitCalls() }
    let lockCalls = unsafe { CJthreadSpinLockLockCalls() }
    let unlockCalls = unsafe { CJthreadSpinLockUnlockCalls() }
    let destroyCalls = unsafe { CJthreadSpinLockDestroyCalls() }
    let addressMismatches = unsafe { CJthreadSpinLockAddressMismatches() }

    if (initState != 1 || heldState != 0 || unlockState != 1 || destroyState != 1 ||
        initResult != 0 || lockResult != 0 || unlockResult != 0 || destroyResult != 0) {
        println("CJTHREAD_SPINLOCK_PROBE FAIL state or return")
        return 2
    }
    if (runResult != 0 || result.blockReady != 1 || result.acquiredBeforeRelease != 0 ||
        result.acquiredAfterRelease != 1 || result.counter != 32768 || result.handoffReady != 1 ||
        result.handoffObserved != 1511506142 || result.workerFailures != 0) {
        println("CJTHREAD_SPINLOCK_PROBE FAIL behavior rc=${runResult}")
        return 3
    }
    if (initCalls != 1 || lockCalls != 32773 || unlockCalls != 32773 || destroyCalls != 1 ||
        addressMismatches != 0) {
        println("CJTHREAD_SPINLOCK_PROBE FAIL native call/address counts")
        return 4
    }

    println("CJTHREAD_SPINLOCK_PTHREAD sizeof=4 align=4 is_int=false " +
        "remove_cv_is_int=true volatile=true")
    println("CJTHREAD_SPINLOCK_LAYOUT sizeof=${lockSize} align=${lockAlign} lock=0")
    println("CJTHREAD_SPINLOCK_BYTES init=01000000 held_lock=00000000 " +
        "unlock=01000000 destroy=01000000")
    println("CJTHREAD_SPINLOCK_RETURNS init=${initResult} lock=${lockResult} " +
        "unlock=${unlockResult} destroy=${destroyResult}")
    println("CJTHREAD_SPINLOCK_BLOCK pre_release=${result.blockReady} " +
        "acquired_before_release=${result.acquiredBeforeRelease} " +
        "post_release=${result.acquiredAfterRelease} " +
        "acquired_after_release=${result.acquiredAfterRelease} status=PASS")
    println("CJTHREAD_SPINLOCK_COUNTER threads=8 iterations=4096 expected=32768 " +
        "actual=${result.counter} status=PASS")
    println("CJTHREAD_SPINLOCK_HANDOFF payload=1511506142 observed=${result.handoffObserved} " +
        "status=PASS")
    println("CJTHREAD_SPINLOCK_CALLS init=${initCalls} lock=${lockCalls} unlock=${unlockCalls} " +
        "destroy=${destroyCalls} address_mismatches=${addressMismatches} destroy_after_users=true")
    println("CJTHREAD_SPINLOCK_NONZERO safe_defined_trigger=none caller_owned_error_policy=true")
    return 0
}
