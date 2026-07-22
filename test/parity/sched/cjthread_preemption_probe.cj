foreign func CJRT_CJThreadPreemptionRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_CJThreadPreemptionRun() })
}
