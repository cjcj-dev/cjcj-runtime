package spinlock.noheap

import rt.base.SpinLock
import rt.base.Lock as SpinLockLock
import rt.base.Unlock as SpinLockUnlock
import rt.base.TryLock as SpinLockTryLock

// Base/SpinLock.h:18,28-30. Construct one inline lock and observe the field
// through its original address without copying the lock value.
public func Construct(): Int32 {
    var lock = SpinLock()
    return unsafe { CPointer<Int32>(CPointer<SpinLock>(inout lock)).read() }
}

// Base/SpinLock.h:22.
public func Lock(lock: CPointer<SpinLock>): Unit {
    SpinLockLock(lock)
}

// Base/SpinLock.h:24.
public func Unlock(lock: CPointer<SpinLock>): Unit {
    SpinLockUnlock(lock)
}

// Base/SpinLock.h:26.
public func TryLock(lock: CPointer<SpinLock>): Bool {
    return SpinLockTryLock(lock)
}

// Base/SpinLock.h:20,33-39 intentionally have no roots: the deterministic
// destructor and ScopedEnterSpinLock are blocked, not silently omitted.
