package rt.heap.allocator

import rt.base.REGION

foreign {
    // rt0/os/*/PagePoolMutex.cpp and RegionList.h:168-174.
    @When[os == "Linux" || env == "ohos"]
    func CJRT_PagePoolMutexConstruct(storage: CPointer<Unit>): Unit
    @When[os == "Linux" || env == "ohos"]
    func CJRT_PagePoolMutexDestroy(storage: CPointer<Unit>): Unit
    @When[os == "Linux" || env == "ohos"]
    func CJRT_PagePoolMutexLock(storage: CPointer<Unit>): Unit
    @When[os == "Linux" || env == "ohos"]
    func CJRT_PagePoolMutexUnlock(storage: CPointer<Unit>): Unit

    @When[os == "macOS" || os == "iOS"]
    func CJRT_PagePoolMutexConstruct(storage: CPointer<Unit>): Unit
    @When[os == "macOS" || os == "iOS"]
    func CJRT_PagePoolMutexDestroy(storage: CPointer<Unit>): Unit
    @When[os == "macOS" || os == "iOS"]
    func CJRT_PagePoolMutexLock(storage: CPointer<Unit>): Unit
    @When[os == "macOS" || os == "iOS"]
    func CJRT_PagePoolMutexUnlock(storage: CPointer<Unit>): Unit

    @When[os == "Windows"]
    func CJRT_PagePoolMutexConstruct(storage: CPointer<Unit>): Unit
    @When[os == "Windows"]
    func CJRT_PagePoolMutexDestroy(storage: CPointer<Unit>): Unit
    @When[os == "Windows"]
    func CJRT_PagePoolMutexLock(storage: CPointer<Unit>): Unit
    @When[os == "Windows"]
    func CJRT_PagePoolMutexUnlock(storage: CPointer<Unit>): Unit

    // Base/LogFile.h:185-203 and LogFile.cpp:189-195. The fixed declaration
    // lowers the existing C++ variadic ABI without constructing a managed String.
    @When[debug && (os == "Linux" || env == "ohos")]
    func _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz(addPrefix: Bool, logType: Int32,
        format: CPointer<UInt8>, a1: UIntNative, a2: UIntNative, a3: UIntNative,
        a4: UIntNative, a5: UIntNative, a6: UIntNative, a7: UIntNative,
        a8: UIntNative, a9: UIntNative, a10: UIntNative, a11: UIntNative): Unit
    @When[debug && (os == "macOS" || os == "iOS")]
    func _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz(addPrefix: Bool, logType: Int32,
        format: CPointer<UInt8>, a1: UIntNative, a2: UIntNative, a3: UIntNative,
        a4: UIntNative, a5: UIntNative, a6: UIntNative, a7: UIntNative,
        a8: UIntNative, a9: UIntNative, a10: UIntNative, a11: UIntNative): Unit
    @When[debug && os == "Windows"]
    func _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz(addPrefix: Bool, logType: Int32,
        format: CPointer<UInt8>, a1: UIntNative, a2: UIntNative, a3: UIntNative,
        a4: UIntNative, a5: UIntNative, a6: UIntNative, a7: UIntNative,
        a8: UIntNative, a9: UIntNative, a10: UIntNative, a11: UIntNative): Unit
}

// RegionList.h:115-132. The context is the native lowering of a capturing
// std::function visitor and is owned by the caller.
public type RegionListVisitor = CFunc<(CPointer<RegionInfo>, CPointer<Unit>) -> Unit>

@When[os == "Linux" || env == "ohos"]
@C
struct RegionListMutexStorage {
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

// APPLE_ABI_FACTS.md sections 1-4: Darwin libc++ std::mutex is 64/8.
@When[os == "macOS" || os == "iOS"]
@C
struct RegionListMutexStorage {
    var sig: Int64
    var opaque0: UInt64
    var opaque1: UInt64
    var opaque2: UInt64
    var opaque3: UInt64
    var opaque4: UInt64
    var opaque5: UInt64
    var opaque6: UInt64
    public init() {
        sig = 0x32AAABA7
        opaque0 = 0u64
        opaque1 = 0u64
        opaque2 = 0u64
        opaque3 = 0u64
        opaque4 = 0u64
        opaque5 = 0u64
        opaque6 = 0u64
    }
}

// The shipped Win64 target uses llvm-mingw libc++: std::mutex is 8/8.
@When[os == "Windows"]
@C
struct RegionListMutexStorage {
    var word0: UInt64
    public init() { word0 = 0u64 }
}

@When[os == "Linux" || env == "ohos"]
private const REGION_LIST_REGION_COUNT_OFFSET: Int64 = 40
@When[os == "Linux" || env == "ohos"]
private const REGION_LIST_UNIT_COUNT_OFFSET: Int64 = 48
@When[os == "Linux" || env == "ohos"]
private const REGION_LIST_HEAD_OFFSET: Int64 = 56
@When[os == "Linux" || env == "ohos"]
private const REGION_LIST_TAIL_OFFSET: Int64 = 64
@When[os == "Linux" || env == "ohos"]
private const REGION_LIST_NAME_OFFSET: Int64 = 72
@When[os == "Linux" || env == "ohos"]
private const REGION_CACHE_ACTIVE_OFFSET: Int64 = 80

@When[os == "macOS" || os == "iOS"]
private const REGION_LIST_REGION_COUNT_OFFSET: Int64 = 64
@When[os == "macOS" || os == "iOS"]
private const REGION_LIST_UNIT_COUNT_OFFSET: Int64 = 72
@When[os == "macOS" || os == "iOS"]
private const REGION_LIST_HEAD_OFFSET: Int64 = 80
@When[os == "macOS" || os == "iOS"]
private const REGION_LIST_TAIL_OFFSET: Int64 = 88
@When[os == "macOS" || os == "iOS"]
private const REGION_LIST_NAME_OFFSET: Int64 = 96
@When[os == "macOS" || os == "iOS"]
private const REGION_CACHE_ACTIVE_OFFSET: Int64 = 104

@When[os == "Windows"]
private const REGION_LIST_REGION_COUNT_OFFSET: Int64 = 8
@When[os == "Windows"]
private const REGION_LIST_UNIT_COUNT_OFFSET: Int64 = 16
@When[os == "Windows"]
private const REGION_LIST_HEAD_OFFSET: Int64 = 24
@When[os == "Windows"]
private const REGION_LIST_TAIL_OFFSET: Int64 = 32
@When[os == "Windows"]
private const REGION_LIST_NAME_OFFSET: Int64 = 40
@When[os == "Windows"]
private const REGION_CACHE_ACTIVE_OFFSET: Int64 = 48

// RegionList.h:14-212. Field order and target-selected native mutex layout are exact.
@C
public struct RegionList {
    var listMutex: RegionListMutexStorage
    var regionCount: UIntNative
    var unitCount: UIntNative
    var listHead: CPointer<RegionInfo>
    var listTail: CPointer<RegionInfo>
    var listName: CString

    public init(name: CString) {
        listMutex = RegionListMutexStorage()
        regionCount = 0
        unitCount = 0
        listHead = CPointer<RegionInfo>()
        listTail = CPointer<RegionInfo>()
        listName = name
    }

    public static func Construct(list: CPointer<RegionList>, name: CString): Unit {
        unsafe {
            CJRT_PagePoolMutexConstruct(CPointer<Unit>(list))
            CPointer<UIntNative>(CPointer<UInt8>(list) + REGION_LIST_REGION_COUNT_OFFSET).write(0, 0)
            CPointer<UIntNative>(CPointer<UInt8>(list) + REGION_LIST_UNIT_COUNT_OFFSET).write(0, 0)
            CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + REGION_LIST_HEAD_OFFSET).write(
                0, CPointer<RegionInfo>())
            CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + REGION_LIST_TAIL_OFFSET).write(
                0, CPointer<RegionInfo>())
            CPointer<CString>(CPointer<UInt8>(list) + REGION_LIST_NAME_OFFSET).write(0, name)
        }
    }

    public static func Destroy(list: CPointer<RegionList>): Unit {
        unsafe { CJRT_PagePoolMutexDestroy(CPointer<Unit>(list)) }
    }
}

// RegionList.h:214-244. The base subobject begins at offset zero.
@C
public struct RegionCache {
    var regionList: RegionList
    var active: Bool
    public init(name: CString) {
        regionList = RegionList(name)
        active = false
    }
    public static func Construct(cache: CPointer<RegionCache>, name: CString): Unit {
        RegionList.Construct(CPointer<RegionList>(cache), name)
        unsafe { CPointer<Bool>(CPointer<UInt8>(cache) + REGION_CACHE_ACTIVE_OFFSET).write(0, false) }
    }
    public static func Destroy(cache: CPointer<RegionCache>): Unit {
        RegionList.Destroy(CPointer<RegionList>(cache))
    }
}

private var REGION_LIST_FATAL: VArray<UInt8, $29> = [
    82u8, 101u8, 103u8, 105u8, 111u8, 110u8, 76u8, 105u8, 115u8, 116u8,
    32u8, 105u8, 110u8, 118u8, 97u8, 114u8, 105u8, 97u8, 110u8, 116u8,
    32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8, 0u8, 0u8
]
private var REGION_LIST_CACHE_NAME: VArray<UInt8, $18> = [
    114u8, 101u8, 103u8, 105u8, 111u8, 110u8, 32u8, 108u8, 105u8, 115u8,
    116u8, 32u8, 99u8, 97u8, 99u8, 104u8, 101u8, 0u8
]

@When[debug]
private var REGION_LIST_DUMP_HEADER: VArray<UInt8, $20> = [
    100u8, 117u8, 109u8, 112u8, 32u8, 114u8, 101u8, 103u8, 105u8, 111u8,
    110u8, 32u8, 108u8, 105u8, 115u8, 116u8, 32u8, 37u8, 115u8, 0u8
]
@When[debug]
private var REGION_LIST_DUMP_ITEM: VArray<UInt8, $75> = [
    114u8,101u8,103u8,105u8,111u8,110u8,32u8,37u8,112u8,32u8,64u8,91u8,48u8,120u8,37u8,122u8,
    120u8,43u8,37u8,122u8,117u8,44u8,32u8,48u8,120u8,37u8,122u8,120u8,41u8,32u8,117u8,110u8,
    105u8,116u8,115u8,32u8,91u8,37u8,122u8,117u8,43u8,37u8,122u8,117u8,44u8,32u8,37u8,122u8,
    117u8,41u8,32u8,116u8,121u8,112u8,101u8,32u8,37u8,117u8,32u8,112u8,114u8,101u8,118u8,32u8,
    37u8,112u8,32u8,110u8,101u8,120u8,116u8,32u8,37u8,112u8,0u8
]
@When[debug]
private var REGION_LIST_PREPEND_LOG: VArray<UInt8, $77> = [
    108u8,105u8,115u8,116u8,32u8,37u8,112u8,32u8,40u8,37u8,122u8,117u8,44u8,32u8,37u8,122u8,
    117u8,41u8,43u8,40u8,37u8,122u8,117u8,44u8,32u8,37u8,122u8,117u8,41u8,32u8,112u8,114u8,
    101u8,112u8,101u8,110u8,100u8,32u8,114u8,101u8,103u8,105u8,111u8,110u8,32u8,37u8,112u8,64u8,
    91u8,37u8,35u8,122u8,120u8,43u8,37u8,122u8,117u8,44u8,32u8,37u8,35u8,122u8,120u8,41u8,
    32u8,116u8,121u8,112u8,101u8,32u8,37u8,117u8,45u8,62u8,37u8,117u8,0u8
]
@When[debug]
private var REGION_LIST_DELETE_LOG: VArray<UInt8, $72> = [
    108u8,105u8,115u8,116u8,32u8,37u8,112u8,32u8,40u8,37u8,122u8,117u8,44u8,32u8,37u8,122u8,
    117u8,41u8,45u8,40u8,37u8,122u8,117u8,44u8,32u8,37u8,122u8,117u8,41u8,32u8,100u8,101u8,
    108u8,101u8,116u8,101u8,32u8,114u8,101u8,103u8,105u8,111u8,110u8,32u8,37u8,112u8,64u8,91u8,
    37u8,35u8,122u8,120u8,43u8,37u8,122u8,117u8,44u8,32u8,37u8,35u8,122u8,120u8,41u8,32u8,
    116u8,121u8,112u8,101u8,32u8,37u8,117u8,0u8
]

private func RegionListAbort(): Unit {
    unsafe { RtFatal(CString(CPointer<UInt8>(inout REGION_LIST_FATAL))) }
}

@When[debug]
private func RegionListAssert(condition: Bool): Unit {
    if (!condition) { RegionListAbort() }
}
@When[!debug]
private func RegionListAssert(condition: Bool): Unit { let _ = condition }

private func RegionListLock(list: CPointer<RegionList>): Unit {
    unsafe { CJRT_PagePoolMutexLock(CPointer<Unit>(list)) }
}
private func RegionListUnlock(list: CPointer<RegionList>): Unit {
    unsafe { CJRT_PagePoolMutexUnlock(CPointer<Unit>(list)) }
}
private func ReadRegionCount(list: CPointer<RegionList>): UIntNative {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + REGION_LIST_REGION_COUNT_OFFSET).read(0) }
}
private func WriteRegionCount(list: CPointer<RegionList>, value: UIntNative): Unit {
    unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + REGION_LIST_REGION_COUNT_OFFSET).write(0, value) }
}
private func ReadUnitCount(list: CPointer<RegionList>): UIntNative {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + REGION_LIST_UNIT_COUNT_OFFSET).read(0) }
}
private func WriteUnitCount(list: CPointer<RegionList>, value: UIntNative): Unit {
    unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + REGION_LIST_UNIT_COUNT_OFFSET).write(0, value) }
}
private func ReadListHead(list: CPointer<RegionList>): CPointer<RegionInfo> {
    return unsafe { CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + REGION_LIST_HEAD_OFFSET).read(0) }
}
private func WriteListHead(list: CPointer<RegionList>, value: CPointer<RegionInfo>): Unit {
    unsafe { CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + REGION_LIST_HEAD_OFFSET).write(0, value) }
}
private func ReadListTail(list: CPointer<RegionList>): CPointer<RegionInfo> {
    return unsafe { CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + REGION_LIST_TAIL_OFFSET).read(0) }
}
private func WriteListTail(list: CPointer<RegionList>, value: CPointer<RegionInfo>): Unit {
    unsafe { CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + REGION_LIST_TAIL_OFFSET).write(0, value) }
}

// RegionInfo.h:886-932. next/prev indices are UInt32 with NULLPTR_IDX sentinel.
private func GetPrevRegion(region: CPointer<RegionInfo>): CPointer<RegionInfo> {
    let idx = unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 20).read(0) }
    if (idx == UnitInfo.INVALID_IDX) { return CPointer<RegionInfo>() }
    return CPointer<RegionInfo>(UnitInfo.GetUnitInfo(UIntNative(idx)))
}
private func SetPrevRegion(region: CPointer<RegionInfo>, prev: CPointer<RegionInfo>): Unit {
    if (prev.isNull()) {
        unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 20).write(0, UnitInfo.INVALID_IDX) }
        return
    }
    let idx = prev.GetUnitIdx()
    RegionListAssert(idx < UIntNative(UnitInfo.INVALID_IDX))
    unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 20).write(0, UInt32(idx)) }
}
private func GetNextRegion(region: CPointer<RegionInfo>): CPointer<RegionInfo> {
    let idx = unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 16).read(0) }
    if (idx == UnitInfo.INVALID_IDX) { return CPointer<RegionInfo>() }
    return CPointer<RegionInfo>(UnitInfo.GetUnitInfo(UIntNative(idx)))
}
private func SetNextRegion(region: CPointer<RegionInfo>, next: CPointer<RegionInfo>): Unit {
    if (next.isNull()) {
        unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 16).write(0, UnitInfo.INVALID_IDX) }
        return
    }
    let idx = next.GetUnitIdx()
    RegionListAssert(idx < UIntNative(UnitInfo.INVALID_IDX))
    unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 16).write(0, UInt32(idx)) }
}
private func GetNextGhostRegion(region: CPointer<RegionInfo>): CPointer<RegionInfo> {
    let idx = unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 72).read(0) }
    if (idx == UnitInfo.INVALID_IDX) { return CPointer<RegionInfo>() }
    return CPointer<RegionInfo>(UnitInfo.GetUnitInfo(UIntNative(idx)))
}
private func GetRegionAllocatedSize(region: CPointer<RegionInfo>): UIntNative {
    return region.GetRegionAllocPtr() - region.GetRegionStart()
}

@When[debug]
private func RegionListWriteLog(format: CPointer<UInt8>, a1: UIntNative, a2: UIntNative,
    a3: UIntNative, a4: UIntNative, a5: UIntNative, a6: UIntNative, a7: UIntNative,
    a8: UIntNative, a9: UIntNative, a10: UIntNative, a11: UIntNative): Unit {
    unsafe {
        _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz(true, REGION, format,
            a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11)
    }
}

@When[debug]
private func RegionListPrependLog(list: CPointer<RegionList>, region: CPointer<RegionInfo>,
    regionType: RegionType): Unit {
    RegionListWriteLog(CPointer<UInt8>(inout REGION_LIST_PREPEND_LOG), list.toUIntNative(),
        ReadRegionCount(list), ReadUnitCount(list), 1, region.GetUnitCount(), region.toUIntNative(),
        region.GetRegionStart(), GetRegionAllocatedSize(region),
        region.GetRegionStart() + region.GetRegionSize(), UIntNative(region.GetRegionType()),
        UIntNative(regionType))
}
@When[!debug]
private func RegionListPrependLog(list: CPointer<RegionList>, region: CPointer<RegionInfo>,
    regionType: RegionType): Unit {
    let _ = list
    let _ = region
    let _ = regionType
}

@When[debug]
private func RegionListDeleteLog(list: CPointer<RegionList>, region: CPointer<RegionInfo>): Unit {
    RegionListWriteLog(CPointer<UInt8>(inout REGION_LIST_DELETE_LOG), list.toUIntNative(),
        ReadRegionCount(list), ReadUnitCount(list), 1, region.GetUnitCount(), region.toUIntNative(),
        region.GetRegionStart(), GetRegionAllocatedSize(region),
        region.GetRegionStart() + region.GetRegionSize(), UIntNative(region.GetRegionType()), 0)
}
@When[!debug]
private func RegionListDeleteLog(list: CPointer<RegionList>, region: CPointer<RegionInfo>): Unit {
    let _ = list
    let _ = region
}

extend CPointer<RegionList> {
    // RegionList.h:19-20; RegionManager.cpp:177-204.
    public func PrependRegion(region: CPointer<RegionInfo>, regionType: RegionType): Unit {
        RegionListLock(this)
        PrependRegionLocked(region, regionType)
        RegionListUnlock(this)
    }
    public func PrependRegionLocked(region: CPointer<RegionInfo>, regionType: RegionType): Unit {
        if (region.isNull()) { return }
        RegionListPrependLog(this, region, regionType)
        region.SetRegionType(regionType)
        SetPrevRegion(region, CPointer<RegionInfo>())
        IncCounts(1, region.GetUnitCount())
        let head = ReadListHead(this)
        SetNextRegion(region, head)
        if (head.isNull()) {
            RegionListAssert(ReadListTail(this).isNull())
            WriteListTail(this, region)
        } else {
            SetPrevRegion(head, region)
        }
        WriteListHead(this, region)
    }

    // RegionList.h:22; RegionManager.cpp:155-175.
    public func MergeRegionList(srcList: CPointer<RegionList>, regionType: RegionType): Unit {
        let cacheName = CString(CPointer<UInt8>(inout REGION_LIST_CACHE_NAME))
        var cacheValue = RegionList(cacheName)
        let cache = unsafe { CPointer<RegionList>(inout cacheValue) }
        RegionList.Construct(cache, cacheName)
        srcList.MoveTo(cache)
        let head = cache.GetHeadRegion()
        let tail = cache.GetTailRegion()
        if (head.isNull()) {
            RegionList.Destroy(cache)
            return
        }
        RegionListLock(this)
        cache.SetElementType(regionType)
        IncCounts(cache.GetRegionCount(), cache.GetUnitCount())
        let currentHead = ReadListHead(this)
        if (currentHead.isNull()) {
            WriteListHead(this, head)
            WriteListTail(this, tail)
        } else {
            SetNextRegion(tail, currentHead)
            SetPrevRegion(currentHead, tail)
            WriteListHead(this, head)
        }
        RegionListUnlock(this)
        RegionList.Destroy(cache)
    }

    // RegionList.h:24-48.
    public func DeleteRegion(del: CPointer<RegionInfo>): Unit {
        if (del.isNull()) { return }
        RegionListLock(this)
        DeleteRegionLocked(del)
        RegionListUnlock(this)
    }
    public func TryDeleteRegion(del: CPointer<RegionInfo>, oldType: RegionType,
        newType: RegionType): Bool {
        if (del.isNull()) { return false }
        if (oldType == newType) { RegionListAbort() }
        RegionListLock(this)
        if (del.GetRegionType() == oldType) {
            DeleteRegionLocked(del)
            del.SetRegionType(newType)
            RegionListUnlock(this)
            return true
        }
        RegionListUnlock(this)
        return false
    }

    // RegionList.h:54-70.
    public func DecCounts(nRegion: UIntNative, nUnit: UIntNative): Unit {
        let regions = ReadRegionCount(this)
        let units = ReadUnitCount(this)
        if (regions >= nRegion && units >= nUnit) {
            WriteRegionCount(this, regions - nRegion)
            WriteUnitCount(this, units - nUnit)
        } else {
            RegionListAbort()
        }
    }
    public func IncCounts(nRegion: UIntNative, nUnit: UIntNative): Unit {
        let regions = ReadRegionCount(this)
        let units = ReadUnitCount(this)
        if (nRegion > UIntNative.Max - regions || nUnit > UIntNative.Max - units) {
            RegionListAbort()
        }
        WriteRegionCount(this, regions + nRegion)
        WriteUnitCount(this, units + nUnit)
    }

    public func GetHeadRegion(): CPointer<RegionInfo> { return ReadListHead(this) }
    public func ClearList(): Unit {
        WriteListHead(this, CPointer<RegionInfo>())
        WriteListTail(this, CPointer<RegionInfo>())
        WriteRegionCount(this, 0)
        WriteUnitCount(this, 0)
    }
    public func GetTailRegion(): CPointer<RegionInfo> { return ReadListTail(this) }

    // RegionList.h:84-101.
    public func TakeHeadRegion(): CPointer<RegionInfo> {
        RegionListLock(this)
        let head = ReadListHead(this)
        if (head.isNull()) {
            RegionListUnlock(this)
            return CPointer<RegionInfo>()
        }
        DeleteRegionLocked(head)
        RegionListUnlock(this)
        return head
    }
    public func TakeHeadRegion(newType: RegionType): CPointer<RegionInfo> {
        RegionListLock(this)
        let head = ReadListHead(this)
        if (head.isNull()) {
            RegionListUnlock(this)
            return CPointer<RegionInfo>()
        }
        DeleteRegionLocked(head)
        head.SetRegionType(newType)
        RegionListUnlock(this)
        return head
    }

    public func GetUnitCount(): UIntNative { return ReadUnitCount(this) }
    public func GetRegionCount(): UIntNative { return ReadRegionCount(this) }
    public func GetAllocatedSize(count!: Bool = false): UIntNative {
        if (!count) { return GetUnitCount() * RegionInfo.UNIT_SIZE }
        return CountAllocatedSize()
    }

    // RegionList.h:115-132.
    public func VisitAllRegions(visitor: RegionListVisitor, ctx: CPointer<Unit>): Unit {
        RegionListLock(this)
        var node = ReadListHead(this)
        while (!node.isNull()) {
            let next = GetNextRegion(node)
            unsafe { visitor(node, ctx) }
            node = next
        }
        RegionListUnlock(this)
    }
    public func VisitAllGhostRegions(visitor: RegionListVisitor, ctx: CPointer<Unit>): Unit {
        var node = ReadListHead(this)
        while (!node.isNull()) {
            unsafe { visitor(node, ctx) }
            node = GetNextGhostRegion(node)
        }
    }

    // RegionList.h:134-166.
    public func SetElementType(regionType: RegionType): Unit {
        RegionListLock(this)
        var node = ReadListHead(this)
        while (!node.isNull()) {
            node.SetRegionType(regionType)
            node = GetNextRegion(node)
        }
        RegionListUnlock(this)
    }
    public func ClearTraceRegionFlag(): Unit {
        RegionListLock(this)
        var node = ReadListHead(this)
        while (!node.isNull()) {
            node.SetTraceRegionFlag(0u8)
            node = GetNextRegion(node)
        }
        RegionListUnlock(this)
    }
    public func GetListMutex(): CPointer<Unit> { return CPointer<Unit>(this) }
    public func MoveTo(targetList: CPointer<RegionList>): Unit {
        RegionListLock(this)
        targetList.AssignWith(this)
        ClearList()
        RegionListUnlock(this)
    }
    public func CopyListTo(dstList: CPointer<RegionList>): Unit {
        RegionListLock(this)
        WriteListHead(dstList, ReadListHead(this))
        WriteListTail(dstList, ReadListTail(this))
        WriteRegionCount(dstList, ReadRegionCount(this))
        WriteUnitCount(dstList, ReadUnitCount(this))
        RegionListUnlock(this)
    }

    // RegionList.h:176; RegionManager.cpp:206-243.
    public func DeleteRegionLocked(del: CPointer<RegionInfo>): Unit {
        RegionListAssert(!ReadListHead(this).isNull() && !ReadListTail(this).isNull())
        let prev = GetPrevRegion(del)
        let next = GetNextRegion(del)
        SetNextRegion(del, CPointer<RegionInfo>())
        SetPrevRegion(del, CPointer<RegionInfo>())
        RegionListDeleteLog(this, del)
        DecCounts(1, del.GetUnitCount())
        if (ReadListHead(this).toUIntNative() == del.toUIntNative()) {
            RegionListAssert(prev.isNull())
            WriteListHead(this, next)
            if (ReadListHead(this).isNull()) {
                WriteListTail(this, CPointer<RegionInfo>())
                return
            }
        } else {
            SetNextRegion(prev, next)
        }
        if (ReadListTail(this).toUIntNative() == del.toUIntNative()) {
            RegionListAssert(next.isNull())
            WriteListTail(this, prev)
            if (ReadListTail(this).isNull()) {
                WriteListHead(this, CPointer<RegionInfo>())
                return
            }
        } else {
            SetPrevRegion(next, prev)
        }
    }

    private func AssignWith(srcList: CPointer<RegionList>): Unit {
        RegionListLock(this)
        WriteListHead(this, ReadListHead(srcList))
        WriteListTail(this, ReadListTail(srcList))
        WriteRegionCount(this, ReadRegionCount(srcList))
        WriteUnitCount(this, ReadUnitCount(srcList))
        RegionListUnlock(this)
    }
    private func CountAllocatedSize(): UIntNative {
        var allocated: UIntNative = 0
        RegionListLock(this)
        var region = ReadListHead(this)
        while (!region.isNull()) {
            allocated += GetRegionAllocatedSize(region)
            region = GetNextRegion(region)
        }
        RegionListUnlock(this)
        return allocated
    }

    // RegionList.h:50-52; RegionManager.cpp:245-257.
    @When[debug]
    public func DumpRegionList(message: CPointer<UInt8>): Unit {
        RegionListWriteLog(CPointer<UInt8>(inout REGION_LIST_DUMP_HEADER),
            message.toUIntNative(), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        RegionListLock(this)
        var region = ReadListHead(this)
        while (!region.isNull()) {
            RegionListWriteLog(CPointer<UInt8>(inout REGION_LIST_DUMP_ITEM), region.toUIntNative(),
                region.GetRegionStart(), GetRegionAllocatedSize(region),
                region.GetRegionStart() + region.GetRegionSize(), region.GetUnitIdx(),
                region.GetUnitCount(), region.GetUnitIdx() + region.GetUnitCount(),
                UIntNative(region.GetRegionType()), GetPrevRegion(region).toUIntNative(),
                GetNextRegion(region).toUIntNative(), 0)
            region = GetNextRegion(region)
        }
        RegionListUnlock(this)
    }

    // RegionList.h:198-211.
    @When[debug]
    private func VerifyRegion(region: CPointer<RegionInfo>): Unit {
        let prev = GetPrevRegion(region)
        let next = GetNextRegion(region)
        if (!prev.isNull() && GetNextRegion(prev).toUIntNative() != region.toUIntNative()) {
            RegionListAbort()
        }
        if (!next.isNull() && GetPrevRegion(next).toUIntNative() != region.toUIntNative()) {
            RegionListAbort()
        }
    }
}

extend CPointer<RegionCache> {
    // RegionList.h:218-241.
    public func TryPrependRegion(region: CPointer<RegionInfo>, regionType: RegionType): Bool {
        let list = CPointer<RegionList>(this)
        RegionListLock(list)
        let active = unsafe { CPointer<Bool>(CPointer<UInt8>(this) + REGION_CACHE_ACTIVE_OFFSET).read(0) }
        if (active) {
            list.PrependRegionLocked(region, regionType)
            RegionListUnlock(list)
            return true
        }
        RegionListUnlock(list)
        return false
    }
    public func ActivateRegionCache(): Unit {
        let list = CPointer<RegionList>(this)
        RegionListLock(list)
        unsafe { CPointer<Bool>(CPointer<UInt8>(this) + REGION_CACHE_ACTIVE_OFFSET).write(0, true) }
        RegionListUnlock(list)
    }
    public func DeactivateRegionCache(): Unit {
        let list = CPointer<RegionList>(this)
        RegionListLock(list)
        var node = ReadListHead(list)
        while (!node.isNull()) {
            node.SetTraceRegionFlag(0u8)
            node = GetNextRegion(node)
        }
        unsafe { CPointer<Bool>(CPointer<UInt8>(this) + REGION_CACHE_ACTIVE_OFFSET).write(0, false) }
        RegionListUnlock(list)
    }
}

// RegionList.h:16,176 and RegionManager.cpp:474-477.
public func RemoveRegionLocked(regionList: CPointer<RegionList>,
    region: CPointer<RegionInfo>): Unit {
    regionList.DeleteRegionLocked(region)
}
