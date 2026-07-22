package rt.heap.allocator

foreign {
    func CJRT_FreeRegionManagerVTableAddressPoint(): CPointer<Unit>
    func CJRT_PagePoolMutexTryLock(storage: CPointer<Unit>): Bool
    func CJRT_ScopedEnterSaferegionOnlyMutatorBegin(): Bool
    func CJRT_ScopedEnterSaferegionEnd(stateChanged: Bool): Unit
    func CJRT_FreeRegionReleaseNoneLog(dirtyBytes: UIntNative,
        targetCachedSize: UIntNative): Unit
    func CJRT_FreeRegionReleaseLog(releasedBytes: UIntNative, dirtyBytes: UIntNative,
        targetCachedSize: UIntNative): Unit
}

@When[os == "Linux" || env == "ohos"]
@C
struct FreeRegionMutexStorage {
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

@When[os == "macOS" || os == "iOS"]
@C
struct FreeRegionMutexStorage {
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

@When[os == "Windows"]
@C
struct FreeRegionMutexStorage {
    var word0: UInt64
    public init() { word0 = 0u64 }
}

@When[os == "Linux" || env == "ohos"]
private const FREE_REGION_RELEASED_TREE_OFFSET: Int64 = 56
@When[os == "Linux" || env == "ohos"]
private const FREE_REGION_DIRTY_MUTEX_OFFSET: Int64 = 184
@When[os == "Linux" || env == "ohos"]
private const FREE_REGION_DIRTY_TREE_OFFSET: Int64 = 224

@When[os == "macOS" || os == "iOS"]
private const FREE_REGION_RELEASED_TREE_OFFSET: Int64 = 80
@When[os == "macOS" || os == "iOS"]
private const FREE_REGION_DIRTY_MUTEX_OFFSET: Int64 = 208
@When[os == "macOS" || os == "iOS"]
private const FREE_REGION_DIRTY_TREE_OFFSET: Int64 = 272

@When[os == "Windows"]
private const FREE_REGION_RELEASED_TREE_OFFSET: Int64 = 24
@When[os == "Windows"]
private const FREE_REGION_DIRTY_MUTEX_OFFSET: Int64 = 152
@When[os == "Windows"]
private const FREE_REGION_DIRTY_TREE_OFFSET: Int64 = 160

// FreeRegionManager.h:19-168. The RegionManager reference is represented by
// its native address. Both CartesianTree values and both std::mutex values are
// embedded in original field order with target-selected mutex layout.
@C
public struct FreeRegionManager {
    var vtable: CPointer<Unit>
    var regionManager: CPointer<Unit>
    var releasedUnitTreeMutex: FreeRegionMutexStorage
    var releasedUnitTree: CartesianTree
    var dirtyUnitTreeMutex: FreeRegionMutexStorage
    var dirtyUnitTree: CartesianTree

    public init() {
        vtable = CPointer<Unit>()
        regionManager = CPointer<Unit>()
        releasedUnitTreeMutex = FreeRegionMutexStorage()
        releasedUnitTree = CartesianTree()
        dirtyUnitTreeMutex = FreeRegionMutexStorage()
        dirtyUnitTree = CartesianTree()
    }

    // FreeRegionManager.h:24 and in-class member construction order.
    @NoHeapAlloc
    public static func Construct(manager: CPointer<FreeRegionManager>,
        owner: CPointer<Unit>): Unit {
        unsafe {
            CPointer<CPointer<Unit>>(manager).write(0, CJRT_FreeRegionManagerVTableAddressPoint())
            CPointer<CPointer<Unit>>(CPointer<UInt8>(manager) + 8).write(0, owner)
            CJRT_PagePoolMutexConstruct(CPointer<Unit>(CPointer<UInt8>(manager) + 16))
            CPointer<CartesianTree>(CPointer<UInt8>(manager) +
                FREE_REGION_RELEASED_TREE_OFFSET).write(0, CartesianTree())
            CJRT_PagePoolMutexConstruct(CPointer<Unit>(CPointer<UInt8>(manager) +
                FREE_REGION_DIRTY_MUTEX_OFFSET))
            CPointer<CartesianTree>(CPointer<UInt8>(manager) +
                FREE_REGION_DIRTY_TREE_OFFSET).write(0, CartesianTree())
        }
    }

    // FreeRegionManager.h:26-30. Explicit Fini calls precede reverse member
    // destruction, exactly as in the original destructor.
    @NoHeapAlloc
    public static func Destroy(manager: CPointer<FreeRegionManager>): Unit {
        let released = FreeRegionReleasedTree(manager)
        let dirty = FreeRegionDirtyTree(manager)
        Fini(dirty)
        Fini(released)
        unsafe {
            CJRT_PagePoolMutexDestroy(FreeRegionDirtyMutex(manager))
            CJRT_PagePoolMutexDestroy(FreeRegionReleasedMutex(manager))
        }
    }
}

private var FREE_REGION_MERGE_FATAL: VArray<UInt8, $36> = [
    70u8,114u8,101u8,101u8,82u8,101u8,103u8,105u8,111u8,110u8,77u8,97u8,
    110u8,97u8,103u8,101u8,114u8,32u8,109u8,101u8,114u8,103u8,101u8,32u8,
    105u8,110u8,118u8,97u8,114u8,105u8,97u8,110u8,116u8,0u8,0u8,0u8
]

private func FreeRegionReleasedMutex(manager: CPointer<FreeRegionManager>): CPointer<Unit> {
    return unsafe { CPointer<Unit>(CPointer<UInt8>(manager) + 16) }
}

private func FreeRegionReleasedTree(manager: CPointer<FreeRegionManager>): CPointer<CartesianTree> {
    return unsafe {
        CPointer<CartesianTree>(CPointer<UInt8>(manager) + FREE_REGION_RELEASED_TREE_OFFSET)
    }
}

private func FreeRegionDirtyMutex(manager: CPointer<FreeRegionManager>): CPointer<Unit> {
    return unsafe {
        CPointer<Unit>(CPointer<UInt8>(manager) + FREE_REGION_DIRTY_MUTEX_OFFSET)
    }
}

private func FreeRegionDirtyTree(manager: CPointer<FreeRegionManager>): CPointer<CartesianTree> {
    return unsafe {
        CPointer<CartesianTree>(CPointer<UInt8>(manager) + FREE_REGION_DIRTY_TREE_OFFSET)
    }
}

extend CPointer<FreeRegionManager> {
    private func ReleasedMutex(): CPointer<Unit> {
        return FreeRegionReleasedMutex(this)
    }

    private func ReleasedTree(): CPointer<CartesianTree> {
        return FreeRegionReleasedTree(this)
    }

    private func DirtyMutex(): CPointer<Unit> {
        return FreeRegionDirtyMutex(this)
    }

    private func DirtyTree(): CPointer<CartesianTree> {
        return FreeRegionDirtyTree(this)
    }

    // FreeRegionManager.h:32-36.
    @NoHeapAlloc
    public func Initialize(regionCnt: UIntNative): Unit {
        Init(ReleasedTree(), regionCnt)
        Init(DirtyTree(), regionCnt)
    }

    // FreeRegionManager.h:38-87.
    @NoHeapAlloc
    public func TakeRegion(num: UIntNative, uclass: UnitRole,
        expectPhysicalMem: Bool): CPointer<RegionInfo> {
        var idx: Index = 0u32
        var tryDirtyTree = true
        var tryReleasedTree = true
        while (tryDirtyTree || tryReleasedTree) {
            if (tryDirtyTree && unsafe { CJRT_PagePoolMutexTryLock(DirtyMutex()) }) {
                let dirtyOk = DirtyTree().TakeUnitsLowAddr(UInt32(num),
                    unsafe { CPointer<Index>(inout idx) })
                if (dirtyOk) {
                    RegionInfo.ClearUnits(UIntNative(idx), num)
                    let region = RegionInfo.InitRegion(UIntNative(idx), num, uclass)
                    unsafe { CJRT_PagePoolMutexUnlock(DirtyMutex()) }
                    return region
                }
                tryDirtyTree = false
                unsafe { CJRT_PagePoolMutexUnlock(DirtyMutex()) }
            }
            if (tryReleasedTree && unsafe { CJRT_PagePoolMutexTryLock(ReleasedMutex()) }) {
                let releasedOk = ReleasedTree().TakeUnitsLowAddr(UInt32(num),
                    unsafe { CPointer<Index>(inout idx) })
                if (releasedOk) {
                    FreeRegionCommitMemory(UIntNative(idx), num)
                    let region = RegionInfo.InitRegion(UIntNative(idx), num, uclass)
                    unsafe { CJRT_PagePoolMutexUnlock(ReleasedMutex()) }
                    PrehandleReleasedUnit(expectPhysicalMem, UIntNative(idx), num)
                    return region
                }
                tryReleasedTree = false
                unsafe { CJRT_PagePoolMutexUnlock(ReleasedMutex()) }
            }
            let stateChanged = unsafe { CJRT_ScopedEnterSaferegionOnlyMutatorBegin() }
            unsafe { CJRT_ScopedEnterSaferegionEnd(stateChanged) }
        }
        return CPointer<RegionInfo>()
    }

    // FreeRegionManager.h:89-106.
    @NoHeapAlloc
    public func AddGarbageUnits(idx: Index, num: Count): Unit {
        let stateChanged = unsafe { CJRT_ScopedEnterSaferegionOnlyMutatorBegin() }
        unsafe { CJRT_PagePoolMutexLock(DirtyMutex()) }
        if (!DirtyTree().MergeInsert(idx, num, true)) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout FREE_REGION_MERGE_FATAL))) }
        }
        unsafe {
            CJRT_PagePoolMutexUnlock(DirtyMutex())
            CJRT_ScopedEnterSaferegionEnd(stateChanged)
        }
    }

    @NoHeapAlloc
    public func AddReleaseUnits(idx: Index, num: Count): Unit {
        let stateChanged = unsafe { CJRT_ScopedEnterSaferegionOnlyMutatorBegin() }
        unsafe { CJRT_PagePoolMutexLock(ReleasedMutex()) }
        if (!ReleasedTree().MergeInsert(idx, num, true)) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout FREE_REGION_MERGE_FATAL))) }
        }
        unsafe {
            CJRT_PagePoolMutexUnlock(ReleasedMutex())
            CJRT_ScopedEnterSaferegionEnd(stateChanged)
        }
    }

    // FreeRegionManager.h:108-142.
    @NoHeapAlloc
    public func GetDirtyUnitCount(): Count {
        unsafe { CJRT_PagePoolMutexLock(DirtyMutex()) }
        let count = DirtyTree().GetTotalCount()
        unsafe { CJRT_PagePoolMutexUnlock(DirtyMutex()) }
        return count
    }

    @NoHeapAlloc
    public func GetReleasedUnitCount(): Count {
        unsafe { CJRT_PagePoolMutexLock(ReleasedMutex()) }
        let count = ReleasedTree().GetTotalCount()
        unsafe { CJRT_PagePoolMutexUnlock(ReleasedMutex()) }
        return count
    }

    @NoHeapAlloc
    public func GetReleasedMaxBlock(): Count {
        unsafe { CJRT_PagePoolMutexLock(ReleasedMutex()) }
        let root = ReleasedTree().RootNode()
        let count = if (root.isNull()) { 0u32 } else { root.GetCount() }
        unsafe { CJRT_PagePoolMutexUnlock(ReleasedMutex()) }
        return count
    }

    @NoHeapAlloc
    public func GetDirtyMaxBlock(): Count {
        unsafe { CJRT_PagePoolMutexLock(DirtyMutex()) }
        let root = DirtyTree().RootNode()
        let count = if (root.isNull()) { 0u32 } else { root.GetCount() }
        unsafe { CJRT_PagePoolMutexUnlock(DirtyMutex()) }
        return count
    }

    @NoHeapAlloc
    public func GetReleasedNodeCount(): UIntNative {
        unsafe { CJRT_PagePoolMutexLock(ReleasedMutex()) }
        let count = ReleasedTree().GetNodeCount()
        unsafe { CJRT_PagePoolMutexUnlock(ReleasedMutex()) }
        return count
    }

    @NoHeapAlloc
    public func GetDirtyNodeCount(): UIntNative {
        unsafe { CJRT_PagePoolMutexLock(DirtyMutex()) }
        let count = DirtyTree().GetNodeCount()
        unsafe { CJRT_PagePoolMutexUnlock(DirtyMutex()) }
        return count
    }

    // RegionManager.cpp:278-304.
    @NoHeapAlloc
    public func ReleaseGarbageRegions(targetCachedSize: UIntNative): UIntNative {
        var dirtyBytes = UIntNative(DirtyTree().GetTotalCount()) * RegionInfo.UNIT_SIZE
        if (dirtyBytes <= targetCachedSize) {
            unsafe { CJRT_FreeRegionReleaseNoneLog(dirtyBytes, targetCachedSize) }
            return 0
        }
        var releasedBytes: UIntNative = 0
        while (dirtyBytes > targetCachedSize) {
            unsafe { CJRT_PagePoolMutexLock(DirtyMutex()) }
            let node = DirtyTree().RootNode()
            if (node.isNull()) {
                unsafe { CJRT_PagePoolMutexUnlock(DirtyMutex()) }
                break
            }
            let idx = node.GetIndex()
            let num = node.GetCount()
            DirtyTree().ReleaseRootNode()
            unsafe { CJRT_PagePoolMutexUnlock(DirtyMutex()) }

            unsafe { CJRT_PagePoolMutexLock(ReleasedMutex()) }
            if (!ReleasedTree().MergeInsert(idx, num, true)) {
                unsafe { RtFatal(CString(CPointer<UInt8>(inout FREE_REGION_MERGE_FATAL))) }
            }
            unsafe { CJRT_PagePoolMutexUnlock(ReleasedMutex()) }
            releasedBytes += UIntNative(num) * RegionInfo.UNIT_SIZE
            dirtyBytes = UIntNative(DirtyTree().GetTotalCount()) * RegionInfo.UNIT_SIZE
        }
        unsafe { CJRT_FreeRegionReleaseLog(releasedBytes, dirtyBytes, targetCachedSize) }
        return releasedBytes
    }

    // FreeRegionManager.h:153-158.
    @NoHeapAlloc
    private func PrehandleReleasedUnit(expectPhysicalMem: Bool, idx: UIntNative,
        num: UIntNative): Unit {
        if (expectPhysicalMem) {
            RegionInfo.ClearUnits(idx, num)
        }
    }
}

@When[os == "Windows"]
private func FreeRegionCommitMemory(idx: UIntNative, num: UIntNative): Unit {
    let address = RegionInfo.GetUnitAddress(idx)
    let unitAddress = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(address)) }
    MemMap.CommitMemory(unitAddress, num * RegionInfo.UNIT_SIZE)
}

@When[os != "Windows"]
private func FreeRegionCommitMemory(idx: UIntNative, num: UIntNative): Unit {
    let _ = idx
    let _ = num
}
