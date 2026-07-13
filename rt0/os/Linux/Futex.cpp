// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

#include <unistd.h>
#include "linux/futex.h"
#include "sys/syscall.h"

namespace MapleRuntime {
#ifndef SYS_futex
#define SYS_futex __NR_futex
#endif

// cangjie_runtime/runtime/src/Base/SysCall.cpp:25-31
// only support FUTEX_WAIT/FUTEX_WAKE
int Futex(const volatile int* uaddr, int op, int val)
{
    return syscall(SYS_futex, uaddr, op, val, nullptr, nullptr, 0);
}
} // namespace MapleRuntime
