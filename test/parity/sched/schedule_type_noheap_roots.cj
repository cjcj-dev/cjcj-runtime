package scheduletype.noheap

import rt.sched.ScheduleType
import rt.sched.SCHEDULE_DEFAULT
import rt.sched.SCHEDULE_UI_THREAD
import rt.sched.SCHEDULE_FOREIGN_THREAD
import rt.sched.SCHEDULE_EXCLUSIVE

foreign func ScheduleTypeObserve(scheduleDefault: UInt32, uiThread: UInt32,
    foreignThread: UInt32, exclusive: UInt32, aliasSize: UIntNative,
    aliasAlign: UIntNative, aliasSigned: UInt32): Int32

// schedule.h:423-430,839. This fixed root carries only the four unsigned ABI
// values; the real C++ owner oracle independently validates Schedule:253.
@C
public func CJRT_ScheduleTypeRun(): Int32 {
    return unsafe {
        ScheduleTypeObserve(SCHEDULE_DEFAULT, SCHEDULE_UI_THREAD,
            SCHEDULE_FOREIGN_THREAD, SCHEDULE_EXCLUSIVE, sizeOf<ScheduleType>(),
            alignOf<ScheduleType>(), 0u32)
    }
}
