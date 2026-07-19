// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <cerrno>
#include <cstdint>
#include <semaphore.h>

static_assert(sizeof(sem_t) == sizeof(uint64_t) * 4,
    "Linux x86_64 sem_t size changed");
static_assert(alignof(sem_t) == alignof(uint64_t),
    "Linux x86_64 sem_t alignment changed");

// CJThread schedule/include/inner/base.h:86-89. The bridge owns no state: cast
// the caller-owned inline address, preserve both arguments, and return sem_init.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_semaphore_init(
    uint64_t* sem, int32_t pshared, uint32_t value)
{
    return sem_init(reinterpret_cast<sem_t*>(sem), pshared, value);
}

// CJThread schedule/include/inner/base.h:91-94.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_semaphore_wait(uint64_t* sem)
{
    return sem_wait(reinterpret_cast<sem_t*>(sem));
}

// CJThread schedule/include/inner/base.h:96-103. Keep the source do/while and
// inspect native TLS errno immediately after the corresponding sem_wait.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_semaphore_wait_no_intr(uint64_t* sem)
{
    int32_t error;
    do {
        error = sem_wait(reinterpret_cast<sem_t*>(sem));
    } while (error != 0 && errno == EINTR);
    return error;
}

// CJThread schedule/include/inner/base.h:105-108.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_semaphore_post(uint64_t* sem)
{
    return sem_post(reinterpret_cast<sem_t*>(sem));
}

// CJThread schedule/include/inner/base.h:110-113.
extern "C" __attribute__((visibility("hidden"))) int32_t cj_cjthread_semaphore_destroy(uint64_t* sem)
{
    return sem_destroy(reinterpret_cast<sem_t*>(sem));
}
