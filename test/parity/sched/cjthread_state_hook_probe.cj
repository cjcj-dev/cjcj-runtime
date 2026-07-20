// Test-only executable entry for schedule.h:344-353 representation parity.
foreign func CJRT_CJThreadStateHookRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_CJThreadStateHookRun() })
}
