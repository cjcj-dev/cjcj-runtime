package rt.heap.allocator

foreign {
    // PagePoolMutex.cpp:10-34. RegionList and PagePool both embed the same
    // production std::mutex object; this bridge placement-constructs and operates
    // on that native object without taking the address of a managed field.
    func CJRT_PagePoolMutexConstruct(storage: CPointer<Unit>): Unit
    func CJRT_PagePoolMutexDestroy(storage: CPointer<Unit>): Unit
    func CJRT_PagePoolMutexLock(storage: CPointer<Unit>): Unit
    func CJRT_PagePoolMutexUnlock(storage: CPointer<Unit>): Unit

    // RegionList.h:115-132. The native handle points to the original
    // std::function<void(RegionInfo*)>; keeping it opaque avoids materializing a
    // managed Cangjie function object on allocator/collector paths.
    func CJRT_RegionListInvokeVisitor(visitor: CPointer<Unit>,
        region: CPointer<RegionInfo>): Unit

}

// RegionList.h:14-212. Linux x86_64 std::mutex is 40 bytes; the remaining
// fields follow it at the exact C++ offsets 40, 48, 56, 64, and 72.
// Production values are placement-constructed in native storage by Construct.
@C
public struct RegionList {
    var mutexWord0: UInt64
    var mutexWord1: UInt64
    var mutexWord2: UInt64
    var mutexWord3: UInt64
    var mutexWord4: UInt64
    var regionCount: UIntNative
    var unitCount: UIntNative
    var listHead: CPointer<RegionInfo>
    var listTail: CPointer<RegionInfo>
    var listName: CString

    // RegionList.h:17 and in-class initializers at :170-174. This constructor
    // describes the value layout only; Construct performs std::mutex placement
    // construction before a native instance is used.
    public init(name: CString) {
        mutexWord0 = 0u64
        mutexWord1 = 0u64
        mutexWord2 = 0u64
        mutexWord3 = 0u64
        mutexWord4 = 0u64
        regionCount = 0
        unitCount = 0
        listHead = CPointer<RegionInfo>()
        listTail = CPointer<RegionInfo>()
        listName = name
    }

    // RegionList.h:17,169-174. The caller supplies AS0 native storage.
    public static func Construct(list: CPointer<RegionList>, name: CString): Unit {
        unsafe {
            CJRT_PagePoolMutexConstruct(CPointer<Unit>(list))
            CPointer<UIntNative>(CPointer<UInt8>(list) + 40).write(0, 0)
            CPointer<UIntNative>(CPointer<UInt8>(list) + 48).write(0, 0)
            CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + 56).write(
                0, CPointer<RegionInfo>())
            CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + 64).write(
                0, CPointer<RegionInfo>())
            CPointer<CString>(CPointer<UInt8>(list) + 72).write(0, name)
        }
    }

    // RegionList.h:14-212. The implicit C++ destructor destroys listMutex.
    public static func Destroy(list: CPointer<RegionList>): Unit {
        unsafe { CJRT_PagePoolMutexDestroy(CPointer<Unit>(list)) }
    }
}

// RegionList.h:214-244. The RegionList base subobject starts at offset zero and
// active follows it at offset 80, matching the C++ derived-object layout.
@C
public struct RegionCache {
    var regionList: RegionList
    var active: Bool

    public init(name: CString) {
        regionList = RegionList(name)
        active = false
    }

    // RegionList.h:216,243.
    public static func Construct(cache: CPointer<RegionCache>, name: CString): Unit {
        RegionList.Construct(CPointer<RegionList>(cache), name)
        unsafe { CPointer<Bool>(CPointer<UInt8>(cache) + 80).write(0, false) }
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

// RegionManager.cpp:157. Static NUL-terminated native name for the temporary
// list used by MergeRegionList.
private var REGION_LIST_CACHE_NAME: VArray<UInt8, $18> = [
    114u8, 101u8, 103u8, 105u8, 111u8, 110u8, 32u8, 108u8, 105u8, 115u8,
    116u8, 32u8, 99u8, 97u8, 99u8, 104u8, 101u8, 0u8
]

private func RegionListAbort(): Unit {
    unsafe { RtFatal(CString(CPointer<UInt8>(inout REGION_LIST_FATAL))) }
}

// Base/Panic.h:18-42. MRT_ASSERT is debug-only in the C++ build.
@When[debug]
private func RegionListAssert(condition: Bool): Unit {
    if (!condition) {
        RegionListAbort()
    }
}

@When[!debug]
private func RegionListAssert(condition: Bool): Unit {
    let _ = condition
}

private func RegionListLock(list: CPointer<RegionList>): Unit {
    unsafe { CJRT_PagePoolMutexLock(CPointer<Unit>(list)) }
}

private func RegionListUnlock(list: CPointer<RegionList>): Unit {
    unsafe { CJRT_PagePoolMutexUnlock(CPointer<Unit>(list)) }
}

private func ReadRegionCount(list: CPointer<RegionList>): UIntNative {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + 40).read(0) }
}

private func WriteRegionCount(list: CPointer<RegionList>, count: UIntNative): Unit {
    unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + 40).write(0, count) }
}

private func ReadUnitCount(list: CPointer<RegionList>): UIntNative {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + 48).read(0) }
}

private func WriteUnitCount(list: CPointer<RegionList>, count: UIntNative): Unit {
    unsafe { CPointer<UIntNative>(CPointer<UInt8>(list) + 48).write(0, count) }
}

private func ReadListHead(list: CPointer<RegionList>): CPointer<RegionInfo> {
    return unsafe {
        CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + 56).read(0)
    }
}

private func WriteListHead(list: CPointer<RegionList>, head: CPointer<RegionInfo>): Unit {
    unsafe {
        CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + 56).write(0, head)
    }
}

private func ReadListTail(list: CPointer<RegionList>): CPointer<RegionInfo> {
    return unsafe {
        CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + 64).read(0)
    }
}

private func WriteListTail(list: CPointer<RegionList>, tail: CPointer<RegionInfo>): Unit {
    unsafe {
        CPointer<CPointer<RegionInfo>>(CPointer<UInt8>(list) + 64).write(0, tail)
    }
}

// RegionInfo.h:886-903. Required RegionList dependency closure over the live
// native RegionInfo record; NULLPTR_IDX is UInt32.Max.
private func GetPrevRegion(region: CPointer<RegionInfo>): CPointer<RegionInfo> {
    let idx = unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 20).read(0) }
    if (idx == UnitInfo.INVALID_IDX) {
        return CPointer<RegionInfo>()
    }
    return CPointer<RegionInfo>(UnitInfo.GetUnitInfo(UIntNative(idx)))
}

private func SetPrevRegion(region: CPointer<RegionInfo>, prev: CPointer<RegionInfo>): Unit {
    if (prev.isNull()) {
        unsafe {
            CPointer<UInt32>(CPointer<UInt8>(region) + 20).write(0, UnitInfo.INVALID_IDX)
        }
        return
    }
    let idx = prev.GetUnitIdx()
    RegionListAssert(idx < UIntNative(UnitInfo.INVALID_IDX))
    unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 20).write(0, UInt32(idx)) }
}

// RegionInfo.h:905-932.
private func GetNextRegion(region: CPointer<RegionInfo>): CPointer<RegionInfo> {
    let idx = unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 16).read(0) }
    if (idx == UnitInfo.INVALID_IDX) {
        return CPointer<RegionInfo>()
    }
    return CPointer<RegionInfo>(UnitInfo.GetUnitInfo(UIntNative(idx)))
}

private func SetNextRegion(region: CPointer<RegionInfo>, next: CPointer<RegionInfo>): Unit {
    if (next.isNull()) {
        unsafe {
            CPointer<UInt32>(CPointer<UInt8>(region) + 16).write(0, UnitInfo.INVALID_IDX)
        }
        return
    }
    let idx = next.GetUnitIdx()
    RegionListAssert(idx < UIntNative(UnitInfo.INVALID_IDX))
    unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 16).write(0, UInt32(idx)) }
}

// RegionInfo.h:914-921.
private func GetNextGhostRegion(region: CPointer<RegionInfo>): CPointer<RegionInfo> {
    let idx = unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 72).read(0) }
    if (idx == UnitInfo.INVALID_IDX) {
        return CPointer<RegionInfo>()
    }
    return CPointer<RegionInfo>(UnitInfo.GetUnitInfo(UIntNative(idx)))
}

// RegionInfo.h:622.
private func GetRegionAllocatedSize(region: CPointer<RegionInfo>): UIntNative {
    return region.GetRegionAllocPtr() - region.GetRegionStart()
}

extend CPointer<RegionList> {
    // RegionList.h:19 and RegionManager.cpp:177-181.
    public func PrependRegion(region: CPointer<RegionInfo>, regionType: RegionType): Unit {
        RegionListLock(this)
        PrependRegionLocked(region, regionType)
        RegionListUnlock(this)
    }

    // RegionList.h:20 and RegionManager.cpp:183-204. Release DLOG is an exact
    // no-op and therefore emits no managed String formatting here.
    public func PrependRegionLocked(region: CPointer<RegionInfo>, regionType: RegionType): Unit {
        if (region.isNull()) {
            return
        }
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

    // RegionList.h:22 and RegionManager.cpp:155-175.
    public func MergeRegionList(srcList: CPointer<RegionList>, regionType: RegionType): Unit {
        let cache = CPointer<RegionList>(unsafe { malloc(80) })
        if (cache.isNull()) {
            RegionListAbort()
        }
        let cacheName = CString(CPointer<UInt8>(inout REGION_LIST_CACHE_NAME))
        RegionList.Construct(cache, cacheName)
        srcList.MoveTo(cache)
        let head = cache.GetHeadRegion()
        let tail = cache.GetTailRegion()
        if (head.isNull()) {
            RegionList.Destroy(cache)
            unsafe { free(CPointer<Unit>(cache)) }
            return
        }
        RegionListLock(this)
        cache.SetElementType(regionType)
        IncCounts(cache.GetRegionCount(), cache.GetUnitCount())
        let listHead = ReadListHead(this)
        if (listHead.isNull()) {
            WriteListHead(this, head)
            WriteListTail(this, tail)
        } else {
            SetNextRegion(tail, listHead)
            SetPrevRegion(listHead, tail)
            WriteListHead(this, head)
        }
        RegionListUnlock(this)
        RegionList.Destroy(cache)
        unsafe { free(CPointer<Unit>(cache)) }
    }

    // RegionList.h:24-32.
    public func DeleteRegion(del: CPointer<RegionInfo>): Unit {
        if (del.isNull()) {
            return
        }
        RegionListLock(this)
        DeleteRegionLocked(del)
        RegionListUnlock(this)
    }

    // RegionList.h:34-48.
    public func TryDeleteRegion(del: CPointer<RegionInfo>, oldType: RegionType,
        newType: RegionType): Bool {
        if (del.isNull()) {
            return false
        }
        if (oldType == newType) {
            RegionListAbort()
        }
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

    // RegionList.h:54-62.
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

    // RegionList.h:64-70.
    public func IncCounts(nRegion: UIntNative, nUnit: UIntNative): Unit {
        let regions = ReadRegionCount(this)
        let units = ReadUnitCount(this)
        if (nRegion > UIntNative.Max - regions || nUnit > UIntNative.Max - units) {
            RegionListAbort()
        }
        WriteRegionCount(this, regions + nRegion)
        WriteUnitCount(this, units + nUnit)
    }

    // RegionList.h:72.
    public func GetHeadRegion(): CPointer<RegionInfo> {
        return ReadListHead(this)
    }

    // RegionList.h:74-80.
    public func ClearList(): Unit {
        WriteListHead(this, CPointer<RegionInfo>())
        WriteListTail(this, CPointer<RegionInfo>())
        WriteRegionCount(this, 0)
        WriteUnitCount(this, 0)
    }

    // RegionList.h:82.
    public func GetTailRegion(): CPointer<RegionInfo> {
        return ReadListTail(this)
    }

    // RegionList.h:84-91.
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

    // RegionList.h:93-101.
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

    // RegionList.h:103.
    public func GetUnitCount(): UIntNative {
        return ReadUnitCount(this)
    }

    // RegionList.h:105.
    public func GetRegionCount(): UIntNative {
        return ReadRegionCount(this)
    }

    // RegionList.h:107-113.
    public func GetAllocatedSize(count!: Bool = false): UIntNative {
        if (!count) {
            return GetUnitCount() * RegionInfo.UNIT_SIZE
        }
        return CountAllocatedSize()
    }

    // RegionList.h:115-125. Save next before invoking the visitor because the
    // visitor is allowed to unlink the current node.
    public func VisitAllRegions(visitor: CPointer<Unit>): Unit {
        RegionListLock(this)
        var node = ReadListHead(this)
        var next = node
        while (!node.isNull()) {
            next = GetNextRegion(node)
            unsafe { CJRT_RegionListInvokeVisitor(visitor, node) }
            node = next
        }
        RegionListUnlock(this)
    }

    // RegionList.h:127-132. Ghost traversal intentionally does not lock.
    public func VisitAllGhostRegions(visitor: CPointer<Unit>): Unit {
        var node = ReadListHead(this)
        while (!node.isNull()) {
            unsafe { CJRT_RegionListInvokeVisitor(visitor, node) }
            node = GetNextGhostRegion(node)
        }
    }

    // RegionList.h:134-140.
    public func SetElementType(regionType: RegionType): Unit {
        RegionListLock(this)
        var node = ReadListHead(this)
        while (!node.isNull()) {
            node.SetRegionType(regionType)
            node = GetNextRegion(node)
        }
        RegionListUnlock(this)
    }

    // RegionList.h:142-148.
    public func ClearTraceRegionFlag(): Unit {
        RegionListLock(this)
        var node = ReadListHead(this)
        while (!node.isNull()) {
            node.SetTraceRegionFlag(0u8)
            node = GetNextRegion(node)
        }
        RegionListUnlock(this)
    }

    // RegionList.h:150.
    public func GetListMutex(): CPointer<Unit> {
        return CPointer<Unit>(this)
    }

    // RegionList.h:152-157.
    public func MoveTo(targetList: CPointer<RegionList>): Unit {
        RegionListLock(this)
        targetList.AssignWith(this)
        ClearList()
        RegionListUnlock(this)
    }

    // RegionList.h:159-166.
    public func CopyListTo(dstList: CPointer<RegionList>): Unit {
        RegionListLock(this)
        WriteListHead(dstList, ReadListHead(this))
        WriteListTail(dstList, ReadListTail(this))
        WriteRegionCount(dstList, ReadRegionCount(this))
        WriteUnitCount(dstList, ReadUnitCount(this))
        RegionListUnlock(this)
    }

    // RegionList.h:176 and RegionManager.cpp:206-243.
    public func DeleteRegionLocked(del: CPointer<RegionInfo>): Unit {
        RegionListAssert(!ReadListHead(this).isNull() && !ReadListTail(this).isNull())
        let prev = GetPrevRegion(del)
        let next = GetNextRegion(del)
        SetNextRegion(del, CPointer<RegionInfo>())
        SetPrevRegion(del, CPointer<RegionInfo>())
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

    // RegionList.h:178-185.
    private func AssignWith(srcList: CPointer<RegionList>): Unit {
        RegionListLock(this)
        WriteListHead(this, ReadListHead(srcList))
        WriteListTail(this, ReadListTail(srcList))
        WriteRegionCount(this, ReadRegionCount(srcList))
        WriteUnitCount(this, ReadUnitCount(srcList))
        RegionListUnlock(this)
    }

    // RegionList.h:187-196.
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
}

extend CPointer<RegionCache> {
    // RegionList.h:218-226.
    public func TryPrependRegion(region: CPointer<RegionInfo>, regionType: RegionType): Bool {
        let list = CPointer<RegionList>(this)
        RegionListLock(list)
        let active = unsafe { CPointer<Bool>(CPointer<UInt8>(this) + 80).read(0) }
        if (active) {
            list.PrependRegionLocked(region, regionType)
            RegionListUnlock(list)
            return true
        }
        RegionListUnlock(list)
        return false
    }

    // RegionList.h:228-232.
    public func ActivateRegionCache(): Unit {
        let list = CPointer<RegionList>(this)
        RegionListLock(list)
        unsafe { CPointer<Bool>(CPointer<UInt8>(this) + 80).write(0, true) }
        RegionListUnlock(list)
    }

    // RegionList.h:234-241.
    public func DeactivateRegionCache(): Unit {
        let list = CPointer<RegionList>(this)
        RegionListLock(list)
        var node = ReadListHead(list)
        while (!node.isNull()) {
            node.SetTraceRegionFlag(0u8)
            node = GetNextRegion(node)
        }
        unsafe { CPointer<Bool>(CPointer<UInt8>(this) + 80).write(0, false) }
        RegionListUnlock(list)
    }
}

// RegionList.h:16,176 and RegionManager.cpp:474-477.
public func RemoveRegionLocked(regionList: CPointer<RegionList>,
    region: CPointer<RegionInfo>): Unit {
    regionList.DeleteRegionLocked(region)
}
