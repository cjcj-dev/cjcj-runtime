foreign func CJRT_SchedLowdepsRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_SchedLowdepsRun() })
}
