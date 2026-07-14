// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

#include <cstdint>

// Layer0 atomic primitives for runtime types that embed an inline atomic int by value
// (Cangjie has no value-type atomic). C++ RwLock uses acquire/release + a default-order
// fetch_sub; SeqCst is the strongest-correct mapping.
extern "C" int32_t cj_atomic_i32_cas(int32_t* p, int32_t expected, int32_t desired)
{
    return __atomic_compare_exchange_n(p, &expected, desired, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST) ? 1 : 0;
}
extern "C" int32_t cj_atomic_i32_load(int32_t* p) { return __atomic_load_n(p, __ATOMIC_SEQ_CST); }
extern "C" void cj_atomic_i32_store(int32_t* p, int32_t v) { __atomic_store_n(p, v, __ATOMIC_SEQ_CST); }
extern "C" int32_t cj_atomic_i32_fetch_sub(int32_t* p, int32_t v) { return __atomic_fetch_sub(p, v, __ATOMIC_SEQ_CST); }

// Heap/Allocator/RegionInfo.h:35-62: inline BitField<uint8_t/uint16_t>.
// Loads are acquire; CAS is acq_rel on success and acquire on failure.
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

// Common/StateWord.h:66-75. Preserve the source-inline weak x86 CAS and the
// strong sequentially-consistent non-x86 CAS as one StateWord-specific leaf.
extern "C" int32_t cj_stateword_u16_cas(uint16_t* p, uint16_t expected, uint16_t desired)
{
#if defined(__x86_64__)
    return __atomic_compare_exchange_n(p, &expected, desired, true, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE) ? 1 : 0;
#else
    return __atomic_compare_exchange_n(p, &expected, desired, false, __ATOMIC_SEQ_CST, __ATOMIC_ACQUIRE) ? 1 : 0;
#endif
}
