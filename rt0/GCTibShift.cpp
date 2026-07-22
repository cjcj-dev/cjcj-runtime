// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <stdint.h>
#include <stddef.h>

// ObjectModel/MClass.h:247-250,320-325. The callers establish that each
// dynamic count is in range; retain the original C++ raw-shift semantics.
extern "C" uintptr_t CJRT_GCTibShiftUIntNative(uintptr_t value, uintptr_t count)
{
    return value >> count;
}

extern "C" uint8_t CJRT_GCTibShiftUInt8(uint8_t value, uintptr_t count)
{
    return static_cast<uint8_t>(value >> count);
}
