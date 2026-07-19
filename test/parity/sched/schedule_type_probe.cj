// Test-only executable entry for schedule.h:423-430 representation parity.
foreign func CJRT_ScheduleTypeRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_ScheduleTypeRun() })
}
