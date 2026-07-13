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
