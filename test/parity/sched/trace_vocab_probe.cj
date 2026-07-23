// Test-only candidate for trace_impl.h:27-103. Every layout offset below is
// obtained from a field address in the same live instance; alignment comes
// from the value-field offset in an actual one-byte-prefix wrapper.
package tracevocab.probe

import rt.sched.*

foreign {
    func TracePrintCandidateVocabulary(values: CPointer<UInt64>): Unit
    func TracePrintCandidateStrings(header: CPointer<UInt8>, exitString: CPointer<UInt8>,
        resched: CPointer<UInt8>, netBlock: CPointer<UInt8>, netUnblock: CPointer<UInt8>,
        unblock: CPointer<UInt8>, unknown: CPointer<UInt8>, runtime: CPointer<UInt8>): Unit
    func TracePrintCandidateLayouts(layout: CPointer<UInt64>): Unit
    func TraceExpected(index: Int32): CPointer<Unit>
    func TraceCppWriteRecords(header: CPointer<TraceBufHeader>, buffer: CPointer<TraceBuf>,
        hooks: CPointer<TraceHooks>): Unit
    func TraceCppCallbackStatus(): UInt64
    func TraceReadVaList(rawArgs: CPointer<Unit>, first: CPointer<UInt64>, second: CPointer<UInt64>): Unit
    func TraceCppCheckCandidate(header: CPointer<TraceBufHeader>, buffer: CPointer<TraceBuf>,
        hooks: CPointer<TraceHooks>): UInt64
    func TracePrintSentinel(cppWriteCjRead: UInt64, cjWriteCppRead: UInt64,
        callbacks: UInt64, arg0: UInt64, arg1: UInt64): Unit
}

@C
struct TraceHooksAlignProbe {
    var pad: UInt8
    var value: TraceHooks

    init(value: TraceHooks) {
        pad = 0u8
        this.value = value
    }
}

@C
struct TraceBufHeaderAlignProbe {
    var pad: UInt8
    var value: TraceBufHeader

    init(value: TraceBufHeader) {
        pad = 0u8
        this.value = value
    }
}

@C
struct TraceBufAlignProbe {
    var pad: UInt8
    var value: TraceBuf

    init(value: TraceBuf) {
        pad = 0u8
        this.value = value
    }
}

var cjDeregisterCalls: UInt64 = 0u64
var cjEventCalls: UInt64 = 0u64
var cjEventArg0: UInt64 = 0u64
var cjEventArg1: UInt64 = 0u64
var cjDumpBytes: VArray<UInt8, $4> = [9u8, 8u8, 7u8, 6u8]

@C
func CandidateDeregister(): Unit {
    cjDeregisterCalls++
}

@C
func CandidateStart(traceType: UInt16): Bool {
    return traceType == TRACE_TYPE_ALL
}

@C
func CandidateStop(): Bool {
    return true
}

@C
func CandidateEvent(event: TraceEvent, skip: Int32, mutator: CPointer<Unit>,
    argNum: Int32, rawArgs: CPointer<Unit>): Unit {
    if (event == TRACE_EV_CJTHREAD_UNBLOCK && skip == 5 &&
        mutator.toUIntNative() == unsafe { TraceExpected(5) }.toUIntNative() && argNum == 2) {
        var first: UInt64 = 0u64
        var second: UInt64 = 0u64
        unsafe { TraceReadVaList(rawArgs, CPointer<UInt64>(inout first), CPointer<UInt64>(inout second)) }
        cjEventArg0 = first
        cjEventArg1 = second
        cjEventCalls++
    }
}

@C
func CandidateDump(len: CPointer<Int32>): CPointer<UInt8> {
    unsafe { len.write(0, 4) }
    return CPointer<UInt8>(inout cjDumpBytes)
}

@C
func CandidateReader(): CPointer<Unit> {
    return unsafe { TraceExpected(4) }
}

func FieldOffset<T>(base: CPointer<T>, field: CPointer<Unit>): UInt64 where T <: CType {
    return UInt64(field.toUIntNative() - CPointer<Unit>(base).toUIntNative())
}

func CheckCppWrite(header: TraceBufHeader, buffer: TraceBuf, hooks: TraceHooks): UInt64 {
    var failures: UInt64 = 0u64
    if (header.dulink.prev.toUIntNative() != unsafe { TraceExpected(0) }.toUIntNative()) { failures |= 1u64 << 0 }
    if (header.dulink.next.toUIntNative() != unsafe { TraceExpected(1) }.toUIntNative()) { failures |= 1u64 << 1 }
    if (header.lastTicks != 0x0123456789abcdefu64) { failures |= 1u64 << 2 }
    if (header.pos != 0x10203040) { failures |= 1u64 << 3 }
    if (buffer.header.dulink.prev.toUIntNative() != unsafe { TraceExpected(1) }.toUIntNative()) { failures |= 1u64 << 4 }
    if (buffer.header.dulink.next.toUIntNative() != unsafe { TraceExpected(0) }.toUIntNative()) { failures |= 1u64 << 5 }
    if (buffer.header.lastTicks != 0xfedcba9876543210u64) { failures |= 1u64 << 6 }
    if (buffer.header.pos != 0x50607080) { failures |= 1u64 << 7 }
    if (buffer.arr[0] != 0x11u8) { failures |= 1u64 << 8 }
    if (buffer.arr[32752] != 0x22u8) { failures |= 1u64 << 9 }
    if (buffer.arr[65503] != 0x33u8) { failures |= 1u64 << 10 }

    unsafe { hooks.traceDeregister() }
    if (!unsafe { hooks.traceStart(TRACE_TYPE_RUNTIME) }) { failures |= 1u64 << 11 }
    if (!unsafe { hooks.traceStop() }) { failures |= 1u64 << 12 }
    unsafe { hooks.traceRecordEvent(TRACE_EV_CJTHREAD_RESCHED, 7, TraceExpected(5), 2, CPointer<Unit>()) }
    var len: Int32 = 0
    let dump = unsafe { hooks.traceDump(CPointer<Int32>(inout len)) }
    if (len != 3 || unsafe { dump.read(0) } != 1u8 || unsafe { dump.read(1) } != 2u8 ||
        unsafe { dump.read(2) } != 3u8) { failures |= 1u64 << 13 }
    if (unsafe { hooks.traceReaderGet() }.toUIntNative() != unsafe { TraceExpected(4) }.toUIntNative()) {
        failures |= 1u64 << 14
    }
    return failures
}

main(): Int64 {
    var values: VArray<UInt64, $45> = [
        UInt64(TRACE_TYPE_SCHEDULE), UInt64(TRACE_TYPE_RUNTIME), UInt64(TRACE_TYPE_ALL),
        UInt64(TRACE_EV_NONE), UInt64(TRACE_EV_BATCH), UInt64(TRACE_EV_FREQUENCY),
        UInt64(TRACE_EV_STACK), UInt64(TRACE_EV_STRING), UInt64(TRACE_EV_PROC_WAKE),
        UInt64(TRACE_EV_PROC_STOP), UInt64(TRACE_EV_CJTHREAD_CREATE), UInt64(TRACE_EV_CJTHREAD_START),
        UInt64(TRACE_EV_CJTHREAD_END), UInt64(TRACE_EV_CJTHREAD_RESCHED), UInt64(TRACE_EV_CJTHREAD_SLEEP),
        UInt64(TRACE_EV_CJTHREAD_BLOCK), UInt64(TRACE_EV_CJTHREAD_UNBLOCK),
        UInt64(TRACE_EV_CJTHREAD_BLOCK_SYNC), UInt64(TRACE_EV_CJTHREAD_BLOCK_NET),
        UInt64(TRACE_EV_CJTHREAD_SYSCALL), UInt64(TRACE_EV_CJTHREAD_SYSEXIT),
        UInt64(TRACE_EV_GC_START), UInt64(TRACE_EV_GC_DONE), UInt64(TRACE_EV_COUNT),
        UInt64(ERRNO_TRACE_ALREADY_START), UInt64(ERRNO_TRACE_SHUTDOWN_WRONG),
        UInt64(ERRNO_TRACE_BUF_FLUSH_WRONG), UInt64(ERRNO_TRACE_EVENT_WHEN_STOP),
        UInt64(ERRNO_TRACE_MALLOC_FAILED), UInt64(ERRNO_TRACE_READER_SPURIOUS_WAKEUP),
        UInt64(ERRNO_TRACE_MULTIPLE_READER), UInt64(ERRNO_TRACE_STOP_EXCEPTION),
        UInt64(ERRNO_TRACE_ALREADY_STOP), UInt64(ERRNO_TRACE_STRING_EVENT),
        UInt64(ERRNO_TRACE_STACK_EVENT), UInt64(TRACE_EVENT_MAXSIZE), UInt64(TRACE_STACK_EVENT_MAXSIZE),
        UInt64(TRACE_HEADER_LENGTH), UInt64(TRACE_PATH_LENGTH), UInt64(TRACE_EFFECTIVE_EVENT),
        UInt64(TRACE_EFFECTIVE_ARG_NUM), UInt64(TRACE_BUF_LENGTH), UInt64(TRACE_UINT64_SHIFTS),
        UInt64(TRACE_UINT64_SHIFT_THRESHOLD), UInt64(TRACE_STACK_ARG_NUM)
    ]
    unsafe { TracePrintCandidateVocabulary(CPointer<UInt64>(inout values)) }
    unsafe {
        TracePrintCandidateStrings(CPointer<UInt8>(inout TRACE_HEADER),
            CPointer<UInt8>(inout TRACE_EXIT_STRING), CPointer<UInt8>(inout TRACE_RESCHED_STRING),
            CPointer<UInt8>(inout TRACE_NET_BLOCK_STRING), CPointer<UInt8>(inout TRACE_NET_UNBLOCK_STRING),
            CPointer<UInt8>(inout TRACE_UNBLOCK_STRING), CPointer<UInt8>(inout TRACE_UNKNOWN_STRING),
            CPointer<UInt8>(inout TRACE_RUNTIME_STRING))
    }

    var hooks = TraceHooks(CandidateDeregister, CandidateStart, CandidateStop,
        CandidateEvent, CandidateDump, CandidateReader)
    var header = TraceBufHeader()
    var buffer = TraceBuf()
    var hooksWrapper = TraceHooksAlignProbe(hooks)
    var headerWrapper = TraceBufHeaderAlignProbe(header)
    var bufferWrapper = TraceBufAlignProbe(buffer)
    let hooksBase = CPointer<TraceHooks>(inout hooks)
    let headerBase = CPointer<TraceBufHeader>(inout header)
    let bufferBase = CPointer<TraceBuf>(inout buffer)
    var layouts: VArray<UInt64, $19> = [
        UInt64(sizeOf<TraceHooks>()),
        FieldOffset(CPointer<TraceHooksAlignProbe>(inout hooksWrapper), CPointer<Unit>(inout hooksWrapper.value)),
        FieldOffset(hooksBase, CPointer<Unit>(inout hooks.traceDeregister)),
        FieldOffset(hooksBase, CPointer<Unit>(inout hooks.traceStart)),
        FieldOffset(hooksBase, CPointer<Unit>(inout hooks.traceStop)),
        FieldOffset(hooksBase, CPointer<Unit>(inout hooks.traceRecordEvent)),
        FieldOffset(hooksBase, CPointer<Unit>(inout hooks.traceDump)),
        FieldOffset(hooksBase, CPointer<Unit>(inout hooks.traceReaderGet)),
        UInt64(sizeOf<TraceBufHeader>()),
        FieldOffset(CPointer<TraceBufHeaderAlignProbe>(inout headerWrapper), CPointer<Unit>(inout headerWrapper.value)),
        FieldOffset(headerBase, CPointer<Unit>(inout header.dulink)),
        FieldOffset(headerBase, CPointer<Unit>(inout header.lastTicks)),
        FieldOffset(headerBase, CPointer<Unit>(inout header.pos)),
        UInt64(sizeOf<TraceBuf>()),
        FieldOffset(CPointer<TraceBufAlignProbe>(inout bufferWrapper), CPointer<Unit>(inout bufferWrapper.value)),
        FieldOffset(bufferBase, CPointer<Unit>(inout buffer.header)),
        FieldOffset(bufferBase, CPointer<Unit>(inout buffer.arr)),
        UInt64(sizeOf<VArray<UInt8, $65504>>()),
        UInt64((64 << 10) - sizeOf<TraceBufHeader>())
    ]
    unsafe { TracePrintCandidateLayouts(CPointer<UInt64>(inout layouts)) }

    unsafe { TraceCppWriteRecords(headerBase, bufferBase, hooksBase) }
    let cppWriteCjRead = CheckCppWrite(header, buffer, hooks)
    let cppCallbacks = unsafe { TraceCppCallbackStatus() }

    header.dulink.prev = CPointer<Dulink>(unsafe { TraceExpected(2) })
    header.dulink.next = CPointer<Dulink>(unsafe { TraceExpected(3) })
    header.lastTicks = 0x8899aabbccddeeffu64
    header.pos = 0x11223344
    buffer.header.dulink.prev = CPointer<Dulink>(unsafe { TraceExpected(3) })
    buffer.header.dulink.next = CPointer<Dulink>(unsafe { TraceExpected(2) })
    buffer.header.lastTicks = 0x7766554433221100u64
    buffer.header.pos = 0x55667788
    buffer.arr[0] = 0xaau8
    buffer.arr[32752] = 0xbbu8
    buffer.arr[65503] = 0xccu8
    hooks = TraceHooks(CandidateDeregister, CandidateStart, CandidateStop,
        CandidateEvent, CandidateDump, CandidateReader)
    let cjWriteCppRead = unsafe { TraceCppCheckCandidate(headerBase, bufferBase, hooksBase) }
    var callbackFailures: UInt64 = cppCallbacks
    if (cjDeregisterCalls != 1u64) { callbackFailures |= 1u64 << 16 }
    if (cjEventCalls != 1u64) { callbackFailures |= 1u64 << 17 }
    unsafe { TracePrintSentinel(cppWriteCjRead, cjWriteCppRead, callbackFailures, cjEventArg0, cjEventArg1) }
    return if (cppWriteCjRead == 0u64 && cjWriteCppRead == 0u64 && callbackFailures == 0u64 &&
        cjEventArg0 == 0x1122334455667788u64 && cjEventArg1 == 0x8877665544332211u64) { 0 } else { 1 }
}
