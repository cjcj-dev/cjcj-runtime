package a4.gate

foreign func MRT_GetThreadLocalData(): UIntNative

@NoHeapAlloc
@C
public func CJRT_G1StackOnlyProbe(value: UIntNative): UIntNative {
    return value + 1
}

@NoHeapAlloc
@C
public func CJRT_G5ThreadLocalProbe(): UIntNative {
    return unsafe { MRT_GetThreadLocalData() }
}
