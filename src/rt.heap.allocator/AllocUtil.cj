package rt.heap.allocator

// Heap/Allocator/AllocUtil.h:15.
public const ALLOC_UTIL_PAGE_SIZE: UInt32 = 4096

// Heap/Allocator/AllocUtil.h:16-17.
@NoHeapAlloc
public func ALLOCUTIL_PAGE_RND_UP(x: UIntNative): UIntNative {
    return (x + UIntNative(ALLOC_UTIL_PAGE_SIZE) - 1) &
        (0 - UIntNative(ALLOC_UTIL_PAGE_SIZE))
}

// Windows <memoryapi.h>: MEM_RELEASE.
@When[os == "Windows"]
private const MEM_RELEASE: UInt32 = 0x8000u32

@When[os == "Windows"]
private var allocUtilUnmapFailure: VArray<UInt8, $41> = [
    86u8, 105u8, 114u8, 116u8, 117u8, 97u8, 108u8, 70u8, 114u8, 101u8,
    101u8, 32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8, 46u8, 32u8,
    80u8, 114u8, 111u8, 99u8, 101u8, 115u8, 115u8, 32u8, 116u8, 101u8,
    114u8, 109u8, 105u8, 110u8, 97u8, 116u8, 105u8, 110u8, 103u8, 46u8,
    0u8
]

@When[os != "Windows"]
private var allocUtilUnmapFailure: VArray<UInt8, $36> = [
    109u8, 117u8, 110u8, 109u8, 97u8, 112u8, 32u8, 102u8, 97u8, 105u8,
    108u8, 101u8, 100u8, 46u8, 32u8, 80u8, 114u8, 111u8, 99u8, 101u8,
    115u8, 115u8, 32u8, 116u8, 101u8, 114u8, 109u8, 105u8, 110u8, 97u8,
    116u8, 105u8, 110u8, 103u8, 46u8, 0u8
]

// Heap/Allocator/AllocUtil.h:19-23 (_WIN64).
@When[os == "Windows"]
@NoHeapAlloc
public func ALLOCUTIL_MEM_UNMAP(address: CPointer<Unit>, sizeInBytes: UIntNative): Unit {
    let _ = sizeInBytes
    if (unsafe { VirtualFree(address, 0, MEM_RELEASE) } == 0) {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout allocUtilUnmapFailure))) }
    }
}

// Heap/Allocator/AllocUtil.h:24-28 (POSIX, including Linux and Apple).
@When[os != "Windows"]
@NoHeapAlloc
public func ALLOCUTIL_MEM_UNMAP(address: CPointer<Unit>, sizeInBytes: UIntNative): Unit {
    if (unsafe { munmap(address, sizeInBytes) } != 0) {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout allocUtilUnmapFailure))) }
    }
}

// Heap/Allocator/AllocUtil.h:31-35. The allocator instantiates T as size_t.
@NoHeapAlloc
public func AllocUtilRndDown(x: UIntNative, n: UIntNative): UIntNative {
    return x & (0 - n)
}

// Heap/Allocator/AllocUtil.h:37-41. The allocator instantiates T as size_t.
@NoHeapAlloc
public func AllocUtilRndUp(x: UIntNative, n: UIntNative): UIntNative {
    return AllocUtilRndDown(x + n - 1, n)
}
