package rt.base

// Heap/Allocator/AllocUtil.h:15.
public const ALLOC_UTIL_PAGE_SIZE: UInt32 = 4096

// Heap/Allocator/AllocUtil.h:16-17.
public func ALLOCUTIL_PAGE_RND_UP(x: UIntNative): UIntNative {
    return (x + UIntNative(ALLOC_UTIL_PAGE_SIZE) - 1) &
        (0 - UIntNative(ALLOC_UTIL_PAGE_SIZE))
}

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

    // Windows <memoryapi.h>; BOOL VirtualFree(LPVOID, SIZE_T, DWORD).
    @When[os == "Windows"]
    func VirtualFree(address: CPointer<Unit>, size: UIntNative, freeType: UInt32): Int32
}

// Heap/Allocator/AllocUtil.h:20 (_WIN64). MEM_RELEASE frees the whole reservation and requires size 0.
@When[os == "Windows"]
public const MEM_RELEASE: UInt32 = 0x8000u32

// Heap/Allocator/AllocUtil.h:24-28 (else).
@When[os != "Windows"]
public func ALLOCUTIL_MEM_UNMAP(address: CPointer<Unit>, sizeInBytes: UIntNative): Unit {
    if (unsafe { munmap(address, sizeInBytes) } != 0) {
        LOG(RTLOG_FATAL, "munmap failed. Process terminating.")
    }
}

// Heap/Allocator/AllocUtil.h:19-23 (_WIN64). VirtualFree returns FALSE (0) on failure.
@When[os == "Windows"]
public func ALLOCUTIL_MEM_UNMAP(address: CPointer<Unit>, sizeInBytes: UIntNative): Unit {
    let _ = sizeInBytes
    if (unsafe { VirtualFree(address, 0, MEM_RELEASE) } == 0) {
        LOG(RTLOG_FATAL, "VirtualFree failed. Process terminating.")
    }
}

// MemMap.cpp:48; Linux <sys/mman.h> constant consumed by the allocator slice.
@When[os == "Linux"]
public const MADV_NOHUGEPAGE: Int32 = 15
