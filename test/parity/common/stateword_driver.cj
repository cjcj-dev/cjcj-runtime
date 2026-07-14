import rt.common.*

foreign func StateWordProbeMain(): Int32

main(): Int64 {
    return Int64(unsafe { StateWordProbeMain() })
}
