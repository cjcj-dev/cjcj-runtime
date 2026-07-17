// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

// APPLE_ABI_FACTS.md §1-§3: Darwin pthread_mutex_t is an 8-byte signature
// followed by 56 opaque bytes, with 64-byte size and 8-byte alignment; libc++
// std::mutex is exactly that single member. C++ consumers are PagePool.h:63,
// 117,152 and RegionList.h:30,41,86,95,117,136,144,150,154,161,169,180,191,
// 220,230,236.
struct _opaque_pthread_mutex_t {
    long __sig;
    char __opaque[56];
};
using pthread_mutex_t = _opaque_pthread_mutex_t;

static constexpr long _PTHREAD_MUTEX_SIG_init = 0x32AAABA7L;
static constexpr pthread_mutex_t PTHREAD_MUTEX_INITIALIZER = {_PTHREAD_MUTEX_SIG_init, {0}};

static_assert(sizeof(pthread_mutex_t) == 64, "Darwin pthread_mutex_t must be 64 bytes");
static_assert(alignof(pthread_mutex_t) == 8, "Darwin pthread_mutex_t must be 8-byte aligned");
// TODO(apple-verify): static_assert sizeof==64 when SDK available

extern "C" int pthread_mutex_destroy(pthread_mutex_t* mutex);
extern "C" int pthread_mutex_lock(pthread_mutex_t* mutex);
extern "C" int pthread_mutex_unlock(pthread_mutex_t* mutex);
extern "C" [[noreturn]] void abort();

// rt0/os/Linux/PagePoolMutex.cpp:13-34 mirrors the C++ std::mutex operations.
// APPLE_ABI_FACTS.md §3 supplies libc++'s static initializer bytes.
extern "C" void CJRT_PagePoolMutexConstruct(void* storage)
{
    *static_cast<pthread_mutex_t*>(storage) = PTHREAD_MUTEX_INITIALIZER;
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
