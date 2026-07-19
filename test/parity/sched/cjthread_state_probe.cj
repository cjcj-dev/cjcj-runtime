// Test-only executable entry for schedule.h:415-420 representation parity.
foreign func CJRT_CJThreadStateRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_CJThreadStateRun() })
}
