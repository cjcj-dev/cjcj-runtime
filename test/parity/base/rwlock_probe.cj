import rt.base.*

main(): Int64 {
    let rwLockSize = sizeOf<RwLock>()
    let rwLockAlign = alignOf<RwLock>()
    if (rwLockSize != 4 || rwLockAlign != 4) {
        println("RWLOCK_PROBE FAIL sizeof=${rwLockSize} align=${rwLockAlign}")
        return 1
    }

    var lock = RwLock()
    let lockPointer = unsafe { CPointer<RwLock>(inout lock) }
    let freshCount = unsafe { CPointer<Int32>(CPointer<UInt8>(lockPointer)).read() }
    let freshWrite = lock.TryLockWrite()
    if (!freshWrite) {
        println("RWLOCK_PROBE FAIL fresh write")
        return 2
    }
    let duplicateWrite = lock.TryLockWrite()
    if (duplicateWrite) {
        println("RWLOCK_PROBE FAIL duplicate write")
        return 3
    }
    lock.UnlockWrite()
    let afterWrite = unsafe { CPointer<Int32>(CPointer<UInt8>(lockPointer)).read() }

    let firstRead = lock.TryLockRead()
    if (!firstRead) {
        println("RWLOCK_PROBE FAIL first read")
        return 4
    }
    let afterFirstRead = unsafe { CPointer<Int32>(CPointer<UInt8>(lockPointer)).read() }
    lock.LockRead()
    let afterSecondRead = unsafe { CPointer<Int32>(CPointer<UInt8>(lockPointer)).read() }
    let writeWhileRead = lock.TryLockWrite()
    if (writeWhileRead) {
        println("RWLOCK_PROBE FAIL write while read-held")
        return 5
    }
    lock.UnlockRead()
    let afterFirstUnlock = unsafe { CPointer<Int32>(CPointer<UInt8>(lockPointer)).read() }
    lock.UnlockRead()
    let afterSecondUnlock = unsafe { CPointer<Int32>(CPointer<UInt8>(lockPointer)).read() }

    let writeAfterReads = lock.TryLockWrite()
    if (!writeAfterReads) {
        println("RWLOCK_PROBE FAIL write after reads")
        return 6
    }
    lock.UnlockWrite()
    let finalCount = unsafe { CPointer<Int32>(CPointer<UInt8>(lockPointer)).read() }

    println("RWLOCK_LAYOUT sizeof=${rwLockSize} align=${rwLockAlign} lockCount=0")
    println("RWLOCK_STATE fresh_count=${freshCount} fresh_write=${freshWrite} " +
        "duplicate_write=${duplicateWrite} after_write=${afterWrite} first_read=${firstRead} " +
        "after_first_read=${afterFirstRead} after_second_read=${afterSecondRead} " +
        "write_while_read=${writeWhileRead} after_first_unlock=${afterFirstUnlock} " +
        "after_second_unlock=${afterSecondUnlock} write_after_reads=${writeAfterReads} " +
        "final_count=${finalCount}")
    return 0
}
