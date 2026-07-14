package rt.common

@C
public func CJRT_PagePoolProbeInit(pageCount: UInt32): Unit {
    unsafe { CPointer<PagePool>(inout PAGE_POOL_INSTANCE) }.Init(pageCount)
}

@C
public func CJRT_PagePoolProbeTrim(): Unit {
    unsafe { CPointer<PagePool>(inout PAGE_POOL_INSTANCE) }.Trim()
}

@C
public func CJRT_PagePoolProbeBase(): CPointer<UInt8> {
    return unsafe { CPointer<CPointer<UInt8>>(CPointer<UInt8>(inout PAGE_POOL_INSTANCE) + 168).read(0) }
}

@C
public func CJRT_PagePoolProbeTotalSize(): UIntNative {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(inout PAGE_POOL_INSTANCE) + 176).read(0) }
}

@C
public func CJRT_PagePoolProbePageSize(): UIntNative {
    return MRT_PAGE_SIZE
}

@C
public func CJRT_PagePoolProbeTag(): CString {
    return unsafe { CPointer<CString>(CPointer<UInt8>(inout PAGE_POOL_INSTANCE) + 192).read(0) }
}
