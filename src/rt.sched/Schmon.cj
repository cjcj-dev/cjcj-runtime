// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.sched

// CJThread base/mid/include/mid.h:31 and schedule_rename.h:560 expand
// MID_SCHMON to ((0x1000 + 10) << 16). schmon.h:20-28 then reserves the two
// exact module errors below. All expressions have signed 32-bit C++ type.
public const MID_SCHMON: Int32 = 0x100A0000
public const ERRNO_SCHMON_ARG_INVALID: Int32 = 0x100A0000
public const ERRNO_SCHMON_INIT_FAILED: Int32 = 0x100A0001

// SchmonStart and SchmonPreemptRunning remain dependency-ordered after the
// complete Processor and Schedule owners; no callable stub is introduced.
