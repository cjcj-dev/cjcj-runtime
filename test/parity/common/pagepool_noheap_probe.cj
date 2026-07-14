package rt.common

@NoHeapAlloc
public func PagePoolConstructNoHeapRoot(storage: CPointer<PagePool>, tag: CString): Unit {
    unsafe {
        storage.write(0, PagePool(tag))
        CJRT_PagePoolMutexConstruct(CPointer<Unit>(storage))
    }
}

@NoHeapAlloc
public func PagePoolInitNoHeapRoot(pagePool: CPointer<PagePool>, pageCount: UInt32): Unit {
    pagePool.Init(pageCount)
}

@NoHeapAlloc
public func PagePoolGetPageNoHeapRoot(pagePool: CPointer<PagePool>,
    bytes: UIntNative): CPointer<UInt8> {
    return pagePool.GetPage(bytes: bytes)
}

@NoHeapAlloc
public func PagePoolReturnPageNoHeapRoot(pagePool: CPointer<PagePool>,
    page: CPointer<UInt8>, bytes: UIntNative): Unit {
    pagePool.ReturnPage(page, bytes: bytes)
}

@NoHeapAlloc
public func PagePoolTrimFiniNoHeapRoot(pagePool: CPointer<PagePool>): Unit {
    pagePool.Trim()
    pagePool.Fini()
}
