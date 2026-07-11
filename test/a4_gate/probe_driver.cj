package a4.gate.driver

foreign func CJRT_G1StackOnlyProbe(value: UIntNative): UIntNative
foreign func CJRT_G5ThreadLocalProbe(): UIntNative

main(): Int64 {
    let stackResult = unsafe { CJRT_G1StackOnlyProbe(41) }
    let threadLocal = unsafe { CJRT_G5ThreadLocalProbe() }
    println("stack_result=${stackResult} tls_nonnull=${if (threadLocal != 0) { 1 } else { 0 }}")
    return if (stackResult == 42 && threadLocal != 0) { 0 } else { 1 }
}
