package rt.common

foreign func PagePoolProbeMain(): Int32

main(): Int64 {
    return Int64(unsafe { PagePoolProbeMain() })
}
