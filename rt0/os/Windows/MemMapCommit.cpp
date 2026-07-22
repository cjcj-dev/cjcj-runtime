// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <windows.h>

#include "Base/Log.h"

// Heap/Allocator/MemMap.cpp:100-105. Keep the Win32 call, error level,
// GetLastError payload, and non-fatal return behavior in one no-allocation leaf.
extern "C" void CJRT_MemMapCommitMemory(void* address, size_t size)
{
    CHECK_E(UNLIKELY(!VirtualAlloc(address, size, MEM_COMMIT, PAGE_READWRITE)),
        "VirtualAlloc commit failed in GetPage, errno: %d", GetLastError());
}
