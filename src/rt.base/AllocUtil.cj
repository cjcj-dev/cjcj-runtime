package rt.base

// Heap/Allocator/AllocUtil.h:15.
public const ALLOC_UTIL_PAGE_SIZE: UInt32 = 4096

// Heap/Allocator/AllocUtil.h:31-35. MemMap's size_t instantiation.
public func AllocUtilRndDown(x: UIntNative, n: UIntNative): UIntNative {
    return x & (0 - n)
}

// Heap/Allocator/AllocUtil.h:37-41. MemMap.cpp:29 instantiates T=size_t.
public func AllocUtilRndUp(x: UIntNative, n: UIntNative): UIntNative {
    return AllocUtilRndDown(x + n - 1, n)
}

foreign {
    @When[os != "Windows"]
    func munmap(address: CPointer<Unit>, size: UIntNative): Int32
}

// Heap/Allocator/AllocUtil.h:24-29.
@When[os != "Windows"]
public func ALLOCUTIL_MEM_UNMAP(address: CPointer<Unit>, sizeInBytes: UIntNative): Unit {
    if (unsafe { munmap(address, sizeInBytes) } != 0) {
        LOG(RTLOG_FATAL, "munmap failed. Process terminating.")
    }
}

// MemMap.cpp:48; Linux <sys/mman.h> constant consumed by the allocator slice.
@When[os == "Linux"]
public const MADV_NOHUGEPAGE: Int32 = 15
