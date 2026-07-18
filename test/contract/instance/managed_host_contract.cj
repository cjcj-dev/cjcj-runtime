package rt.instance.contract

import std.sync.*

@C
struct InstanceParam {
    let thStackSize: UIntNative
    let coStackSize: UIntNative
    let processorNum: UInt32

    init(thStackSize: UIntNative, coStackSize: UIntNative, processorNum: UInt32) {
        this.thStackSize = thStackSize
        this.coStackSize = coStackSize
        this.processorNum = processorNum
    }
}

foreign func CJRT_ContractMode(): Int32
foreign func CJRT_ContractCycles(): Int32
foreign func CJRT_ContractNew(mode: Int32, param: CPointer<InstanceParam>): CPointer<Unit>
foreign func CJRT_ContractRun(mode: Int32, instance: CPointer<Unit>, callback: CPointer<Unit>,
    argument: CPointer<Unit>): CPointer<Unit>
foreign func CJRT_ContractStop(mode: Int32, instance: CPointer<Unit>): Int32
foreign func CJRT_ContractGetRetMatches(handle: CPointer<Unit>, expected: CPointer<Unit>): Int32
foreign func CJRT_ContractReleaseAndReject(handle: CPointer<Unit>): Int32
foreign func CJRT_ContractToken(cycle: Int32): CPointer<Unit>
foreign func CJRT_ContractCurrentSchedule(): UIntNative
foreign func CJRT_ContractCurrentCJThread(): UIntNative
foreign func CJRT_ContractCurrentCJThreadState(): Int32
foreign func CJRT_ContractCurrentOSThread(): UInt64
foreign func CJRT_ContractDriverCount(): Int32
foreign func CJRT_ContractResidentBytes(): UInt64
foreign func CJRT_ContractVerifyRuntimeImage(callback: CPointer<Unit>): Int32
foreign func CJRT_ContractStage(stage: Int32, cycle: Int32, schedule: UIntNative,
    cjthread: UIntNative, state: Int32, osThread: UInt64): Unit
foreign func CJRT_ContractPass(mode: Int32, cycles: Int32, rssBefore: UInt64, rssAfter: UInt64): Unit

let STAGE_WAITER_READY: Int32 = 1
let STAGE_INSTANCE_CREATED: Int32 = 2
let STAGE_TASK_SUBMITTED: Int32 = 3
let STAGE_WAITER_PENDING: Int32 = 4
let STAGE_CALLBACK_ENTERED: Int32 = 5
let STAGE_STATE_UPDATED: Int32 = 6
let STAGE_NOTIFY_ENTERED: Int32 = 7
let STAGE_NOTIFY_RETURNED: Int32 = 8
let STAGE_WAITER_RESUMED: Int32 = 9
let STAGE_RETURN_MATCHED: Int32 = 10
let STAGE_HANDLE_RELEASED: Int32 = 11
let STAGE_INSTANCE_STOPPED: Int32 = 12
let STAGE_DRIVER_LIVE: Int32 = 13

class ManagedWakeState {
    let mtx = Mutex()
    let cv: Condition
    var ready = false
    var callbackEntered = false
    var stateUpdated = false
    var notifyIssued = false
    var callbackSchedule: UIntNative = 0
    var callbackCJThread: UIntNative = 0
    var callbackState: Int32 = -1
    var callbackOSThread: UInt64 = 0

    init() {
        synchronized(mtx) {
            cv = mtx.condition()
        }
    }

    func reset(): Unit {
        ready = false
        callbackEntered = false
        stateUpdated = false
        notifyIssued = false
        callbackSchedule = 0
        callbackCJThread = 0
        callbackState = -1
        callbackOSThread = 0
    }
}

let wakeState = ManagedWakeState()
var activeCycle: Int32 = -1

@C
func ManagedWakeCallback(argument: CPointer<Unit>): CPointer<Unit> {
    let schedule = unsafe { CJRT_ContractCurrentSchedule() }
    let cjthread = unsafe { CJRT_ContractCurrentCJThread() }
    let state = unsafe { CJRT_ContractCurrentCJThreadState() }
    let osThread = unsafe { CJRT_ContractCurrentOSThread() }
    synchronized(wakeState.mtx) {
        wakeState.callbackEntered = true
        wakeState.callbackSchedule = schedule
        wakeState.callbackCJThread = cjthread
        wakeState.callbackState = state
        wakeState.callbackOSThread = osThread
        unsafe {
            CJRT_ContractStage(STAGE_CALLBACK_ENTERED, activeCycle, schedule, cjthread, state, osThread)
        }
        wakeState.stateUpdated = true
        wakeState.ready = true
        unsafe {
            CJRT_ContractStage(STAGE_STATE_UPDATED, activeCycle, schedule, cjthread, state, osThread)
        }
        wakeState.notifyIssued = true
        unsafe {
            CJRT_ContractStage(STAGE_NOTIFY_ENTERED, activeCycle, schedule, cjthread, state, osThread)
        }
        wakeState.cv.notifyAll()
        unsafe {
            CJRT_ContractStage(STAGE_NOTIFY_RETURNED, activeCycle, schedule, cjthread, state, osThread)
        }
    }
    return argument
}

func fail(stage: String, cycle: Int32): Int64 {
    println("MANAGED_CONTRACT FAIL stage=${stage} cycle=${cycle}")
    return 1
}

main(): Int64 {
    let mode = unsafe { CJRT_ContractMode() }
    let cycles = unsafe { CJRT_ContractCycles() }
    if (mode < 0 || cycles <= 0) {
        return fail("configuration", -1)
    }
    if (unsafe { CJRT_ContractVerifyRuntimeImage(CPointer<Unit>(ManagedWakeCallback)) } != 0) {
        return fail("runtime_image", -1)
    }

    let rssBefore = unsafe { CJRT_ContractResidentBytes() }
    if (rssBefore == 0) {
        return fail("rss_before", -1)
    }
    var stableDriverCount: Int32 = -1
    var cycle: Int32 = 0
    while (cycle < cycles) {
        activeCycle = cycle
        let waiterSchedule = unsafe { CJRT_ContractCurrentSchedule() }
        let waiterCJThread = unsafe { CJRT_ContractCurrentCJThread() }
        let waiterState = unsafe { CJRT_ContractCurrentCJThreadState() }
        let waiterOSThread = unsafe { CJRT_ContractCurrentOSThread() }
        unsafe {
            CJRT_ContractStage(STAGE_WAITER_READY, cycle, waiterSchedule, waiterCJThread,
                waiterState, waiterOSThread)
        }

        var instance = CPointer<Unit>()
        var task = CPointer<Unit>()
        var driverLive = false
        let argument = unsafe { CJRT_ContractToken(cycle) }
        var callbackSchedule: UIntNative = 0
        var callbackCJThread: UIntNative = 0
        var callbackState: Int32 = -1
        var callbackOSThread: UInt64 = 0
        synchronized(wakeState.mtx) {
            wakeState.reset()
            var param = InstanceParam(1024, 4 * 1024, 1u32)
            instance = unsafe { CJRT_ContractNew(mode, CPointer<InstanceParam>(inout param)) }
            if (!instance.isNull()) {
                unsafe {
                    CJRT_ContractStage(STAGE_INSTANCE_CREATED, cycle, waiterSchedule, waiterCJThread,
                        waiterState, waiterOSThread)
                }
                let driverCount = unsafe { CJRT_ContractDriverCount() }
                if (driverCount == 1) {
                    driverLive = true
                    unsafe {
                        CJRT_ContractStage(STAGE_DRIVER_LIVE, cycle, waiterSchedule, waiterCJThread,
                            waiterState, waiterOSThread)
                        task = CJRT_ContractRun(mode, instance, CPointer<Unit>(ManagedWakeCallback), argument)
                    }
                }
            }
            if (!task.isNull()) {
                unsafe {
                    CJRT_ContractStage(STAGE_TASK_SUBMITTED, cycle, waiterSchedule, waiterCJThread,
                        waiterState, waiterOSThread)
                    CJRT_ContractStage(STAGE_WAITER_PENDING, cycle, waiterSchedule, waiterCJThread,
                        waiterState, waiterOSThread)
                }
                while (!wakeState.ready) {
                    wakeState.cv.wait()
                }
                callbackSchedule = wakeState.callbackSchedule
                callbackCJThread = wakeState.callbackCJThread
                callbackState = wakeState.callbackState
                callbackOSThread = wakeState.callbackOSThread
            }
        }

        if (instance.isNull()) {
            return fail("instance_new", cycle)
        }
        if (!driverLive) {
            return fail("driver_live_before_submit", cycle)
        }
        if (task.isNull()) {
            return fail("task_submit", cycle)
        }
        unsafe {
            CJRT_ContractStage(STAGE_WAITER_RESUMED, cycle, waiterSchedule, waiterCJThread,
                waiterState, waiterOSThread)
        }
        if (!wakeState.callbackEntered || !wakeState.stateUpdated || !wakeState.notifyIssued) {
            return fail("callback_state", cycle)
        }
        if (waiterSchedule == 0 || callbackSchedule == 0 || waiterSchedule == callbackSchedule ||
            waiterCJThread == 0 || callbackCJThread == 0 || waiterCJThread == callbackCJThread) {
            return fail("schedule_identity", cycle)
        }
        if (callbackState < 0 || callbackOSThread == 0) {
            return fail("callback_identity", cycle)
        }
        if (unsafe { CJRT_ContractGetRetMatches(task, argument) } != 0) {
            return fail("return_identity", cycle)
        }
        unsafe {
            CJRT_ContractStage(STAGE_RETURN_MATCHED, cycle, callbackSchedule, callbackCJThread,
                callbackState, callbackOSThread)
        }
        if (unsafe { CJRT_ContractReleaseAndReject(task) } != 0) {
            return fail("handle_release", cycle)
        }
        unsafe {
            CJRT_ContractStage(STAGE_HANDLE_RELEASED, cycle, callbackSchedule, callbackCJThread,
                callbackState, callbackOSThread)
        }
        if (unsafe { CJRT_ContractStop(mode, instance) } != 0) {
            return fail("instance_stop", cycle)
        }
        unsafe {
            CJRT_ContractStage(STAGE_INSTANCE_STOPPED, cycle, waiterSchedule, waiterCJThread,
                waiterState, waiterOSThread)
        }
        if (mode == 0 && unsafe { CJRT_ContractStop(mode, instance) } == 0) {
            return fail("second_stop", cycle)
        }
        if (mode == 0) {
            let driverCount = unsafe { CJRT_ContractDriverCount() }
            if (driverCount != 0) {
                return fail("driver_leak", cycle)
            }
            if (stableDriverCount < 0) {
                stableDriverCount = driverCount
            } else if (driverCount != stableDriverCount) {
                return fail("driver_count", cycle)
            }
        }
        cycle++
    }

    let rssAfter = unsafe { CJRT_ContractResidentBytes() }
    if (rssAfter == 0 || (rssAfter > rssBefore && rssAfter - rssBefore >= 8 * 1024 * 1024)) {
        return fail("rss_limit", cycles)
    }
    unsafe { CJRT_ContractPass(mode, cycles, rssBefore, rssAfter) }
    return 0
}
