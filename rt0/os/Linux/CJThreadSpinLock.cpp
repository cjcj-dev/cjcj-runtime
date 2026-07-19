// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <cstdint>
#include <pthread.h>

static_assert(sizeof(pthread_spinlock_t) == sizeof(int32_t),
    "Linux x86_64 pthread_spinlock_t size changed");
static_assert(alignof(pthread_spinlock_t) == alignof(int32_t),
    "Linux x86_64 pthread_spinlock_t alignment changed");

// CJThread schedule/include/inner/base.h:144-147. The boundary does not own
// storage: cast the supplied inline address, make the one source call, and
// return the untouched native result.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_pthread_spin_init(int32_t* lock)
{
    return pthread_spin_init(reinterpret_cast<pthread_spinlock_t*>(lock), PTHREAD_PROCESS_PRIVATE);
}

// CJThread schedule/include/inner/base.h:149-152.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_pthread_spin_lock(int32_t* lock)
{
    return pthread_spin_lock(reinterpret_cast<pthread_spinlock_t*>(lock));
}

// CJThread schedule/include/inner/base.h:154-157.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_pthread_spin_unlock(int32_t* lock)
{
    return pthread_spin_unlock(reinterpret_cast<pthread_spinlock_t*>(lock));
}

// CJThread schedule/include/inner/base.h:159-162.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_pthread_spin_destroy(int32_t* lock)
{
    return pthread_spin_destroy(reinterpret_cast<pthread_spinlock_t*>(lock));
}
