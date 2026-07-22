// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

package rt.sched

// CJThread base/mid/include/mid.h:32 and timer/include/timer.h:20-100.
public const MID_TIMER: Int32 = 0x100B0000
public const ERROR_TIMER_ALLOC: Int32 = 0x100B0001
public const ERROR_TIMER_STATE: Int32 = 0x100B0002
public const ERROR_TIMER_PPTR: Int32 = 0x100B0003
public const ERROR_TIMER_STOP_FAILED: Int32 = 0x100B0004
public const ERROR_TIMER_NEW_PARA_INVALID: Int32 = 0x100B0005
public const ERROR_TIMER_PTR_INVALID: Int32 = 0x100B0006
public const ERROR_TIMER_HEAP_NOT_INIT: Int32 = 0x100B0007
public const ERROR_TIMER_IS_NOT_WAITING: Int32 = 0x100B0008
public const ERROR_TIMER_EXIT_FAILED: Int32 = 0x100B0009
public const ERROR_TIMER_MUTEX_INVALID: Int32 = 0x100B000A
public const ERROR_TIMER_HANDLE_INVALID: Int32 = 0x100B000B
public const ERROR_TIMER_FREE: Int32 = 0x100B000C

public type TimerHandle = CPointer<Unit>
public type TimerFunc = CPointer<Unit>
public const FORKS_NUM: UInt32 = 4u32

// timer_impl.h:26-37. The Linux, Darwin and Win64 real-header oracles select
// the same four-byte unsigned representation.
public type TimerStatus = UInt32
public const TIMER_IDLE: TimerStatus = 0u32
public const TIMER_WAITING: TimerStatus = 1u32
public const TIMER_RUNNING: TimerStatus = 2u32
public const TIMER_STOPPED: TimerStatus = 3u32
public const TIMER_MODIFYING: TimerStatus = 4u32
public const TIMER_MODIFIED_AHEAD: TimerStatus = 5u32
public const TIMER_MODIFIED_DELAYED: TimerStatus = 6u32
public const TIMER_REMOVING: TimerStatus = 7u32
public const TIMER_REMOVED: TimerStatus = 8u32
public const TIMER_MOVING: TimerStatus = 9u32

// timer_impl.h:42-51. std::atomic<TimerStatus> is retained as its exact inline
// four-byte value storage; callable atomic transitions remain with Timer logic.
@C
public struct TimerNode {
    public var pPtr: CPointer<Unit>
    public var deadline: UInt64
    public var newDeadline: UInt64
    public var period: UInt64
    public var `func`: TimerFunc
    public var args: CPointer<Unit>
    public var status: TimerStatus
    public var autoReleasing: Bool

    public init() {
        pPtr = CPointer<Unit>()
        deadline = 0u64
        newDeadline = 0u64
        period = 0u64
        `func` = CPointer<Unit>()
        args = CPointer<Unit>()
        status = TIMER_IDLE
        autoReleasing = false
    }
}

// timer_impl.h:72-94. These three records contain no lock or owner lifetime.
@C
public struct MoveItem {
    public var buf: CPointer<CPointer<Unit>>
    public var len: UInt64

    public init() {
        buf = CPointer<CPointer<Unit>>()
        len = 0u64
    }
}

@C
public struct TimerResetPara {
    public var ddl: UInt64
    public var period: UInt64
    public var `func`: TimerFunc
    public var args: CPointer<Unit>

    public init() {
        ddl = 0u64
        period = 0u64
        `func` = CPointer<Unit>()
        args = CPointer<Unit>()
    }
}

@C
public struct TimerStoppedPara {
    public var aheadcnt: UInt64
    public var delcnt: UInt64
    public var bufIndex: UInt64

    public init() {
        aheadcnt = 0u64
        delcnt = 0u64
        bufIndex = 0u64
    }
}

// TIMER-HEAP-PLATFORM-LOCK: timer_impl.h:56-67 embeds pthread_mutex_t and
// atomics whose Darwin/Win64 layouts require separate proven storage arms.
// TIMER-SCHEDULE-OWNER: timer.cpp includes schedule_impl.h, cjthread.h and
// NativeAllocator.h; TimerNew/Stop/Reset/Sleep/Release are dependency-ordered
// after complete Processor/Schedule owners and are not represented by stubs.
