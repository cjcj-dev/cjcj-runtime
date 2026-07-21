package rt.common

import rt.heap.allocator.*
import rt.sync.*
import std.overflow.*

foreign {
    func getpagesize(): Int32
    func abort(): Unit

    @When[os != "Windows"]
    func mmap(address: CPointer<Unit>, length: UIntNative, prot: Int32, flags: Int32,
        fd: Int32, offset: IntNative): CPointer<Unit>
    @When[os != "Windows"]
    func munmap(address: CPointer<Unit>, length: UIntNative): Int32
    @When[os != "Windows"]
    func perror(message: CString): Unit
    @When[os == "Linux"]
    func madvise(address: CPointer<Unit>, length: UIntNative, advice: Int32): Int32
    @When[os == "macOS" || os == "iOS"]
    func memset(address: CPointer<Unit>, value: Int32, length: UIntNative): CPointer<Unit>

    @When[os == "Windows"]
    func VirtualAlloc(address: CPointer<Unit>, size: UIntNative, allocationType: UInt32,
        protect: UInt32): CPointer<Unit>
    @When[os == "Windows"]
    func VirtualFree(address: CPointer<Unit>, size: UIntNative, freeType: UInt32): Int32
    @When[os == "Windows"]
    func GetLastError(): UInt32

    func CJRT_PagePoolMutexConstruct(storage: CPointer<Unit>): Unit
    func CJRT_PagePoolMutexDestroy(storage: CPointer<Unit>): Unit
    func CJRT_PagePoolMutexLock(storage: CPointer<Unit>): Unit
    func CJRT_PagePoolMutexUnlock(storage: CPointer<Unit>): Unit
}

var PAGE_POOL_FINI_ERROR: VArray<UInt8, $38> = [
    109u8, 117u8, 110u8, 109u8, 97u8, 112u8, 32u8, 102u8, 97u8, 105u8,
    108u8, 101u8, 100u8, 32u8, 105u8, 110u8, 32u8, 80u8, 97u8, 103u8,
    101u8, 80u8, 111u8, 111u8, 108u8, 32u8, 100u8, 101u8, 115u8, 116u8,
    114u8, 117u8, 99u8, 116u8, 105u8, 111u8, 110u8, 0u8
]
var PAGE_POOL_RETURN_ERROR: VArray<UInt8, $28> = [
    109u8, 117u8, 110u8, 109u8, 97u8, 112u8, 32u8, 102u8, 97u8, 105u8,
    108u8, 101u8, 100u8, 32u8, 105u8, 110u8, 32u8, 82u8, 101u8, 116u8,
    117u8, 114u8, 110u8, 80u8, 97u8, 103u8, 101u8, 0u8
]
var PAGE_POOL_MAP_FATAL: VArray<UInt8, $55> = [
    97u8, 108u8, 108u8, 111u8, 99u8, 97u8, 116u8, 101u8, 32u8, 99u8,
    114u8, 101u8, 97u8, 116u8, 101u8, 32u8, 112u8, 97u8, 103u8, 101u8,
    32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8, 33u8, 32u8, 79u8,
    117u8, 116u8, 32u8, 111u8, 102u8, 32u8, 77u8, 101u8, 109u8, 111u8,
    114u8, 121u8, 33u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8,
    0u8, 0u8, 0u8
]

// Base/Globals.h:29-30 and RegionManager.cpp:49-52.
public let MRT_PAGE_SIZE: UIntNative = UIntNative(unsafe { getpagesize() })

// PagePool.h:152. Opaque inline storage for the 40-byte std::mutex ABI used by the
// production Linux target. PagePool is compiled on other targets with this ABI debt
// explicitly retained; the Layer0 bridge is Linux-only in this lane.
@C
public struct PagePoolMutex {
    var word0: UInt64
    var word1: UInt64
    var word2: UInt64
    var word3: UInt64
    var word4: UInt64

    public init() {
        word0 = 0u64
        word1 = 0u64
        word2 = 0u64
        word3 = 0u64
        word4 = 0u64
    }
}

// Common/PagePool.h:28-43,122-162. Field order is the original order.
@C
public struct PagePool {
    var freePagesMutex: PagePoolMutex
    var freePagesTree: CartesianTree
    var base: CPointer<UInt8>
    var totalSize: UIntNative
    var usedZone: UIntNative
    var tag: CString
    var smallPageUsed: UInt32
    var totalPageCount: UInt32

    // PagePool.h:32-35 and in-class initializers at :154-161.
    public init(name: CString) {
        freePagesMutex = PagePoolMutex()
        freePagesTree = CartesianTree()
        base = CPointer<UInt8>()
        totalSize = 0
        usedZone = 0
        tag = name
        smallPageUsed = 0u32
        totalPageCount = 0u32
    }
}

extend CPointer<PagePool> {
    // PagePool.h:36-43. Assignment and initialization order is exact.
    public func Init(pageCount: UInt32): Unit {
        unsafe { CPointer<UInt32>(CPointer<UInt8>(this) + 204).write(0, pageCount) }
        let size = UIntNative(pageCount) * MRT_PAGE_SIZE
        let tree = unsafe { CPointer<CartesianTree>(CPointer<UInt8>(this) + 40) }
        Init(tree, UIntNative(pageCount))
        let tag = unsafe { CPointer<CString>(CPointer<UInt8>(this) + 192).read(0) }
        let base = MapMemory(size, tag)
        unsafe {
            CPointer<CPointer<UInt8>>(CPointer<UInt8>(this) + 168).write(0, base)
            CPointer<UIntNative>(CPointer<UInt8>(this) + 176).write(0, size)
        }
    }

    // PagePool.h:44-54.
    public func Fini(): Unit {
        let tree = unsafe { CPointer<CartesianTree>(CPointer<UInt8>(this) + 40) }
        Fini(tree)
        let base = unsafe {
            CPointer<CPointer<UInt8>>(CPointer<UInt8>(this) + 168).read(0)
        }
        let pageCount = unsafe { CPointer<UInt32>(CPointer<UInt8>(this) + 204).read(0) }
        FiniImpl(CPointer<Unit>(base), UIntNative(pageCount) * MRT_PAGE_SIZE)
    }

    // PagePool.h:56-83.
    public func GetPage(bytes!: UIntNative = MRT_PAGE_SIZE): CPointer<UInt8> {
        var idx: Index = 0u32
        let count = (bytes + MRT_PAGE_SIZE - 1).wrappingDiv(MRT_PAGE_SIZE)
        let pageSize = (bytes + MRT_PAGE_SIZE - 1) & (0 - MRT_PAGE_SIZE)
        if (count >= UIntNative(UInt32.Max)) {
            unsafe { abort() }
        }
        let tree = unsafe { CPointer<CartesianTree>(CPointer<UInt8>(this) + 40) }
        unsafe { CJRT_PagePoolMutexLock(CPointer<Unit>(this)) }
        if (CartesianTree.TakeUnits(tree, UInt32(count), CPointer<Index>(inout idx), false)) {
            let base = unsafe {
                CPointer<CPointer<UInt8>>(CPointer<UInt8>(this) + 168).read(0)
            }
            let ret = unsafe { base + Int64(UIntNative(idx) * MRT_PAGE_SIZE) }
            GetPageImpl(CPointer<Unit>(ret), pageSize)
            unsafe { CJRT_PagePoolMutexUnlock(CPointer<Unit>(this)) }
            return ret
        }
        let usedZone = unsafe { CPointer<UIntNative>(CPointer<UInt8>(this) + 184).read(0) }
        let totalSize = unsafe { CPointer<UIntNative>(CPointer<UInt8>(this) + 176).read(0) }
        let base = unsafe {
            CPointer<CPointer<UInt8>>(CPointer<UInt8>(this) + 168).read(0)
        }
        if (usedZone + pageSize <= totalSize && !base.isNull()) {
            unsafe {
                CPointer<UIntNative>(CPointer<UInt8>(this) + 184).write(0, usedZone + pageSize)
            }
            let ret = unsafe { base + Int64(usedZone) }
            GetPageImpl(CPointer<Unit>(ret), pageSize)
            unsafe { CJRT_PagePoolMutexUnlock(CPointer<Unit>(this)) }
            return ret
        }
        unsafe { CJRT_PagePoolMutexUnlock(CPointer<Unit>(this)) }
        let tag = unsafe { CPointer<CString>(CPointer<UInt8>(this) + 192).read(0) }
        return MapMemory(pageSize, tag, isCommit: true)
    }

    // PagePool.h:85-120.
    public func ReturnPage(page: CPointer<UInt8>, bytes!: UIntNative = MRT_PAGE_SIZE): Unit {
        let base = unsafe {
            CPointer<CPointer<UInt8>>(CPointer<UInt8>(this) + 168).read(0)
        }
        let totalSize = unsafe { CPointer<UIntNative>(CPointer<UInt8>(this) + 176).read(0) }
        let end = unsafe { base + Int64(totalSize) }
        let num = (bytes + MRT_PAGE_SIZE - 1).wrappingDiv(MRT_PAGE_SIZE)
        if (page.toUIntNative() < base.toUIntNative() || page.toUIntNative() >= end.toUIntNative()) {
            ReturnPageImpl(CPointer<Unit>(page), num * MRT_PAGE_SIZE)
            return
        }
        if (num >= UIntNative(UInt32.Max)) {
            unsafe { abort() }
        }
        let idx = UInt32((page.toUIntNative() - base.toUIntNative()).wrappingDiv(MRT_PAGE_SIZE))
        ReturnPagePart2(CPointer<Unit>(page), num * MRT_PAGE_SIZE)
        unsafe { CJRT_PagePoolMutexLock(CPointer<Unit>(this)) }
        let tree = unsafe { CPointer<CartesianTree>(CPointer<UInt8>(this) + 40) }
        let inserted = CartesianTree.MergeInsert(tree, idx, UInt32(num), false)
        unsafe { CJRT_PagePoolMutexUnlock(CPointer<Unit>(this)) }
        if (!inserted) {
            unsafe { abort() }
        }
    }

    // PagePool.h:122-123.
    public func Trim(): Unit {}

    // PagePool.h:128-149.
    @When[os == "Linux"]
    public func MapMemory(size: UIntNative, memName: CString,
        isCommit!: Bool = false): CPointer<UInt8> {
        let _ = isCommit
        let result = unsafe {
            mmap(CPointer<Unit>(), size, MemMap.PROT_READ | MemMap.PROT_WRITE,
                Int32(MemMap.MAP_PRIVATE | MemMap.MAP_ANONYMOUS | MemMap.MAP_NORESERVE), -1, 0)
        }
        if (result.toUIntNative() == UIntNative.Max) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout PAGE_POOL_MAP_FATAL))) }
        }
        unsafe {
            let _ = madvise(result, size, 15)
            MRT_PRCTL(result, size, memName)
        }
        return CPointer<UInt8>(result)
    }

    @When[os == "macOS" || os == "iOS"]
    public func MapMemory(size: UIntNative, memName: CString,
        isCommit!: Bool = false): CPointer<UInt8> {
        let _ = memName
        let _ = isCommit
        let result = unsafe {
            mmap(CPointer<Unit>(), size, MemMap.PROT_READ | MemMap.PROT_WRITE,
                Int32(MemMap.MAP_PRIVATE | MemMap.MAP_ANONYMOUS | MemMap.MAP_NORESERVE), -1, 0)
        }
        if (result.toUIntNative() == UIntNative.Max) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout PAGE_POOL_MAP_FATAL))) }
        }
        return CPointer<UInt8>(result)
    }

    @When[os == "Windows"]
    public func MapMemory(size: UIntNative, memName: CString,
        isCommit!: Bool = false): CPointer<UInt8> {
        let _ = memName
        let allocationType = if (isCommit) { 0x1000u32 } else { 0x2000u32 }
        let result = unsafe { VirtualAlloc(CPointer<Unit>(), size, allocationType, 0x04u32) }
        if (result.isNull()) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout PAGE_POOL_MAP_FATAL))) }
        }
        return CPointer<UInt8>(result)
    }
}

// PagePool.h:47-53.
@When[os != "Windows"]
func FiniImpl(base: CPointer<Unit>, size: UIntNative): Unit {
    let ret = unsafe { munmap(base, size) }
    if (ret != 0) {
        unsafe { perror(CString(CPointer<UInt8>(inout PAGE_POOL_FINI_ERROR))) }
    }
}
@When[os == "Windows"]
func FiniImpl(base: CPointer<Unit>, size: UIntNative): Unit {
    let _ = size
    if (unsafe { VirtualFree(base, 0, 0x8000u32) } == 0) {
        unsafe { let _ = GetLastError() }
    }
}

// PagePool.h:66-69,75-78.
@When[os != "Windows"]
func GetPageImpl(page: CPointer<Unit>, size: UIntNative): Unit {
    let _ = page
    let _ = size
}
@When[os == "Windows"]
func GetPageImpl(page: CPointer<Unit>, size: UIntNative): Unit {
    if (unsafe { VirtualAlloc(page, size, 0x1000u32, 0x04u32) }.isNull()) {
        unsafe { let _ = GetLastError() }
    }
}

// PagePool.h:89-97.
@When[os != "Windows"]
func ReturnPageImpl(page: CPointer<Unit>, size: UIntNative): Unit {
    if (unsafe { munmap(page, size) } != 0) {
        unsafe { perror(CString(CPointer<UInt8>(inout PAGE_POOL_RETURN_ERROR))) }
    }
}
@When[os == "Windows"]
func ReturnPageImpl(page: CPointer<Unit>, size: UIntNative): Unit {
    let _ = size
    if (unsafe { VirtualFree(page, 0, 0x8000u32) } == 0) {
        unsafe { let _ = GetLastError() }
    }
}

// PagePool.h:101-116.
@When[os == "Linux"]
func ReturnPagePart2(page: CPointer<Unit>, size: UIntNative): Unit {
    unsafe { let _ = madvise(page, size, 4) }
}
@When[os == "macOS" || os == "iOS"]
func ReturnPagePart2(page: CPointer<Unit>, size: UIntNative): Unit {
    var mmapFailedMessage: VArray<UInt8, $28> = [
        112u8, 97u8, 103u8, 101u8, 32u8, 112u8, 111u8, 111u8, 108u8, 32u8,
        109u8, 109u8, 97u8, 112u8, 32u8, 102u8, 105u8, 120u8, 101u8, 100u8,
        32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8, 0u8
    ]
    var wrongAddressMessage: VArray<UInt8, $25> = [
        109u8, 109u8, 97u8, 112u8, 32u8, 102u8, 105u8, 120u8, 101u8, 100u8,
        32u8, 97u8, 116u8, 32u8, 119u8, 114u8, 111u8, 110u8, 103u8, 32u8,
        97u8, 100u8, 100u8, 114u8, 0u8
    ]
    unsafe {
        let _ = memset(page, 0, size)
        let ret = mmap(page, size, MemMap.PROT_READ | MemMap.PROT_WRITE,
            Int32(MemMap.MAP_PRIVATE | MemMap.MAP_ANONYMOUS | MemMap.MAP_FIXED), -1, 0)
        if (ret.toUIntNative() == UIntNative.Max) {
            perror(CString(CPointer<UInt8>(inout mmapFailedMessage)))
        } else if (ret.toUIntNative() != page.toUIntNative()) {
            perror(CString(CPointer<UInt8>(inout wrongAddressMessage)))
        }
    }
}
@When[os == "Windows"]
func ReturnPagePart2(page: CPointer<Unit>, size: UIntNative): Unit {
    if (unsafe { VirtualFree(page, size, 0x4000u32) } == 0) {
        unsafe { let _ = GetLastError() }
    }
}

// Allocator.cpp:68-73. The literal has process-lifetime static backing.
var PAGE_POOL_TAG: VArray<UInt8, $9> = [
    80u8, 97u8, 103u8, 101u8, 80u8, 111u8, 111u8, 108u8, 0u8
]
var PAGE_POOL_INSTANCE: PagePool = PagePool(CString(CPointer<UInt8>(inout PAGE_POOL_TAG)))
var PAGE_POOL_MUTEX_CONSTRUCTED: Unit = unsafe {
    CJRT_PagePoolMutexConstruct(CPointer<Unit>(CPointer<PagePool>(inout PAGE_POOL_INSTANCE)))
}

// Allocator.cpp:69-72. C++ reference return lowers to the object address.
@C
public func _ZN12MapleRuntime8PagePool8InstanceEv(): CPointer<PagePool> {
    return unsafe { CPointer<PagePool>(inout PAGE_POOL_INSTANCE) }
}

// PagePool.h:44-54. Emitted weak C++ method ABI entry; forwarding only.
@C
public func _ZN12MapleRuntime8PagePool4FiniEv(pagePool: CPointer<PagePool>): Unit {
    pagePool.Fini()
}

// PagePool.h:56-83. Emitted weak C++ method ABI entry; forwarding only.
@C
public func _ZN12MapleRuntime8PagePool7GetPageEm(pagePool: CPointer<PagePool>,
    bytes: UIntNative): CPointer<UInt8> {
    return pagePool.GetPage(bytes: bytes)
}

// PagePool.h:85-120. Emitted weak C++ method ABI entry; forwarding only.
@C
public func _ZN12MapleRuntime8PagePool10ReturnPageEPhm(pagePool: CPointer<PagePool>,
    page: CPointer<UInt8>, bytes: UIntNative): Unit {
    pagePool.ReturnPage(page, bytes: bytes)
}

// PagePool.h:128-149. Emitted weak protected C++ method ABI entry; forwarding only.
@C
public func _ZNK12MapleRuntime8PagePool9MapMemoryEmPKcb(pagePool: CPointer<PagePool>,
    size: UIntNative, memName: CString, isCommit: Bool): CPointer<UInt8> {
    return pagePool.MapMemory(size, memName, isCommit: isCommit)
}
