// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <atomic>
#include <pthread.h>
#define private public
#include "Base/RwLock.h"
#undef private

#include <cstddef>
#include <iostream>

int main()
{
    using MapleRuntime::RwLock;
    RwLock lock;
    const int freshCount = lock.lockCount.load();
    const bool freshWrite = lock.TryLockWrite();
    const bool duplicateWrite = lock.TryLockWrite();
    lock.UnlockWrite();
    const int afterWrite = lock.lockCount.load();
    const bool firstRead = lock.TryLockRead();
    const int afterFirstRead = lock.lockCount.load();
    lock.LockRead();
    const int afterSecondRead = lock.lockCount.load();
    const bool writeWhileRead = lock.TryLockWrite();
    lock.UnlockRead();
    const int afterFirstUnlock = lock.lockCount.load();
    lock.UnlockRead();
    const int afterSecondUnlock = lock.lockCount.load();
    const bool writeAfterReads = lock.TryLockWrite();
    lock.UnlockWrite();
    const int finalCount = lock.lockCount.load();

    std::cout << std::boolalpha;
    std::cout << "RWLOCK_LAYOUT sizeof=" << sizeof(RwLock) << " align=" << alignof(RwLock)
              << " lockCount=" << offsetof(RwLock, lockCount) << '\n';
    std::cout << "RWLOCK_STATE fresh_count=" << freshCount << " fresh_write=" << freshWrite
              << " duplicate_write=" << duplicateWrite << " after_write=" << afterWrite
              << " first_read=" << firstRead << " after_first_read=" << afterFirstRead
              << " after_second_read=" << afterSecondRead << " write_while_read=" << writeWhileRead
              << " after_first_unlock=" << afterFirstUnlock << " after_second_unlock=" << afterSecondUnlock
              << " write_after_reads=" << writeAfterReads << " final_count=" << finalCount << '\n';
    return 0;
}
