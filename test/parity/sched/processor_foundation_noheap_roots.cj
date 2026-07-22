package processorfoundation.noheap

import rt.sched.*

foreign func ProcessorFoundationObserve(
    globalSchNum: Int32, queueCapacity: Int32, stealRatio: Int32,
    globalAddRatio: Int32, parrayNum: Int32, stealRounds: Int32,
    runningSearchingMultiple: Int32, keyTimer: Int32, stealSleep: Int32,
    schedCount: Int32, idle: UInt32, running: UInt32, exiting: UInt32,
    syscallState: UInt32, stateSize: UIntNative, stateAlign: UIntNative,
    freelistSize: UIntNative, freelistAlign: UIntNative,
    freelistCountOffset: UIntNative, observedSize: UIntNative,
    observedAlign: UIntNative, observedTimeOffset: UIntNative,
    infoSize: UIntNative, infoAlign: UIntNative, infoStateOffset: UIntNative,
    infoRunqOffset: UIntNative, infoSchedOffset: UIntNative,
    infoThreadOffset: UIntNative, midSchmon: Int32, argInvalid: Int32,
    initFailed: Int32): Int32

// processor.h:24-108 and schmon.h:20-28. Root every value and derive every
// field offset from the real Cangjie @C records.
@C
public func CJRT_ProcessorFoundationRun(): Int32 {
    var freelist = ProcessorFreelist()
    let freelistBase = unsafe { CPointer<UInt8>(inout freelist).toUIntNative() }
    let freelistCount = unsafe {
        CPointer<UInt8>(inout freelist.cjthreadNum).toUIntNative() - freelistBase
    }
    var observed = ProcessorObservedRecord()
    let observedBase = unsafe { CPointer<UInt8>(inout observed).toUIntNative() }
    let observedTime = unsafe {
        CPointer<UInt8>(inout observed.lastTime).toUIntNative() - observedBase
    }
    var info = ProcessorInfo()
    let infoBase = unsafe { CPointer<UInt8>(inout info).toUIntNative() }
    let infoState = unsafe { CPointer<UInt8>(inout info.state).toUIntNative() - infoBase }
    let infoRunq = unsafe { CPointer<UInt8>(inout info.runqCnt).toUIntNative() - infoBase }
    let infoSched = unsafe { CPointer<UInt8>(inout info.schedCnt).toUIntNative() - infoBase }
    let infoThread = unsafe { CPointer<UInt8>(inout info.threadId).toUIntNative() - infoBase }
    return unsafe {
        ProcessorFoundationObserve(GLOBAL_SCH_NUM, PROCESSOR_QUEUE_CAPACITY,
            PROCESSOR_STEAL_RATIO, GLOBAL_ADD_RATIO, PROCESSOR_PARRAY_NUM,
            PROCESSOR_STEAL_ROUNDS, RUNNING_PROCESSOR_SEARCHING_NUM_MULTIPLE,
            KEY_TIMER, PROCESSOR_STEAL_SLEEP_THRESHOLD,
            PROCESSOR_SCHED_COUNT_THRESHOLD, PROCESSOR_IDLE, PROCESSOR_RUNNING,
            PROCESSOR_EXITING, PROCESSOR_SYSCALL, sizeOf<ProcessorState>(),
            alignOf<ProcessorState>(), sizeOf<ProcessorFreelist>(),
            alignOf<ProcessorFreelist>(), freelistCount,
            sizeOf<ProcessorObservedRecord>(), alignOf<ProcessorObservedRecord>(),
            observedTime, sizeOf<ProcessorInfo>(), alignOf<ProcessorInfo>(),
            infoState, infoRunq, infoSched, infoThread, MID_SCHMON,
            ERRNO_SCHMON_ARG_INVALID, ERRNO_SCHMON_INIT_FAILED)
    }
}
