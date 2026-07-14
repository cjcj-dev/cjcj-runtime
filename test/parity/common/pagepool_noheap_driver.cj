package rt.common

main(): Int64 {
    var tagBytes: VArray<UInt8, $9> = [
        80u8, 97u8, 103u8, 101u8, 80u8, 111u8, 111u8, 108u8, 0u8
    ]
    var pagePoolValue = PagePool(CString(CPointer<UInt8>()))
    let pagePool = unsafe { CPointer<PagePool>(inout pagePoolValue) }
    PagePoolConstructNoHeapRoot(pagePool, CString(CPointer<UInt8>(inout tagBytes)))
    PagePoolInitNoHeapRoot(pagePool, 8u32)
    let first = PagePoolGetPageNoHeapRoot(pagePool, MRT_PAGE_SIZE)
    let second = PagePoolGetPageNoHeapRoot(pagePool, MRT_PAGE_SIZE)
    PagePoolReturnPageNoHeapRoot(pagePool, first, MRT_PAGE_SIZE)
    let reused = PagePoolGetPageNoHeapRoot(pagePool, MRT_PAGE_SIZE)
    if (reused.toUIntNative() != first.toUIntNative()) {
        unsafe { abort() }
    }
    PagePoolReturnPageNoHeapRoot(pagePool, reused, MRT_PAGE_SIZE)
    PagePoolReturnPageNoHeapRoot(pagePool, second, MRT_PAGE_SIZE)
    var inside = 0
    var overflow = CPointer<UInt8>()
    while (overflow.isNull()) {
        let page = PagePoolGetPageNoHeapRoot(pagePool, MRT_PAGE_SIZE)
        let base = unsafe { CPointer<CPointer<UInt8>>(CPointer<UInt8>(pagePool) + 168).read(0) }
        let size = unsafe { CPointer<UIntNative>(CPointer<UInt8>(pagePool) + 176).read(0) }
        if (page.toUIntNative() >= base.toUIntNative() &&
            page.toUIntNative() < base.toUIntNative() + size) {
            inside += 1
        } else {
            overflow = page
        }
    }
    PagePoolReturnPageNoHeapRoot(pagePool, overflow, MRT_PAGE_SIZE)
    PagePoolTrimFiniNoHeapRoot(pagePool)
    unsafe { CJRT_PagePoolMutexDestroy(CPointer<Unit>(pagePool)) }
    println("PAGEPOOL_NOHEAP_EXEC bump=${inside} reuse=PASS overflow=PASS fini=PASS")
    return 0
}
