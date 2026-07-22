// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

package rt.sched

// schedule.h:358-363 and cjthread.h:30-34.
public const CJTHREAD_KEYS_MAX: UInt32 = 9u32
public const CJTHREAD_ARG_ALIGN: UIntNative = 16
public const CJTHREAD_INIT_ID: UInt64 = UInt64.Max
public const CJTHREAD_SANITIZER_CONTEXT_OFFSET: UIntNative = 16
public const CJTHREAD_NAME_SIZE: UInt32 = 32u32
public const CJTHREAD_MAX_STACK_SIZE: UIntNative = 1073741824

// cjthread.h:41-48. uintptr_t arithmetic is retained without dereferencing the
// supplied address. As in the macros, align must be a non-zero power of two.
@NoHeapAlloc
public func StackAddrAlignUp(addr: UIntNative, align: UIntNative): UIntNative {
    return (addr + align - 1) & ~(align - 1)
}

@NoHeapAlloc
public func StackAddrAlignDown(addr: UIntNative, align: UIntNative): UIntNative {
    return addr & ~(align - 1)
}

// cjthread.h:67-91. size_t and pointer fields follow the target native width.
// The record has no operating-system preprocessor arm; sanitizer support only
// changes the later initializer's arithmetic, not this layout.
@C
public struct CJThreadStack {
    public var protectAddr: CPointer<UInt8>
    public var totalSize: UIntNative
    public var stackTopAddr: CPointer<UInt8>
    public var stackGuard: CPointer<UInt8>
    public var stackBaseAddr: CPointer<UInt8>
    public var stackSize: UIntNative
    public var cjthreadStackBaseAddr: CPointer<UInt8>
    public var stackGrowCnt: UInt32

    public init() {
        protectAddr = CPointer<UInt8>()
        totalSize = 0
        stackTopAddr = CPointer<UInt8>()
        stackGuard = CPointer<UInt8>()
        stackBaseAddr = CPointer<UInt8>()
        stackSize = 0
        cjthreadStackBaseAddr = CPointer<UInt8>()
        stackGrowCnt = 0u32
    }
}

@C
public struct StackInfo {
    public var stackLimit: UInt64
    public var lastLeaveFrame: UInt64

    public init() {
        stackLimit = 0u64
        lastLeaveFrame = 0u64
    }
}

// cjthread.h:96-100. The real-header oracle fixes the non-negative enum to a
// four-byte unsigned representation on the supported toolchains.
public type CJThreadBuf = UInt32
public const LOCAL_BUF: CJThreadBuf = 0u32
public const GLOBAL_BUF: CJThreadBuf = 1u32
public const NO_BUF: CJThreadBuf = 2u32

// cjthread.h:173-185. These are the complete allocation input records; no
// stack allocation, Schedule owner, or driver lifetime is introduced here.
@C
public struct ArgAttr {
    public var argStart: CPointer<Unit>
    public var argSize: UIntNative

    public init() {
        argStart = CPointer<Unit>()
        argSize = 0
    }
}

@C
public struct StackAttr {
    public var stackSizeAlign: UIntNative
    public var stackGrow: Bool

    public init() {
        stackSizeAlign = 0
        stackGrow = false
    }
}

// CJTHREAD-STACK-ALLOC-LIFETIME: cjthread.cpp:51-118,249-451 owns mmap /
// NativeAllocator release and the enclosing Schedule/CJThread lifetime. It is
// dependency-ordered after those owners and is intentionally not stubbed.
// CJTHREAD-STACK-SANITIZER: cjthread.cpp:207-210 conditionally subtracts the
// sanitizer context from cjthreadStackBaseAddr; that branch remains attached
// to the deferred full initializer rather than being silently omitted here.
