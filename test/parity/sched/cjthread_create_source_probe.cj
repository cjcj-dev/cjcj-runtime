// Test-only executable entry for schedule.h:403-410 representation parity.
foreign func CJRT_CJThreadCreateSourceRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_CJThreadCreateSourceRun() })
}
