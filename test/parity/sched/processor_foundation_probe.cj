foreign func CJRT_ProcessorFoundationRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_ProcessorFoundationRun() })
}
