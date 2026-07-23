// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

package rt.sched

// CJThread schedule/include/schedule.h:439-474. The public trace selector and
// event vocabulary has no target-dependent branch.
public const TRACE_TYPE_SCHEDULE: UInt16 = 0x0100u16
public const TRACE_TYPE_RUNTIME: UInt16 = 0x0200u16
public const TRACE_TYPE_ALL: UInt16 = 0xff00u16

public type TraceEvent = UInt32
public const TRACE_EV_NONE: TraceEvent = 0x0000u32
public const TRACE_EV_BATCH: TraceEvent = 0x0301u32
public const TRACE_EV_FREQUENCY: TraceEvent = 0x0302u32
public const TRACE_EV_STACK: TraceEvent = 0x0303u32
public const TRACE_EV_STRING: TraceEvent = 0x0304u32
public const TRACE_EV_PROC_WAKE: TraceEvent = 0x0105u32
public const TRACE_EV_PROC_STOP: TraceEvent = 0x0106u32
public const TRACE_EV_CJTHREAD_CREATE: TraceEvent = 0x0107u32
public const TRACE_EV_CJTHREAD_START: TraceEvent = 0x0108u32
public const TRACE_EV_CJTHREAD_END: TraceEvent = 0x0109u32
public const TRACE_EV_CJTHREAD_RESCHED: TraceEvent = 0x010au32
public const TRACE_EV_CJTHREAD_SLEEP: TraceEvent = 0x010bu32
public const TRACE_EV_CJTHREAD_BLOCK: TraceEvent = 0x010cu32
public const TRACE_EV_CJTHREAD_UNBLOCK: TraceEvent = 0x010du32
public const TRACE_EV_CJTHREAD_BLOCK_SYNC: TraceEvent = 0x010eu32
public const TRACE_EV_CJTHREAD_BLOCK_NET: TraceEvent = 0x010fu32
public const TRACE_EV_CJTHREAD_SYSCALL: TraceEvent = 0x0110u32
public const TRACE_EV_CJTHREAD_SYSEXIT: TraceEvent = 0x0111u32
public const TRACE_EV_GC_START: TraceEvent = 0x0212u32
public const TRACE_EV_GC_DONE: TraceEvent = 0x0213u32
public const TRACE_EV_COUNT: TraceEvent = 0x0014u32

// CJThread trace/include/inner/trace.h:20-73 and base/mid/include/mid.h:42.
// schedule_rename.h:560 expands MID_MAKE(21) to 0x10150000.
public const MID_TRACE: Int32 = 0x10150000
public const ERRNO_TRACE_ALREADY_START: Int32 = 0x10150000
public const ERRNO_TRACE_SHUTDOWN_WRONG: Int32 = 0x10150001
public const ERRNO_TRACE_BUF_FLUSH_WRONG: Int32 = 0x10150002
public const ERRNO_TRACE_EVENT_WHEN_STOP: Int32 = 0x10150003
public const ERRNO_TRACE_MALLOC_FAILED: Int32 = 0x10150004
public const ERRNO_TRACE_READER_SPURIOUS_WAKEUP: Int32 = 0x10150005
public const ERRNO_TRACE_MULTIPLE_READER: Int32 = 0x10150006
public const ERRNO_TRACE_STOP_EXCEPTION: Int32 = 0x10150007
public const ERRNO_TRACE_ALREADY_STOP: Int32 = 0x10150008
public const ERRNO_TRACE_STRING_EVENT: Int32 = 0x10150009
public const ERRNO_TRACE_STACK_EVENT: Int32 = 0x1015000a

// CJThread schedule/include/inner/trace_impl.h:27-46. The C++ literals denote
// process-lifetime NUL-terminated byte arrays. Top-level VArray storage is the
// existing freestanding AS0 representation used by other runtime packages;
// no managed String, Array, concatenation, or growing container is involved.
public const TRACE_EVENT_MAXSIZE: Int32 = 90
public const TRACE_STACK_EVENT_MAXSIZE: Int32 = 251
public var TRACE_HEADER: VArray<UInt8, $14> = [
    67u8, 97u8, 110u8, 103u8, 106u8, 105u8, 101u8, 32u8,
    116u8, 114u8, 97u8, 99u8, 101u8, 0u8
]
public const TRACE_HEADER_LENGTH: Int32 = 32
public const TRACE_PATH_LENGTH: Int32 = 256
public const TRACE_EFFECTIVE_EVENT: Int32 = 0x00ff
public const TRACE_EFFECTIVE_ARG_NUM: Int32 = 0x00ff
// Cangjie const-generic lengths require a literal. The parity gate derives the
// value again from (64 << 10) - sizeOf<TraceBufHeader>() and rejects drift.
public const TRACE_BUF_LENGTH: UIntNative = 65504
public const TRACE_UINT64_SHIFTS: Int32 = 7
public const TRACE_UINT64_SHIFT_THRESHOLD: Int32 = 0x80
public const TRACE_STACK_ARG_NUM: Int32 = 4
public var TRACE_EXIT_STRING: VArray<UInt8, $16> = [
    67u8, 74u8, 95u8, 67u8, 74u8, 84u8, 104u8, 114u8,
    101u8, 97u8, 100u8, 69u8, 120u8, 105u8, 116u8, 0u8
]
public var TRACE_RESCHED_STRING: VArray<UInt8, $19> = [
    67u8, 74u8, 95u8, 67u8, 74u8, 84u8, 104u8, 114u8,
    101u8, 97u8, 100u8, 82u8, 101u8, 115u8, 99u8, 104u8,
    101u8, 100u8, 0u8
]
public var TRACE_NET_BLOCK_STRING: VArray<UInt8, $16> = [
    67u8, 74u8, 95u8, 83u8, 99u8, 104u8, 100u8, 112u8,
    111u8, 108u8, 108u8, 87u8, 97u8, 105u8, 116u8, 0u8
]
public var TRACE_NET_UNBLOCK_STRING: VArray<UInt8, $17> = [
    67u8, 74u8, 95u8, 83u8, 99u8, 104u8, 100u8, 112u8,
    111u8, 108u8, 108u8, 82u8, 101u8, 97u8, 100u8, 121u8, 0u8
]
public var TRACE_UNBLOCK_STRING: VArray<UInt8, $17> = [
    67u8, 74u8, 95u8, 67u8, 74u8, 84u8, 104u8, 114u8,
    101u8, 97u8, 100u8, 82u8, 101u8, 97u8, 100u8, 121u8, 0u8
]
public var TRACE_UNKNOWN_STRING: VArray<UInt8, $2> = [63u8, 0u8]
public var TRACE_RUNTIME_STRING: VArray<UInt8, $22> = [
    108u8, 105u8, 98u8, 99u8, 97u8, 110u8, 103u8, 106u8,
    105u8, 101u8, 45u8, 114u8, 117u8, 110u8, 116u8, 105u8,
    109u8, 101u8, 46u8, 115u8, 111u8, 0u8
]

// CJThread schedule/include/inner/trace_impl.h:54-83. CFunc is the language's
// native C function-pointer carrier and is non-capturing.
public type TraceRegisterFunc = CFunc<() -> Unit>
public type TraceDeregisterFunc = CFunc<() -> Unit>
public type TraceStartFunc = CFunc<(UInt16) -> Bool>
public type TraceStopFunc = CFunc<() -> Bool>
public type TraceDumpFunc = CFunc<(CPointer<Int32>) -> CPointer<UInt8>>
// CJThread is only forward-declared at this boundary; match the existing
// schedule.h opaque-handle representation instead of importing its owner.
public type TraceReaderGetFunc = CFunc<() -> CPointer<Unit>>

// Linux x86_64 SysV va_list is an array parameter adjusted to a native pointer.
// The executable parity gate constructs it in C++ and calls through this exact
// function pointer. AAPCS64 uses a 32-byte aggregate; Win64 and Apple use their
// own pointer forms. Those targets intentionally have no TraceEventFunc or
// TraceHooks declaration until their ABI is proved by a target-native probe.
@When[os == "Linux" && arch == "x86_64"]
public type TraceEventFunc = CFunc<(TraceEvent, Int32, CPointer<Unit>, Int32, CPointer<Unit>) -> Unit>

@When[os == "Linux" && arch == "x86_64"]
@C
public struct TraceHooks {
    public var traceDeregister: TraceDeregisterFunc
    public var traceStart: TraceStartFunc
    public var traceStop: TraceStopFunc
    public var traceRecordEvent: TraceEventFunc
    public var traceDump: TraceDumpFunc
    public var traceReaderGet: TraceReaderGetFunc

    public init(traceDeregister: TraceDeregisterFunc, traceStart: TraceStartFunc,
        traceStop: TraceStopFunc, traceRecordEvent: TraceEventFunc,
        traceDump: TraceDumpFunc, traceReaderGet: TraceReaderGetFunc) {
        this.traceDeregister = traceDeregister
        this.traceStart = traceStart
        this.traceStop = traceStop
        this.traceRecordEvent = traceRecordEvent
        this.traceDump = traceDump
        this.traceReaderGet = traceReaderGet
    }
}

// CJThread schedule/include/inner/trace_impl.h:93-103. These records contain no
// Trace owner lock, atomic, or DlHandle storage.
@C
public struct TraceBufHeader {
    public var dulink: Dulink
    public var lastTicks: UInt64
    public var pos: Int32

    public init() {
        dulink = Dulink()
        lastTicks = 0u64
        pos = 0
    }
}

@C
public struct TraceBuf {
    public var header: TraceBufHeader
    public var arr: VArray<UInt8, $65504>

    public init() {
        header = TraceBufHeader()
        arr = VArray<UInt8, $65504>(repeat: 0u8)
    }
}

// TRACE-OWNER-EXCLUDED: trace_impl.h:105 onward owns pthread_mutex_t,
// std::atomic fields, and the MRT_WINDOWS HMODULE/non-Windows void* DlHandle.
// That owner and all of its target branches remain outside this vocabulary lane.
