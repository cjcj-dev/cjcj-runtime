package atomicspinlock.noheap

import rt.base.*

// Base/AtomicSpinLock.h:16-17,29. Construct one inline lock and observe its
// clear byte without copying the lock value.
public func Construct(): UInt8 {
    var lock = AtomicSpinLock()
    return unsafe { CPointer<UInt8>(CPointer<AtomicSpinLock>(inout lock)).read() }
}

// Base/AtomicSpinLock.h:19-22.
public func Lock(lock: CPointer<AtomicSpinLock>): Unit {
    rt.base.Lock(lock)
}

// Base/AtomicSpinLock.h:24.
public func Unlock(lock: CPointer<AtomicSpinLock>): Unit {
    rt.base.Unlock(lock)
}

// Base/AtomicSpinLock.h:26.
public func TryLock(lock: CPointer<AtomicSpinLock>): Bool {
    return rt.base.TryLock(lock)
}
