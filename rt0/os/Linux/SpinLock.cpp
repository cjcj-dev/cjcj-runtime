// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <cstdint>
#include <pthread.h>

// Base/SpinLock.h:18. Initialize the caller-owned inline pthread storage with
// process-private sharing and preserve the source's ignored return value.
extern "C" void cj_pthread_spin_init(int32_t* p)
{
    (void)pthread_spin_init(reinterpret_cast<pthread_spinlock_t*>(p), 0);
}

// Base/SpinLock.h:22. Exactly one blocking lock call on the original address.
extern "C" void cj_pthread_spin_lock(int32_t* p)
{
    (void)pthread_spin_lock(reinterpret_cast<pthread_spinlock_t*>(p));
}

// Base/SpinLock.h:24. Exactly one unlock call on the original address.
extern "C" void cj_pthread_spin_unlock(int32_t* p)
{
    (void)pthread_spin_unlock(reinterpret_cast<pthread_spinlock_t*>(p));
}

// Base/SpinLock.h:26. Return the native code because the C++ source tests it.
extern "C" int32_t cj_pthread_spin_trylock(int32_t* p)
{
    return pthread_spin_trylock(reinterpret_cast<pthread_spinlock_t*>(p));
}
