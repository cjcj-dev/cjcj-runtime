import rt.common.*

foreign func ThreadLocalTLSABIProbeMain(): Int32

main(): Int64 {
    return Int64(unsafe { ThreadLocalTLSABIProbeMain() })
}
