// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <cstdint>

// Value-storage atomics used by Cangjie runtime structs that must retain the
// target C++ inline std::atomic layout. GCC/Clang __atomic builtins lower for
// x86, ARM and Win64 without owning storage or allocating.
extern "C" bool cj_atomic_flag_test_and_set(uint8_t* p)
{
    return __atomic_test_and_set(p, __ATOMIC_ACQUIRE);
}
extern "C" void cj_atomic_flag_clear(uint8_t* p) { __atomic_clear(p, __ATOMIC_RELEASE); }

extern "C" int32_t cj_atomic_i32_cas(int32_t* p, int32_t expected, int32_t desired)
{
    return __atomic_compare_exchange_n(p, &expected, desired, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST) ? 1 : 0;
}
extern "C" int32_t cj_atomic_i32_load(int32_t* p) { return __atomic_load_n(p, __ATOMIC_SEQ_CST); }
extern "C" void cj_atomic_i32_store(int32_t* p, int32_t v) { __atomic_store_n(p, v, __ATOMIC_SEQ_CST); }
extern "C" int32_t cj_atomic_i32_fetch_sub(int32_t* p, int32_t v)
{
    return __atomic_fetch_sub(p, v, __ATOMIC_SEQ_CST);
}

extern "C" int32_t cj_atomic_u8_cas(uint8_t* p, uint8_t* expected, uint8_t desired)
{
    return __atomic_compare_exchange_n(p, expected, desired, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE) ? 1 : 0;
}
extern "C" uint8_t cj_atomic_u8_load(uint8_t* p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
extern "C" void cj_atomic_u8_store(uint8_t* p, uint8_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }

extern "C" int32_t cj_atomic_u16_cas(uint16_t* p, uint16_t* expected, uint16_t desired)
{
    return __atomic_compare_exchange_n(p, expected, desired, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE) ? 1 : 0;
}
extern "C" uint16_t cj_atomic_u16_load(uint16_t* p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
extern "C" void cj_atomic_u16_store(uint16_t* p, uint16_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }

// Heap/Collector/LiveInfo.h:71-185. Unqualified std::atomic operations are
// sequentially consistent; the two explicitly qualified loads are acquire.
extern "C" uint16_t cj_atomic_u16_fetch_add_seq_cst(uint16_t* p, uint16_t v)
{
    return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST);
}
extern "C" uint64_t cj_atomic_u64_load_seq_cst(uint64_t* p) { return __atomic_load_n(p, __ATOMIC_SEQ_CST); }
extern "C" uint64_t cj_atomic_u64_load_acquire(uint64_t* p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
extern "C" uint64_t cj_atomic_u64_fetch_add_seq_cst(uint64_t* p, uint64_t v)
{
    return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST);
}
extern "C" uint64_t cj_atomic_u64_fetch_or_seq_cst(uint64_t* p, uint64_t v)
{
    return __atomic_fetch_or(p, v, __ATOMIC_SEQ_CST);
}

extern "C" int32_t cj_stateword_u16_cas(uint16_t* p, uint16_t expected, uint16_t desired)
{
#if defined(__x86_64__)
    return __atomic_compare_exchange_n(p, &expected, desired, true, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE) ? 1 : 0;
#else
    return __atomic_compare_exchange_n(p, &expected, desired, false, __ATOMIC_SEQ_CST, __ATOMIC_ACQUIRE) ? 1 : 0;
#endif
}
