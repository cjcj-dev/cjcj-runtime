package rt.heap.allocator

import rt.base.*
import rt.sync.*

foreign {
    // POSIX mapping primitives, used on Linux/OHOS and Apple. <sys/mman.h>.
    @When[os != "Windows"]
    func mmap(address: CPointer<Unit>, length: UIntNative, prot: Int32, flags: Int32,
        fd: Int32, offset: IntNative): CPointer<Unit>

    @When[os != "Windows"]
    func mprotect(address: CPointer<Unit>, length: UIntNative, prot: Int32): Int32

    @When[os != "Windows"]
    func munmap(address: CPointer<Unit>, length: UIntNative): Int32

    // Linux-only page advice. Apple lacks MADV_NOHUGEPAGE, so MemMap.cpp:44 skips madvise there.
    @When[os == "Linux" || env == "ohos"]
    func madvise(address: CPointer<Unit>, length: UIntNative, advice: Int32): Int32

    // Windows virtual-memory API. <memoryapi.h>.
    @When[os == "Windows"]
    func VirtualAlloc(address: CPointer<Unit>, size: UIntNative, allocationType: UInt32,
        protect: UInt32): CPointer<Unit>
    @When[os == "Windows"]
    func GetLastError(): UInt32
    @When[os == "Windows"]
    func VirtualFree(address: CPointer<Unit>, size: UIntNative, freeType: UInt32): Int32

    // MemMap.cpp:64 `new (std::nothrow) MemMap` and MemMap.h:57 `delete memMap` resolve to the
    // global operator new / operator delete. The runtime installs no operator-new override, so
    // those lower to malloc/free; this mirrors them faithfully. NativeAllocator (the runtime's own
    // page/thread-cache allocator) is invoked only at explicit NativeAlloc/NativeFree call sites and
    // never backs a `new MemMap`, so it is intentionally not involved here.
    func malloc(size: UIntNative): CPointer<Unit>
    func free(address: CPointer<Unit>): Unit
}

// Heap/Allocator/MemMap.h:37-43.
@C
public struct Option {
    public let tag: CString
    public let reqBase: CPointer<Unit>
    public let flags: UInt32
    public let prot: Int32
    public let protAll: Bool

    public init(tag: CString, reqBase: CPointer<Unit>, flags: UInt32, prot: Int32, protAll: Bool) {
        this.tag = tag
        this.reqBase = reqBase
        this.flags = flags
        this.prot = prot
        this.protAll = protAll
    }
}

// Heap/Allocator/MemMap.h:21-86; MemMap.cpp:26-100.
@C
public struct MemMap {
    public static const MAP_PRIVATE: UInt32 = 2u32
    public static const MAP_FIXED: UInt32 = 0x10u32

    // MemMap.h:23-31 defines these for Windows; elsewhere they come from <sys/mman.h>. The Apple
    // (Darwin) MAP_ANON/MAP_NORESERVE bit values differ from Linux, so they are selected per target.
    @When[os == "macOS" || os == "iOS"]
    public static const MAP_ANONYMOUS: UInt32 = 0x1000u32
    @When[os != "macOS" && os != "iOS"]
    public static const MAP_ANONYMOUS: UInt32 = 0x20u32

    @When[os == "macOS" || os == "iOS"]
    public static const MAP_NORESERVE: UInt32 = 0x40u32
    @When[os == "Linux" || env == "ohos"]
    public static const MAP_NORESERVE: UInt32 = 0x4000u32

    public static const PROT_NONE: Int32 = 0
    public static const PROT_READ: Int32 = 1
    public static const PROT_WRITE: Int32 = 2
    public static const PROT_EXEC: Int32 = 4
    public static const DEFAULT_MEM_PROT: Int32 = PROT_READ | PROT_WRITE

    // MemMap.h:32 (Windows) and MemMap.h:33 (else). Windows omits MAP_NORESERVE.
    @When[os == "Windows"]
    public static const DEFAULT_MEM_FLAGS: UInt32 = MAP_PRIVATE | MAP_ANONYMOUS
    @When[os != "Windows"]
    public static const DEFAULT_MEM_FLAGS: UInt32 = MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE

    // Windows virtual-memory constants. <winnt.h>.
    @When[os == "Windows"]
    public static const MEM_RESERVE: UInt32 = 0x2000u32
    @When[os == "Windows"]
    public static const MEM_COMMIT: UInt32 = 0x1000u32
    @When[os == "Windows"]
    public static const PAGE_READWRITE: UInt32 = 0x04u32

    // MemMap.h:45. Static bytes give the C++ string literal identical process-lifetime backing storage.
    private static var DEFAULT_OPTIONS_TAG: VArray<UInt8, $14> = [
        109u8, 97u8, 112u8, 108u8, 101u8, 95u8, 117u8,
        110u8, 110u8, 97u8, 109u8, 101u8, 100u8, 0u8
    ]
    public static let DEFAULT_OPTIONS: Option = Option(
        CString(CPointer<UInt8>(inout DEFAULT_OPTIONS_TAG)), CPointer<Unit>(),
        DEFAULT_MEM_FLAGS, DEFAULT_MEM_PROT, false)

    private var memBaseAddr: CPointer<Unit>
    private var memCurrEndAddr: CPointer<Unit>
    private var memMappedEndAddr: CPointer<Unit>
    private var memCurrSize: UIntNative
    private var memMappedSize: UIntNative

    // MemMap.cpp:77-82.
    private init(baseAddr: CPointer<Unit>, initSize: UIntNative, mappedSize: UIntNative) {
        memBaseAddr = baseAddr
        memCurrEndAddr = unsafe { CPointer<Unit>(CPointer<UInt8>(baseAddr) + Int64(initSize)) }
        memMappedEndAddr = unsafe { CPointer<Unit>(CPointer<UInt8>(baseAddr) + Int64(mappedSize)) }
        memCurrSize = initSize
        memMappedSize = mappedSize
    }

    // MemMap.cpp:51-98. Linux/OHOS branch.
    @When[os == "Linux" || env == "ohos"]
    public static func MapMemory(reqSize: UIntNative, initSize: UIntNative,
        opt!: Option = DEFAULT_OPTIONS): CPointer<MemMap> {
        let mappedSize = AllocUtilRndUp(reqSize, UIntNative(ALLOC_UTIL_PAGE_SIZE))
        let mappedAddr = unsafe { mmap(opt.reqBase, mappedSize, PROT_NONE, Int32(opt.flags), -1, 0) }
        if (mappedAddr.toUIntNative() == UIntNative.Max) {
            unsafe { abort() }
        } else {
            unsafe {
                let _ = madvise(mappedAddr, mappedSize, MADV_NOHUGEPAGE)
                MRT_PRCTL(mappedAddr, mappedSize, opt.tag)
            }
            let protSize = if (opt.protAll) { mappedSize } else { initSize }
            if (!ProtectMemInternal(mappedAddr, protSize, opt.prot)) {
                MapMemoryImpl(mappedAddr, mappedSize)
                unsafe { abort() }
            }
        }

        let memMap = CPointer<MemMap>(unsafe { malloc(sizeOf<MemMap>()) })
        if (memMap.isNull()) {
            unsafe { abort() }
        }
        unsafe { memMap.write(0, MemMap(mappedAddr, initSize, mappedSize)) }
        return memMap
    }

    // MemMap.cpp:51-98. Windows branch.
    @When[os == "Windows"]
    public static func MapMemory(reqSize: UIntNative, initSize: UIntNative,
        opt!: Option = DEFAULT_OPTIONS): CPointer<MemMap> {
        let mappedSize = AllocUtilRndUp(reqSize, UIntNative(ALLOC_UTIL_PAGE_SIZE))
        let _ = opt
        let mappedAddr = unsafe { VirtualAlloc(CPointer<Unit>(), mappedSize, MEM_RESERVE, PAGE_READWRITE) }
        if (mappedAddr.isNull()) {
            unsafe { abort() }
        }

        let memMap = CPointer<MemMap>(unsafe { malloc(sizeOf<MemMap>()) })
        if (memMap.isNull()) {
            unsafe { abort() }
        }
        unsafe { memMap.write(0, MemMap(mappedAddr, initSize, mappedSize)) }
        return memMap
    }

    // MemMap.cpp:25-47.
    @When[os == "macOS" || os == "iOS"]
    private static func MapMemoryOnApple(reqBase: CPointer<Unit>, reqSize: UIntNative,
        initSize: UIntNative, opt: Option): CPointer<Unit> {
        if (IsCangjieHeapTag(opt.tag)) {
            let flags = opt.flags & !MAP_NORESERVE
            return unsafe {
                mmap(reqBase, reqSize, opt.prot, Int32(flags), CANGJIE_HEAP_VM_TAG << 24, 0)
            }
        }

        let mappedAddr = unsafe { mmap(reqBase, reqSize, PROT_NONE, Int32(opt.flags), -1, 0) }
        if (mappedAddr.toUIntNative() == UIntNative.Max) {
            return mappedAddr
        }

        let protSize = if (opt.protAll) { reqSize } else { initSize }
        if (!ProtectMemInternal(mappedAddr, protSize, opt.prot)) {
            MapMemoryImpl(mappedAddr, reqSize)
            return CPointer<Unit>(UIntNative.Max)
        }
        return mappedAddr
    }

    // MemMap.cpp:51-98. Apple branch.
    @When[os == "macOS" || os == "iOS"]
    public static func MapMemory(reqSize: UIntNative, initSize: UIntNative,
        opt!: Option = DEFAULT_OPTIONS): CPointer<MemMap> {
        let mappedSize = AllocUtilRndUp(reqSize, UIntNative(ALLOC_UTIL_PAGE_SIZE))
        let mappedAddr = MapMemoryOnApple(opt.reqBase, mappedSize, initSize, opt)
        if (mappedAddr.toUIntNative() == UIntNative.Max) {
            unsafe { abort() }
        }

        let memMap = CPointer<MemMap>(unsafe { malloc(sizeOf<MemMap>()) })
        if (memMap.isNull()) {
            unsafe { abort() }
        }
        unsafe { memMap.write(0, MemMap(mappedAddr, initSize, mappedSize)) }
        return memMap
    }

    // MemMap.h:55-61 and MemMap.cpp:94-100. delete is represented by the authorized raw free.
    public static func DestroyMemMap(memMap: CPointer<CPointer<MemMap>>): Unit {
        let value = unsafe { memMap.read() }
        if (!value.isNull()) {
            var object = unsafe { value.read() }
            let baseAddress = object.memBaseAddr
            let mappedSize = object.memMappedSize
            object.memBaseAddr = CPointer<Unit>()
            object.memCurrEndAddr = CPointer<Unit>()
            object.memMappedEndAddr = CPointer<Unit>()
            unsafe {
                value.write(0, object)
                DestroyMemMapImpl(CPointer<Unit>(value), baseAddress, mappedSize)
                // Mirrors C++ `delete memMap`, i.e. operator delete = free (see the foreign block).
                memMap.write(0, CPointer<MemMap>())
            }
        }
    }

    // MemMap.cpp:69-74. Windows-only: commit reserved pages before first access.
    @When[os == "Windows"]
    public static func CommitMemory(address: CPointer<Unit>, size: UIntNative): Unit {
        let committed = unsafe { VirtualAlloc(address, size, MEM_COMMIT, PAGE_READWRITE) }
        CHECK_E(committed.isNull(),
            "VirtualAlloc commit failed in GetPage, errno: ${unsafe { GetLastError() }}")
    }

    // MemMap.h:63.
    public func GetBaseAddr(): CPointer<Unit> {
        return memBaseAddr
    }

    // MemMap.h:64.
    public func GetCurrEnd(): CPointer<Unit> {
        return memCurrEndAddr
    }

    // MemMap.h:65.
    public func GetMappedEndAddr(): CPointer<Unit> {
        return memMappedEndAddr
    }

    // MemMap.h:66.
    public func GetCurrSize(): UIntNative {
        return memCurrSize
    }

    // MemMap.h:67.
    public func GetMappedSize(): UIntNative {
        return memMappedSize
    }

    // MemMap.cpp:84-93. Windows relies on the reservation protection and never re-protects.
    @When[os != "Windows"]
    private static func ProtectMemInternal(address: CPointer<Unit>, size: UIntNative, prot: Int32): Bool {
        let ret = unsafe { mprotect(address, size, prot) }
        return ret == 0
    }
    @When[os == "Windows"]
    private static func ProtectMemInternal(address: CPointer<Unit>, size: UIntNative, prot: Int32): Bool {
        let _ = address
        let _ = size
        let _ = prot
        return true
    }

    // MemMap.cpp:56 and AllocUtil.h:24-28. Release after failed protection.
    @When[os != "Windows"]
    private static func MapMemoryImpl(address: CPointer<Unit>, size: UIntNative): Unit {
        if (unsafe { munmap(address, size) } != 0) {
            unsafe { abort() }
        }
    }
    @When[os == "Windows"]
    private static func MapMemoryImpl(address: CPointer<Unit>, size: UIntNative): Unit {
        let _ = size
        if (unsafe { VirtualFree(address, 0, 0x8000u32) } == 0) {
            unsafe { abort() }
        }
    }

    // MemMap.cpp:94-100 and MemMap.h:55-60.
    @When[os != "Windows"]
    private static func DestroyMemMapImpl(object: CPointer<Unit>, address: CPointer<Unit>,
        size: UIntNative): Unit {
        if (unsafe { munmap(address, size) } != 0) {
            unsafe { abort() }
        }
        unsafe { free(object) }
    }
    @When[os == "Windows"]
    private static func DestroyMemMapImpl(object: CPointer<Unit>, address: CPointer<Unit>,
        size: UIntNative): Unit {
        let _ = size
        if (unsafe { VirtualFree(address, 0, 0x8000u32) } == 0) {
            unsafe { abort() }
        }
        unsafe { free(object) }
    }
}
