package rt.heap.allocator

import rt.base.*
import rt.sync.MRT_PRCTL

foreign {
    @When[os == "Linux"]
    func mmap(address: CPointer<Unit>, length: UIntNative, prot: Int32, flags: Int32,
        fd: Int32, offset: IntNative): CPointer<Unit>

    @When[os == "Linux"]
    func madvise(address: CPointer<Unit>, length: UIntNative, advice: Int32): Int32

    @When[os == "Linux"]
    func mprotect(address: CPointer<Unit>, length: UIntNative, prot: Int32): Int32

    // TRANSITIONAL: native allocator 未移植，暂用 malloc/free 承载 MemMap 对象
    @When[os == "Linux"]
    func malloc(size: UIntNative): CPointer<Unit>

    // TRANSITIONAL: native allocator 未移植，暂用 malloc/free 承载 MemMap 对象
    @When[os == "Linux"]
    func free(address: CPointer<Unit>): Unit
}

// Heap/Allocator/MemMap.h:37-43.
@C
@When[os == "Linux"]
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
@When[os == "Linux"]
public struct MemMap {
    public static const MAP_PRIVATE: UInt32 = 2u32
    public static const MAP_FIXED: UInt32 = 0x10u32
    public static const MAP_ANONYMOUS: UInt32 = 0x20u32
    public static const MAP_NORESERVE: UInt32 = 0x4000u32
    public static const PROT_NONE: Int32 = 0
    public static const PROT_READ: Int32 = 1
    public static const PROT_WRITE: Int32 = 2
    public static const PROT_EXEC: Int32 = 4
    public static const DEFAULT_MEM_FLAGS: UInt32 = MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE
    public static const DEFAULT_MEM_PROT: Int32 = PROT_READ | PROT_WRITE

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

    // MemMap.cpp:26-67.
    public static func MapMemory(reqSize: UIntNative, initSize: UIntNative,
        opt!: Option = DEFAULT_OPTIONS): CPointer<MemMap> {
        let mappedSize = AllocUtilRndUp(reqSize, UIntNative(ALLOC_UTIL_PAGE_SIZE))
        DLOG(ALLOC, "MemMap::MapMemory size ${mappedSize}")
        let mappedAddr = unsafe {
            mmap(opt.reqBase, mappedSize, PROT_NONE, Int32(opt.flags), -1, 0)
        }

        var failure = false
        if (mappedAddr.toUIntNative() != UIntNative.Max) {
            unsafe {
                let _ = madvise(mappedAddr, mappedSize, MADV_NOHUGEPAGE)
                MRT_PRCTL(mappedAddr, mappedSize, opt.tag)
            }
            let protSize = if (opt.protAll) { mappedSize } else { initSize }
            if (!ProtectMemInternal(mappedAddr, protSize, opt.prot)) {
                failure = true
                LOG(RTLOG_ERROR, "MemMap::MapMemory mprotect failed")
                ALLOCUTIL_MEM_UNMAP(mappedAddr, mappedSize)
            }
        } else {
            failure = true
        }
        CHECK_DETAIL(!failure,
            "MemMap::MapMemory failed reqSize: ${mappedSize} initSize: ${initSize}")

        DLOG(ALLOC, "MemMap::MapMemory size ${mappedSize} successful at ${mappedAddr.toUIntNative()}")
        // TRANSITIONAL: native allocator 未移植，暂用 malloc/free 承载 MemMap 对象
        let memMap = CPointer<MemMap>(unsafe { malloc(sizeOf<MemMap>()) })
        CHECK_DETAIL(!memMap.isNull(), "new MemMap failed")
        unsafe { memMap.write(MemMap(mappedAddr, initSize, mappedSize)) }
        return memMap
    }

    // MemMap.h:55-61 and MemMap.cpp:94-100. delete is represented by the authorized raw free.
    public static func DestroyMemMap(memMap: CPointer<CPointer<MemMap>>): Unit {
        let value = unsafe { memMap.read() }
        if (!value.isNull()) {
            var object = unsafe { value.read() }
            ALLOCUTIL_MEM_UNMAP(object.memBaseAddr, object.memMappedSize)
            object.memBaseAddr = CPointer<Unit>()
            object.memCurrEndAddr = CPointer<Unit>()
            object.memMappedEndAddr = CPointer<Unit>()
            unsafe {
                value.write(object)
                // TRANSITIONAL: native allocator 未移植，暂用 malloc/free 承载 MemMap 对象
                free(CPointer<Unit>(value))
                memMap.write(CPointer<MemMap>())
            }
        }
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

    // MemMap.cpp:84-93.
    private static func ProtectMemInternal(address: CPointer<Unit>, size: UIntNative, prot: Int32): Bool {
        DLOG(ALLOC, "MemMap::ProtectMem ${address.toUIntNative()}, size ${size}, prot ${prot}")
        let ret = unsafe { mprotect(address, size, prot) }
        return ret == 0
    }
}
