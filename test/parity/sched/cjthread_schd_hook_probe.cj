// Test-only executable entry for schedule.h:332-342 representation parity.
foreign func CJRT_CJThreadSchdHookRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_CJThreadSchdHookRun() })
}
