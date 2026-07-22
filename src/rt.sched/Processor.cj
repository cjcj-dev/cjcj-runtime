// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.sched

// CJThread schedule/include/inner/processor.h:24-51. Each macro expands from
// an ordinary C++ int expression and has no target-preprocessor branch.
public const GLOBAL_SCH_NUM: Int32 = 32
public const PROCESSOR_QUEUE_CAPACITY: Int32 = 128
public const PROCESSOR_STEAL_RATIO: Int32 = 2
public const GLOBAL_ADD_RATIO: Int32 = 4
public const PROCESSOR_PARRAY_NUM: Int32 = 4
public const PROCESSOR_STEAL_ROUNDS: Int32 = 2
public const RUNNING_PROCESSOR_SEARCHING_NUM_MULTIPLE: Int32 = 2
public const KEY_TIMER: Int32 = 0
public const PROCESSOR_STEAL_SLEEP_THRESHOLD: Int32 = 2
public const PROCESSOR_SCHED_COUNT_THRESHOLD: Int32 = 100

// processor.h:53-61. The real-header GCC oracle selects an unsigned 4-byte
// underlying representation for this non-negative unscoped enum.
public type ProcessorState = UInt32
public const PROCESSOR_IDLE: ProcessorState = 0u32
public const PROCESSOR_RUNNING: ProcessorState = 1u32
public const PROCESSOR_EXITING: ProcessorState = 2u32
public const PROCESSOR_SYSCALL: ProcessorState = 3u32

// processor.h:63-69. This is the complete free-list record, not its mutating
// operations from processor.cpp:1025-1116.
@C
public struct ProcessorFreelist {
    public var freeList: Dulink
    public var cjthreadNum: UInt32

    public init() {
        freeList = Dulink()
        cjthreadNum = 0u32
    }
}

// processor.h:71-78. unsigned long follows the target C data model: native
// width on Unix-family targets and 32 bits on Win64.
@When[os == "Linux" || os == "macOS" || os == "iOS" || env == "ohos"]
@C
public struct ProcessorObservedRecord {
    public var lastSchedCnt: UIntNative
    public var lastTime: UInt64

    public init() {
        lastSchedCnt = 0
        lastTime = 0u64
    }
}

@When[os == "Windows"]
@C
public struct ProcessorObservedRecord {
    public var lastSchedCnt: UInt32
    public var lastTime: UInt64

    public init() {
        lastSchedCnt = 0u32
        lastTime = 0u64
    }
}

// processor.h:99-108. The same unsigned-long target split applies to schedCnt
// and threadId. No ProcessorGetInfoAll behavior is claimed by this descriptor.
@When[os == "Linux" || os == "macOS" || os == "iOS" || env == "ohos"]
@C
public struct ProcessorInfo {
    public var processorId: UInt32
    public var state: Int32
    public var runqCnt: Int32
    public var schedCnt: UIntNative
    public var threadId: UIntNative

    public init() {
        processorId = 0u32
        state = 0
        runqCnt = 0
        schedCnt = 0
        threadId = 0
    }
}

@When[os == "Windows"]
@C
public struct ProcessorInfo {
    public var processorId: UInt32
    public var state: Int32
    public var runqCnt: Int32
    public var schedCnt: UInt32
    public var threadId: UInt32

    public init() {
        processorId = 0u32
        state = 0
        runqCnt = 0
        schedCnt = 0u32
        threadId = 0u32
    }
}

// Full Processor (processor.h:80-97) is intentionally dependency-ordered
// after Queue, CJThread, TraceBuf, and their atomic ownership surfaces.
