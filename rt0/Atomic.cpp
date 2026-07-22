// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <stdint.h>
#include <stddef.h>

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

// ObjectModel/Field.h and RefField.h keep the atomic storage inline.  These
// bit-preserving entry points let the Cangjie value wrappers retain that layout
// while forwarding the caller's std::memory_order value unchanged.
extern "C" uint64_t cj_atomic_field_load(const void* p, size_t size, int32_t order)
{
    switch (size) {
        case 1: return __atomic_load_n(static_cast<const uint8_t*>(p), order);
        case 2: return __atomic_load_n(static_cast<const uint16_t*>(p), order);
        case 4: return __atomic_load_n(static_cast<const uint32_t*>(p), order);
        case 8: return __atomic_load_n(static_cast<const uint64_t*>(p), order);
        default: __builtin_trap();
    }
}

extern "C" void cj_atomic_field_store(void* p, const void* value, size_t size, int32_t order)
{
    switch (size) {
        case 1: __atomic_store_n(static_cast<uint8_t*>(p), *static_cast<const uint8_t*>(value), order); return;
        case 2: __atomic_store_n(static_cast<uint16_t*>(p), *static_cast<const uint16_t*>(value), order); return;
        case 4: __atomic_store_n(static_cast<uint32_t*>(p), *static_cast<const uint32_t*>(value), order); return;
        case 8: __atomic_store_n(static_cast<uint64_t*>(p), *static_cast<const uint64_t*>(value), order); return;
        default: __builtin_trap();
    }
}

extern "C" int32_t cj_atomic_field_compare_exchange(void* p, void* expected, const void* desired, size_t size,
                                                       int32_t success, int32_t failure)
{
    switch (size) {
        case 1: return __atomic_compare_exchange_n(static_cast<uint8_t*>(p), static_cast<uint8_t*>(expected),
            *static_cast<const uint8_t*>(desired), false, success, failure);
        case 2: return __atomic_compare_exchange_n(static_cast<uint16_t*>(p), static_cast<uint16_t*>(expected),
            *static_cast<const uint16_t*>(desired), false, success, failure);
        case 4: return __atomic_compare_exchange_n(static_cast<uint32_t*>(p), static_cast<uint32_t*>(expected),
            *static_cast<const uint32_t*>(desired), false, success, failure);
        case 8: return __atomic_compare_exchange_n(static_cast<uint64_t*>(p), static_cast<uint64_t*>(expected),
            *static_cast<const uint64_t*>(desired), false, success, failure);
        default: __builtin_trap();
    }
}

extern "C" uint64_t cj_atomic_field_exchange(void* p, const void* desired, size_t size, int32_t order)
{
    switch (size) {
        case 1: return __atomic_exchange_n(static_cast<uint8_t*>(p), *static_cast<const uint8_t*>(desired), order);
        case 2: return __atomic_exchange_n(static_cast<uint16_t*>(p), *static_cast<const uint16_t*>(desired), order);
        case 4: return __atomic_exchange_n(static_cast<uint32_t*>(p), *static_cast<const uint32_t*>(desired), order);
        case 8: return __atomic_exchange_n(static_cast<uint64_t*>(p), *static_cast<const uint64_t*>(desired), order);
        default: __builtin_trap();
    }
}

#define CJ_ATOMIC_FIELD_FETCH(NAME, BUILTIN) \
extern "C" uint64_t NAME(void* p, const void* operand, size_t size, int32_t order) \
{ \
    switch (size) { \
        case 1: return BUILTIN(static_cast<uint8_t*>(p), *static_cast<const uint8_t*>(operand), order); \
        case 2: return BUILTIN(static_cast<uint16_t*>(p), *static_cast<const uint16_t*>(operand), order); \
        case 4: return BUILTIN(static_cast<uint32_t*>(p), *static_cast<const uint32_t*>(operand), order); \
        case 8: return BUILTIN(static_cast<uint64_t*>(p), *static_cast<const uint64_t*>(operand), order); \
        default: __builtin_trap(); \
    } \
}

CJ_ATOMIC_FIELD_FETCH(cj_atomic_field_fetch_add, __atomic_fetch_add)
CJ_ATOMIC_FIELD_FETCH(cj_atomic_field_fetch_sub, __atomic_fetch_sub)
CJ_ATOMIC_FIELD_FETCH(cj_atomic_field_fetch_and, __atomic_fetch_and)
CJ_ATOMIC_FIELD_FETCH(cj_atomic_field_fetch_or, __atomic_fetch_or)
CJ_ATOMIC_FIELD_FETCH(cj_atomic_field_fetch_xor, __atomic_fetch_xor)
#undef CJ_ATOMIC_FIELD_FETCH

extern "C" int32_t cj_stateword_u16_cas(uint16_t* p, uint16_t expected, uint16_t desired)
{
#if defined(__x86_64__)
    return __atomic_compare_exchange_n(p, &expected, desired, true, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE) ? 1 : 0;
#else
    return __atomic_compare_exchange_n(p, &expected, desired, false, __ATOMIC_SEQ_CST, __ATOMIC_ACQUIRE) ? 1 : 0;
#endif
}
