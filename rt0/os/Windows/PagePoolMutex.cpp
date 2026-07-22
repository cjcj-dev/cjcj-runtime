// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <cstdlib>
#include <mutex>
#include <new>
#include <pthread.h>

// Common/PagePool.h:152 and Heap/Allocator/RegionList.h:169. The shipped
// Win64 runtime uses llvm-mingw libc++, whose std::mutex is one pointer.
static_assert(sizeof(std::mutex) == 8, "Win64 std::mutex size changed");
static_assert(alignof(std::mutex) == 8, "Win64 std::mutex alignment changed");

extern "C" void CJRT_PagePoolMutexConstruct(void* storage)
{
    new (storage) std::mutex();
}

extern "C" void CJRT_PagePoolMutexDestroy(void* storage)
{
    static_cast<std::mutex*>(storage)->~mutex();
}

extern "C" void CJRT_PagePoolMutexLock(void* storage)
{
    if (pthread_mutex_lock(static_cast<pthread_mutex_t*>(storage)) != 0) {
        std::abort();
    }
}

extern "C" void CJRT_PagePoolMutexUnlock(void* storage)
{
    if (pthread_mutex_unlock(static_cast<pthread_mutex_t*>(storage)) != 0) {
        std::abort();
    }
}
