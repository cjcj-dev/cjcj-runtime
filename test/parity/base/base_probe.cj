import rt.base.*
import rt.sync.MRT_PRCTL

foreign {
    func mmap(address: CPointer<Unit>, length: UIntNative, prot: Int32, flags: Int32,
        fd: Int32, offset: IntNative): CPointer<Unit>
}

main(): Int64 {
    CHECK_DETAIL(true, "must not abort")
    LOG(RTLOG_ERROR, "probe")

    let size = AllocUtilRndUp(1, UIntNative(ALLOC_UTIL_PAGE_SIZE))
    let address = unsafe { mmap(CPointer<Unit>(), size, 0x3, 0x22, -1, 0) }
    if (address.toUIntNative() == UIntNative.Max) {
        return 1
    }
    let tag = unsafe { LibC.mallocCString("base_probe") }
    unsafe { MRT_PRCTL(address, size, tag) }
    unsafe { LibC.free(tag) }
    ALLOCUTIL_MEM_UNMAP(address, size)
    println("BASE_PROBE PASS")
    return 0
}
