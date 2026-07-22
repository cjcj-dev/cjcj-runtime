// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

// Common/PagePool.h:152 and Heap/Allocator/RegionList.h:169. The shipped
// Win64 runtime uses llvm-mingw libc++'s pthread backend. __libcpp_mutex_t is
// pthread_mutex_t, and llvm-mingw's pthread_mutex_t is one pointer.
using pthread_mutex_t = void*;
static_assert(sizeof(pthread_mutex_t) == 8, "Win64 pthread_mutex_t size changed");
static_assert(alignof(pthread_mutex_t) == 8, "Win64 pthread_mutex_t alignment changed");

extern "C" int pthread_mutex_init(pthread_mutex_t* mutex, const void* attributes);
extern "C" int pthread_mutex_destroy(pthread_mutex_t* mutex);
extern "C" int pthread_mutex_lock(pthread_mutex_t* mutex);
extern "C" int pthread_mutex_unlock(pthread_mutex_t* mutex);
extern "C" [[noreturn]] void abort();

extern "C" void CJRT_PagePoolMutexConstruct(void* storage)
{
    if (pthread_mutex_init(static_cast<pthread_mutex_t*>(storage), nullptr) != 0) {
        abort();
    }
}

extern "C" void CJRT_PagePoolMutexDestroy(void* storage)
{
    (void)pthread_mutex_destroy(static_cast<pthread_mutex_t*>(storage));
}

extern "C" void CJRT_PagePoolMutexLock(void* storage)
{
    if (pthread_mutex_lock(static_cast<pthread_mutex_t*>(storage)) != 0) {
        abort();
    }
}

extern "C" void CJRT_PagePoolMutexUnlock(void* storage)
{
    if (pthread_mutex_unlock(static_cast<pthread_mutex_t*>(storage)) != 0) {
        abort();
    }
}
