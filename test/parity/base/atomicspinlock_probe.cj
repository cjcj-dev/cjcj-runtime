import rt.base.*

@C
struct AtomicSpinLockResult {
    var blockReady: UInt64
    var acquiredBeforeRelease: UInt64
    var acquiredAfterRelease: UInt64
    var counter: UInt64
    var counterFinalByte: UInt64
    var handoffReady: UInt64
    var handoffObserved: UInt64
    var handoffFinalByte: UInt64

    init() {
        blockReady = 0u64
        acquiredBeforeRelease = 0u64
        acquiredAfterRelease = 0u64
        counter = 0u64
        counterFinalByte = 0u64
        handoffReady = 0u64
        handoffObserved = 0u64
        handoffFinalByte = 0u64
    }
}

foreign func AtomicSpinLockRun(lock: CPointer<AtomicSpinLock>,
    result: CPointer<AtomicSpinLockResult>): Int32

// Test-only C entries used by native pthread orchestration. Each entry invokes
// the production AtomicSpinLock operation over the original inline object.
@C
public func CJRT_AtomicSpinLockLock(lock: CPointer<AtomicSpinLock>): Unit {
    lock.Lock()
}

@C
public func CJRT_AtomicSpinLockUnlock(lock: CPointer<AtomicSpinLock>): Unit {
    lock.Unlock()
}

@C
public func CJRT_AtomicSpinLockTryLock(lock: CPointer<AtomicSpinLock>): Bool {
    return lock.TryLock()
}

main(): Int64 {
    let lockSize = sizeOf<AtomicSpinLock>()
    let lockAlign = alignOf<AtomicSpinLock>()
    if (lockSize != 1 || lockAlign != 1) {
        println("ATOMICSPINLOCK_PROBE FAIL sizeof=${lockSize} align=${lockAlign}")
        return 1
    }

    var lock = AtomicSpinLock()
    let lockPointer = unsafe { CPointer<AtomicSpinLock>(inout lock) }
    let statePointer = CPointer<UInt8>(lockPointer)
    let constructByte = unsafe { statePointer.read() }
    let first = lockPointer.TryLock()
    let trySuccessByte = unsafe { statePointer.read() }
    let second = lockPointer.TryLock()
    let tryFailedByte = unsafe { statePointer.read() }
    lockPointer.Unlock()
    let unlockByte = unsafe { statePointer.read() }
    lockPointer.Lock()
    let lockByte = unsafe { statePointer.read() }
    lockPointer.Unlock()
    let finalUnlockByte = unsafe { statePointer.read() }

    println("ATOMICSPINLOCK_LAYOUT sizeof=${lockSize} align=${lockAlign} state=0")
    println("ATOMICSPINLOCK_BYTES construct=${constructByte} try_success=${trySuccessByte} " +
        "try_failed=${tryFailedByte} unlock=${unlockByte} lock=${lockByte} " +
        "final_unlock=${finalUnlockByte}")
    println("ATOMICSPINLOCK_TRY clear=${first} held=${second} status=PASS")

    var result = AtomicSpinLockResult()
    let runResult = unsafe { AtomicSpinLockRun(lockPointer,
        CPointer<AtomicSpinLockResult>(inout result)) }
    if (runResult != 0 || result.blockReady != 1 || result.acquiredBeforeRelease != 0 ||
        result.acquiredAfterRelease != 1 || result.counter != 16384 ||
        result.counterFinalByte != 0 || result.handoffReady != 1 ||
        result.handoffObserved != 1511506142 || result.handoffFinalByte != 0) {
        println("ATOMICSPINLOCK_PROBE FAIL behavior rc=${runResult}")
        return 2
    }

    println("ATOMICSPINLOCK_BLOCK pre_release=${result.blockReady} " +
        "acquired_before_release=${result.acquiredBeforeRelease} " +
        "post_release=${result.acquiredAfterRelease} " +
        "acquired_after_release=${result.acquiredAfterRelease} status=PASS")
    println("ATOMICSPINLOCK_COUNTER threads=4 iterations=4096 expected=16384 " +
        "actual=${result.counter} final=${result.counterFinalByte} status=PASS")
    println("ATOMICSPINLOCK_HANDOFF payload=1511506142 observed=${result.handoffObserved} " +
        "final=${result.handoffFinalByte} status=PASS")
    return 0
}
