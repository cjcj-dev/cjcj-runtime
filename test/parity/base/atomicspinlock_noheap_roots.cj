package atomicspinlock.noheap

import rt.base.AtomicSpinLock
import rt.base.Lock as AtomicSpinLockLock
import rt.base.Unlock as AtomicSpinLockUnlock
import rt.base.TryLock as AtomicSpinLockTryLock

// Base/AtomicSpinLock.h:16-17,29. Construct one inline lock and observe its
// clear byte without copying the lock value.
public func Construct(): UInt8 {
    var lock = AtomicSpinLock()
    return unsafe { CPointer<UInt8>(CPointer<AtomicSpinLock>(inout lock)).read() }
}

// Base/AtomicSpinLock.h:19-22.
public func Lock(lock: CPointer<AtomicSpinLock>): Unit {
    AtomicSpinLockLock(lock)
}

// Base/AtomicSpinLock.h:24.
public func Unlock(lock: CPointer<AtomicSpinLock>): Unit {
    AtomicSpinLockUnlock(lock)
}

// Base/AtomicSpinLock.h:26.
public func TryLock(lock: CPointer<AtomicSpinLock>): Bool {
    return AtomicSpinLockTryLock(lock)
}
