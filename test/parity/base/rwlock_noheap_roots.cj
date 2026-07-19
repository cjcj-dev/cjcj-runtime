package rwlock.noheap

import rt.base.*

// Base/RwLock.h:56-62.
public func UnlockRead(): Unit {
    var lock = RwLock()
    lock.LockWrite()
    lock.UnlockRead()
}

// Base/RwLock.h:64-68.
public func UnlockWrite(): Unit {
    var lock = RwLock()
    lock.UnlockWrite()
}
