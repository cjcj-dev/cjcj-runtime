import rt.base.*

main(): Int64 {
    let rwLockSize = sizeOf<RwLock>()
    if (rwLockSize != 4) {
        println("RWLOCK_PROBE FAIL sizeof=${rwLockSize}, expected=4")
        return 1
    }

    var lock = RwLock()
    if (!lock.TryLockWrite()) {
        println("RWLOCK_PROBE FAIL fresh write")
        return 2
    }
    if (lock.TryLockWrite()) {
        println("RWLOCK_PROBE FAIL duplicate write")
        return 3
    }
    lock.UnlockWrite()

    if (!lock.TryLockRead()) {
        println("RWLOCK_PROBE FAIL first read")
        return 4
    }
    lock.LockRead()
    if (lock.TryLockWrite()) {
        println("RWLOCK_PROBE FAIL write while read-held")
        return 5
    }
    lock.UnlockRead()
    lock.UnlockRead()

    if (!lock.TryLockWrite()) {
        println("RWLOCK_PROBE FAIL write after reads")
        return 6
    }
    lock.UnlockWrite()

    println("RWLOCK_PROBE PASS sizeof=${rwLockSize}")
    return 0
}
