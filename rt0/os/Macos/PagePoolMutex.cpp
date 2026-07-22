// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

// Common/PagePool.h:152 and Heap/Allocator/RegionList.h:169 embed std::mutex.
// APPLE_ABI_FACTS.md sections 1-4 record the Darwin libc++ contract: std::mutex
// is one 64-byte, 8-aligned pthread_mutex_t with this static initializer.
struct _opaque_pthread_mutex_t {
    long sig;
    char opaque[56];
};
using pthread_mutex_t = _opaque_pthread_mutex_t;

static constexpr long PTHREAD_MUTEX_SIG_INIT = 0x32AAABA7L;
static constexpr pthread_mutex_t PTHREAD_MUTEX_INITIALIZER_VALUE = {
    PTHREAD_MUTEX_SIG_INIT, {0}
};

static_assert(sizeof(pthread_mutex_t) == 64, "Darwin pthread_mutex_t size changed");
static_assert(alignof(pthread_mutex_t) == 8, "Darwin pthread_mutex_t alignment changed");

extern "C" int pthread_mutex_destroy(pthread_mutex_t* mutex);
extern "C" int pthread_mutex_lock(pthread_mutex_t* mutex);
extern "C" int pthread_mutex_trylock(pthread_mutex_t* mutex);
extern "C" int pthread_mutex_unlock(pthread_mutex_t* mutex);
extern "C" [[noreturn]] void abort();

extern "C" void CJRT_PagePoolMutexConstruct(void* storage)
{
    *static_cast<pthread_mutex_t*>(storage) = PTHREAD_MUTEX_INITIALIZER_VALUE;
}

extern "C" bool CJRT_PagePoolMutexTryLock(void* storage)
{
    return pthread_mutex_trylock(static_cast<pthread_mutex_t*>(storage)) == 0;
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
