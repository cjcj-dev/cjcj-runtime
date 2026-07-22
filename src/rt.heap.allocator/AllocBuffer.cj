package rt.heap.allocator

foreign {
    // AllocBuffer.h:75 and RegionInfo.h:140-144. This returns the canonical
    // process-lifetime native sentinel used by the mixed C++/Cangjie heap.
    func CJRT_AllocBufferNullRegion(): CPointer<RegionInfo>

    // AllocBuffer.h:30,42-46,77. std::atomic<RegionInfo*> remains an inline
    // native object; the leaf bridge preserves the exact memory orders.
    func CJRT_AllocBufferPreparedConstruct(storage: CPointer<Unit>): Unit
    func CJRT_AllocBufferPreparedLoadRelaxed(storage: CPointer<Unit>): CPointer<RegionInfo>
    func CJRT_AllocBufferPreparedCompareExchangeRelease(storage: CPointer<Unit>,
        desired: CPointer<RegionInfo>): Int32

    // AllocBuffer.h:49-63,83. std::list<BaseObject*> and the not-yet-ported
    // MarkStack<BaseObject*> stay opaque at the Cangjie boundary.
    func CJRT_AllocBufferStackRootsConstruct(storage: CPointer<Unit>): Unit
    func CJRT_AllocBufferStackRootsDestroy(storage: CPointer<Unit>): Unit
    func CJRT_AllocBufferPushRoot(storage: CPointer<Unit>, root: CPointer<Unit>): Unit
    func CJRT_AllocBufferMergeRoots(storage: CPointer<Unit>, workStack: CPointer<Unit>): Unit
}

// AllocBuffer.h:20-21. Both strings have process-lifetime static backing, just
// like the two C++ string literals passed to the embedded RegionList objects.
private var ALLOC_BUFFER_RAW_POINTER_REGIONS_NAME: VArray<UInt8, $33> = [
    116u8, 104u8, 114u8, 101u8, 97u8, 100u8, 45u8, 108u8, 111u8, 99u8,
    97u8, 108u8, 32u8, 114u8, 97u8, 119u8, 45u8, 112u8, 111u8, 105u8,
    110u8, 116u8, 101u8, 114u8, 32u8, 114u8, 101u8, 103u8, 105u8, 111u8,
    110u8, 115u8, 0u8
]

private var ALLOC_BUFFER_LARGE_RAW_POINTER_REGIONS_NAME: VArray<UInt8, $39> = [
    116u8, 104u8, 114u8, 101u8, 97u8, 100u8, 45u8, 108u8, 111u8, 99u8,
    97u8, 108u8, 32u8, 108u8, 97u8, 114u8, 103u8, 101u8, 32u8, 114u8,
    97u8, 119u8, 45u8, 112u8, 111u8, 105u8, 110u8, 116u8, 101u8, 114u8,
    32u8, 114u8, 101u8, 103u8, 105u8, 111u8, 110u8, 115u8, 0u8
]

@When[debug]
private var ALLOC_BUFFER_CLEAR_REGION_LOG: VArray<UInt8, $46> = [
    97u8, 108u8, 108u8, 111u8, 99u8, 32u8, 98u8, 117u8, 102u8, 102u8,
    101u8, 114u8, 32u8, 99u8, 108u8, 101u8, 97u8, 114u8, 32u8, 116u8,
    108u8, 82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 32u8, 37u8, 112u8,
    64u8, 91u8, 48u8, 120u8, 37u8, 122u8, 120u8, 44u8, 32u8, 48u8,
    120u8, 37u8, 122u8, 120u8, 41u8, 0u8
]

@When[os == "Linux" || env == "ohos"]
private const ALLOC_BUFFER_LARGE_REGIONS_OFFSET: Int64 = 96
@When[os == "Linux" || env == "ohos"]
private const ALLOC_BUFFER_STACK_ROOTS_OFFSET: Int64 = 176

// Darwin libc++ uses the 104-byte RegionList selected in RegionList.cj.
@When[os == "macOS" || os == "iOS"]
private const ALLOC_BUFFER_LARGE_REGIONS_OFFSET: Int64 = 120
@When[os == "macOS" || os == "iOS"]
private const ALLOC_BUFFER_STACK_ROOTS_OFFSET: Int64 = 224

// The shipped llvm-mingw libc++ uses the 48-byte RegionList selected in RegionList.cj.
@When[os == "Windows"]
private const ALLOC_BUFFER_LARGE_REGIONS_OFFSET: Int64 = 64
@When[os == "Windows"]
private const ALLOC_BUFFER_STACK_ROOTS_OFFSET: Int64 = 112

// AllocBuffer.h:18-84. The first embedded RegionList starts at offset 16;
// the target-selected RegionList mutex ABI determines the remaining offsets.
// The final three words are opaque inline std::list<BaseObject*> storage.
@C
public struct AllocBuffer {
    var tlRegion: CPointer<RegionInfo>
    var preparedRegion: CPointer<RegionInfo>
    var tlRawPointerRegions: RegionList
    var tlLargeRawPointerRegions: RegionList
    var stackRootsWord0: UIntNative
    var stackRootsWord1: UIntNative
    var stackRootsWord2: UIntNative

    // AllocBuffer.h:20-21,75,77,80-83. This value constructor describes the
    // byte layout; Construct placement-constructs every embedded native object.
    public init() {
        tlRegion = CPointer<RegionInfo>()
        preparedRegion = CPointer<RegionInfo>()
        tlRawPointerRegions = RegionList(CString(CPointer<UInt8>()))
        tlLargeRawPointerRegions = RegionList(CString(CPointer<UInt8>()))
        stackRootsWord0 = 0
        stackRootsWord1 = 0
        stackRootsWord2 = 0
    }

    // AllocBuffer.h:20-21,75,77,80-83. The caller supplies sizeOf<AllocBuffer>()
    // bytes of AS0 native storage. Construction follows C++ data-member order.
    @NoHeapAlloc
    public static func Construct(buffer: CPointer<AllocBuffer>): Unit {
        unsafe {
            CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(buffer)).write(
                0, CJRT_AllocBufferNullRegion())
            CJRT_AllocBufferPreparedConstruct(CPointer<Unit>(CPointer<UInt8>(buffer) + 8))
            RegionList.Construct(CPointer<RegionList>(CPointer<UInt8>(buffer) + 16),
                CString(CPointer<UInt8>(inout ALLOC_BUFFER_RAW_POINTER_REGIONS_NAME)))
            RegionList.Construct(CPointer<RegionList>(CPointer<UInt8>(buffer) +
                ALLOC_BUFFER_LARGE_REGIONS_OFFSET),
                CString(CPointer<UInt8>(inout ALLOC_BUFFER_LARGE_RAW_POINTER_REGIONS_NAME)))
            CJRT_AllocBufferStackRootsConstruct(CPointer<Unit>(CPointer<UInt8>(buffer) +
                ALLOC_BUFFER_STACK_ROOTS_OFFSET))
        }
    }
}

extend CPointer<AllocBuffer> {
    // AllocBuffer.h:29.
    @NoHeapAlloc
    public func GetRegion(): CPointer<RegionInfo> {
        return unsafe {
            CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(this)).read(0)
        }
    }

    // AllocBuffer.h:30. The bridge performs memory_order_relaxed.
    @NoHeapAlloc
    public func GetPreparedRegion(): CPointer<RegionInfo> {
        return unsafe {
            CJRT_AllocBufferPreparedLoadRelaxed(CPointer<Unit>(CPointer<UInt8>(this) + 8))
        }
    }

    // AllocBuffer.h:31.
    @NoHeapAlloc
    public func SetRegion(newRegion: CPointer<RegionInfo>): Unit {
        unsafe {
            CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(this)).write(0, newRegion)
        }
    }

    // AllocBuffer.h:32-40. The debug branch preserves the original REGION
    // WriteLog formatting path; the release branch emits no call.
    @NoHeapAlloc
    public func ClearRegion(): Unit {
        let nullRegion = unsafe { CJRT_AllocBufferNullRegion() }
        if (GetRegion().toUIntNative() == nullRegion.toUIntNative()) {
            return
        }
        AllocBufferClearRegionLog(GetRegion())
        SetRegion(nullRegion)
    }

    // AllocBuffer.h:42-46. The bridge uses a null expected value, a strong CAS,
    // release success ordering, and the standard relaxed failure ordering.
    @NoHeapAlloc
    public func SetPreparedRegion(newPreparedRegion: CPointer<RegionInfo>): Bool {
        return unsafe {
            CJRT_AllocBufferPreparedCompareExchangeRelease(
                CPointer<Unit>(CPointer<UInt8>(this) + 8), newPreparedRegion) != 0
        }
    }

    // AllocBuffer.h:49-50. BaseObject remains an opaque native pointer.
    @NoHeapAlloc
    public func PushRoot(root: CPointer<Unit>): Unit {
        unsafe {
            CJRT_AllocBufferPushRoot(CPointer<Unit>(CPointer<UInt8>(this) +
                ALLOC_BUFFER_STACK_ROOTS_OFFSET), root)
        }
    }

    // AllocBuffer.h:52-63. WorkStack is the deferred Collector marking-layer
    // MarkStack<BaseObject*> specialization, carried as an opaque native pointer.
    @NoHeapAlloc
    public func MergeRoots(workStack: CPointer<Unit>): Unit {
        unsafe {
            CJRT_AllocBufferMergeRoots(CPointer<Unit>(CPointer<UInt8>(this) +
                ALLOC_BUFFER_STACK_ROOTS_OFFSET), workStack)
        }
    }
}

@When[debug]
private func AllocBufferClearRegionLog(region: CPointer<RegionInfo>): Unit {
    let start = region.GetRegionStart()
    unsafe {
        _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz(true, 3,
            CPointer<UInt8>(inout ALLOC_BUFFER_CLEAR_REGION_LOG), region.toUIntNative(),
            start, start + region.GetRegionSize(), 0, 0, 0, 0, 0, 0, 0, 0)
    }
}

@When[!debug]
private func AllocBufferClearRegionLog(region: CPointer<RegionInfo>): Unit {
    let _ = region
}
