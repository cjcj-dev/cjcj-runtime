package rt.gc.forwarddata

import rt.base.*
import rt.gc.*
import rt.heap.allocator.*
import rt.sync.*
import std.overflow.*

foreign {
    @When[os != "Windows"]
    func mmap(address: CPointer<Unit>, length: UIntNative, prot: Int32, flags: Int32,
        fd: Int32, offset: IntNative): CPointer<Unit>
    @When[os != "Windows"]
    func munmap(address: CPointer<Unit>, length: UIntNative): Int32
    @When[os == "Linux" || env == "ohos"]
    func madvise(address: CPointer<Unit>, length: UIntNative, advice: Int32): Int32
    @When[os == "Windows"]
    func VirtualAlloc(address: CPointer<Unit>, size: UIntNative, allocationType: UInt32,
        protect: UInt32): CPointer<Unit>
    @When[os == "Windows"]
    func VirtualFree(address: CPointer<Unit>, size: UIntNative, freeType: UInt32): Int32
    func memset(destination: CPointer<Unit>, value: Int32, count: UIntNative): CPointer<Unit>
    func write(fd: Int32, data: CPointer<UInt8>, size: UIntNative): IntNative
    func abort(): Unit

    func cj_atomic_uintptr_fetch_add_seq_cst(p: CPointer<UIntNative>, value: UIntNative): UIntNative
    func cj_atomic_uintptr_load_seq_cst(p: CPointer<UIntNative>): UIntNative
    @When[os == "Windows"]
    func cj_atomic_uintptr_load_relaxed(p: CPointer<UIntNative>): UIntNative
    func cj_atomic_uintptr_store_seq_cst(p: CPointer<UIntNative>, value: UIntNative): Unit

    // Existing C++ production owner; no bridge ABI is introduced.
    func _ZN12MapleRuntime4Heap7GetHeapEv(): CPointer<Unit>
    func _ZNK12MapleRuntime8HeapImpl14GetMaxCapacityEv(heap: CPointer<Unit>): UIntNative
}

private const LIVE_INFO_ZONE: UIntNative = 0
private const BIT_MAP_ZONE: UIntNative = 1
private const FORWARD_ZONE_COUNT: UIntNative = 2

// ForwardDataManager.h:36-44. std::atomic<uintptr_t> is one caller-owned word.
@C
public struct ForwardDataZone {
    public var zoneStartAddress: UIntNative
    public var zonePosition: UIntNative

    public init() {
        zoneStartAddress = 0
        zonePosition = 0
    }
}

// ForwardDataManager.h:34-128. Target-only members preserve the three C++ layouts.
@When[os != "Windows"]
@C
public struct ForwardDataSpace {
    public var allocZone: VArray<ForwardDataZone, $2>
    public var startAddress: UIntNative
    public var size: UIntNative

    public init() {
        allocZone = VArray<ForwardDataZone, $2>(repeat: ForwardDataZone())
        startAddress = 0
        size = 0
    }
}

@When[os == "Windows"]
@C
public struct ForwardDataSpace {
    public var allocZone: VArray<ForwardDataZone, $2>
    public var startAddress: UIntNative
    public var size: UIntNative
    public var lastCommitEndAddr: VArray<UIntNative, $2>
    public var allocSpinLock: AtomicSpinLock

    public init() {
        allocZone = VArray<ForwardDataZone, $2>(repeat: ForwardDataZone())
        startAddress = 0
        size = 0
        lastCommitEndAddr = VArray<UIntNative, $2>(repeat: 0)
        allocSpinLock = AtomicSpinLock()
    }
}

@When[os != "Windows"]
@C
public struct ForwardDataManager {
    public var liveInfoData: VArray<ForwardDataSpace, $2>
    public var regionUnitCount: UIntNative
    public var forwardDataStart: UIntNative
    public var forwardDataSize: UIntNative
    public var currentTagID: UInt16

    public init() {
        liveInfoData = VArray<ForwardDataSpace, $2>(repeat: ForwardDataSpace())
        regionUnitCount = 0
        forwardDataStart = 0
        forwardDataSize = 0
        currentTagID = 0u16
    }
}

@When[os == "Windows"]
@C
public struct ForwardDataManager {
    public var liveInfoData: VArray<ForwardDataSpace, $2>
    public var regionUnitCount: UIntNative
    public var forwardDataStart: UIntNative
    public var forwardDataSize: UIntNative
    public var currentTagID: UInt16

    public init() {
        liveInfoData = VArray<ForwardDataSpace, $2>(repeat: ForwardDataSpace())
        regionUnitCount = 0
        forwardDataStart = 0
        forwardDataSize = 0
        currentTagID = 0u16
    }
}

private var forwardDataManager: ForwardDataManager = ForwardDataManager()
private var FORWARD_DATA_NAME: VArray<UInt8, $13> = [
    102u8, 111u8, 114u8, 119u8, 97u8, 114u8, 100u8, 95u8, 100u8, 97u8, 116u8, 97u8, 0u8
]
private var FORWARD_DATA_ERRORS: VArray<UInt8, $247> = [
    86u8, 105u8, 114u8, 116u8, 117u8, 97u8, 108u8, 65u8, 108u8, 108u8, 111u8, 99u8, 32u8, 99u8, 111u8, 109u8,
    109u8, 105u8, 116u8, 32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8, 32u8, 105u8, 110u8, 32u8, 65u8, 108u8,
    108u8, 111u8, 99u8, 97u8, 116u8, 101u8, 10u8,
    86u8, 105u8, 114u8, 116u8, 117u8, 97u8, 108u8, 70u8, 114u8, 101u8, 101u8, 32u8, 102u8, 97u8, 105u8, 108u8,
    101u8, 100u8, 32u8, 105u8, 110u8, 32u8, 82u8, 101u8, 116u8, 117u8, 114u8, 110u8, 80u8, 97u8, 103u8, 101u8,
    10u8,
    102u8, 111u8, 114u8, 119u8, 97u8, 114u8, 100u8, 105u8, 110u8, 103u8, 32u8, 102u8, 97u8, 116u8, 97u8, 32u8,
    109u8, 109u8, 97u8, 112u8, 32u8, 105u8, 120u8, 101u8, 100u8, 32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8,
    10u8,
    109u8, 109u8, 97u8, 112u8, 32u8, 102u8, 105u8, 120u8, 101u8, 100u8, 32u8, 97u8, 116u8, 32u8, 119u8, 114u8,
    111u8, 110u8, 103u8, 32u8, 97u8, 100u8, 100u8, 114u8, 10u8,
    109u8, 117u8, 110u8, 109u8, 97u8, 112u8, 32u8, 101u8, 114u8, 114u8, 111u8, 114u8, 32u8, 102u8, 111u8, 114u8,
    32u8, 70u8, 111u8, 114u8, 119u8, 97u8, 114u8, 100u8, 68u8, 97u8, 116u8, 97u8, 77u8, 97u8, 110u8, 97u8,
    103u8, 101u8, 114u8, 10u8,
    86u8, 105u8, 114u8, 116u8, 117u8, 97u8, 108u8, 70u8, 114u8, 101u8, 101u8, 32u8, 101u8, 114u8, 114u8, 111u8,
    114u8, 32u8, 102u8, 111u8, 114u8, 32u8, 70u8, 111u8, 114u8, 119u8, 97u8, 114u8, 100u8, 68u8, 97u8, 116u8,
    97u8, 77u8, 97u8, 110u8, 97u8, 103u8, 101u8, 114u8, 10u8,
    102u8, 97u8, 105u8, 108u8, 101u8, 100u8, 32u8, 116u8, 111u8, 32u8, 105u8, 110u8, 105u8, 116u8, 105u8, 97u8,
    108u8, 105u8, 122u8, 101u8, 32u8, 70u8, 111u8, 114u8, 119u8, 97u8, 114u8, 100u8, 68u8, 97u8, 116u8, 97u8,
    77u8, 97u8, 110u8, 97u8, 103u8, 101u8, 114u8, 10u8
]

@NoHeapAlloc
private func ForwardDataError(offset: Int64, size: UIntNative): Unit {
    unsafe { let _ = write(2, CPointer<UInt8>(inout FORWARD_DATA_ERRORS) + offset, size) }
}

@NoHeapAlloc
public func GetForwardDataManager(): CPointer<ForwardDataManager> {
    return unsafe { CPointer<ForwardDataManager>(inout forwardDataManager) }
}

private func ZoneAddress(space: CPointer<ForwardDataSpace>, index: UIntNative): CPointer<ForwardDataZone> {
    return unsafe { CPointer<ForwardDataZone>(CPointer<UInt8>(space) + Int64(index * 16)) }
}

@When[os == "Windows"]
private func LastCommitAddress(space: CPointer<ForwardDataSpace>, index: UIntNative): CPointer<UIntNative> {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(space) + Int64(48 + index * 8)) }
}

@When[os != "Windows"]
private func SetLastCommit(space: CPointer<ForwardDataSpace>, index: UIntNative,
    value: UIntNative): Unit {
    let _ = space
    let _ = index
    let _ = value
}

@When[os == "Windows"]
private func SetLastCommit(space: CPointer<ForwardDataSpace>, index: UIntNative,
    value: UIntNative): Unit {
    unsafe { cj_atomic_uintptr_store_seq_cst(LastCommitAddress(space, index), value) }
}

@NoHeapAlloc
public func ForwardDataSpaceInitialize(space: CPointer<ForwardDataSpace>, start: UIntNative,
    size: UIntNative, unitCount: UIntNative): Unit {
    unsafe {
        CPointer<UIntNative>(CPointer<UInt8>(space) + 32).write(0, start)
        CPointer<UIntNative>(CPointer<UInt8>(space) + 40).write(0, size)
    }
    var cursor = start
    let live = ZoneAddress(space, LIVE_INFO_ZONE)
    unsafe {
        CPointer<UIntNative>(live).write(0, cursor)
        cj_atomic_uintptr_store_seq_cst(CPointer<UIntNative>(CPointer<UInt8>(live) + 8), cursor)
    }
    SetLastCommit(space, LIVE_INFO_ZONE, cursor)
    cursor = cursor.wrappingAdd(unitCount.wrappingMul(sizeOf<LiveInfo>()))
    let bitmap = ZoneAddress(space, BIT_MAP_ZONE)
    unsafe {
        CPointer<UIntNative>(bitmap).write(0, cursor)
        cj_atomic_uintptr_store_seq_cst(CPointer<UIntNative>(CPointer<UInt8>(bitmap) + 8), cursor)
    }
    SetLastCommit(space, BIT_MAP_ZONE, cursor)
}

@When[os != "Windows"]
@NoHeapAlloc
public func ForwardDataSpaceAllocate(space: CPointer<ForwardDataSpace>, zone: UIntNative,
    size: UIntNative): UIntNative {
    let value = ZoneAddress(space, zone)
    return unsafe {
        cj_atomic_uintptr_fetch_add_seq_cst(CPointer<UIntNative>(CPointer<UInt8>(value) + 8), size)
    }
}

@When[os == "Windows"]
@NoHeapAlloc
public func ForwardDataSpaceAllocate(space: CPointer<ForwardDataSpace>, zone: UIntNative,
    size: UIntNative): UIntNative {
    let lock = unsafe { CPointer<AtomicSpinLock>(CPointer<UInt8>(space) + 64) }
    Lock(lock)
    let value = ZoneAddress(space, zone)
    let start = unsafe {
        cj_atomic_uintptr_fetch_add_seq_cst(CPointer<UIntNative>(CPointer<UInt8>(value) + 8), size)
    }
    let end = start.wrappingAdd(size)
    let commit = LastCommitAddress(space, zone)
    let last = unsafe { cj_atomic_uintptr_load_relaxed(commit) }
    if (end > last) {
        let pageSize = AllocUtilRndUp(size, UIntNative(ALLOC_UTIL_PAGE_SIZE))
        let result = unsafe {
            VirtualAlloc(CPointer<Unit>(unsafe { CPointer<UInt8>() + Int64(last) }), pageSize,
                MemMap.MEM_COMMIT, MemMap.PAGE_READWRITE)
        }
        if (result.isNull()) { ForwardDataError(0, 39) }
        unsafe { cj_atomic_uintptr_store_seq_cst(commit, last.wrappingAdd(pageSize)) }
    }
    Unlock(lock)
    return start
}

@When[os == "Linux" || env == "ohos"]
@NoHeapAlloc
public func ForwardDataSpaceRelease(space: CPointer<ForwardDataSpace>): Unit {
    let start = unsafe { CPointer<UIntNative>(CPointer<UInt8>(space) + 32).read(0) }
    let size = unsafe { CPointer<UIntNative>(CPointer<UInt8>(space) + 40).read(0) }
    let address = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(start)) }
    if (unsafe { madvise(address, size, 4) } != 0) {
        unsafe { let _ = memset(address, 0, size) }
    }
    ForwardDataSpaceReset(space)
}

@When[os == "macOS" || os == "iOS"]
@NoHeapAlloc
public func ForwardDataSpaceRelease(space: CPointer<ForwardDataSpace>): Unit {
    let start = unsafe { CPointer<UIntNative>(CPointer<UInt8>(space) + 32).read(0) }
    let size = unsafe { CPointer<UIntNative>(CPointer<UInt8>(space) + 40).read(0) }
    let address = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(start)) }
    unsafe { let _ = memset(address, 0, size) }
    let ret = unsafe { mmap(address, size, MemMap.PROT_READ | MemMap.PROT_WRITE,
        Int32(MemMap.MAP_PRIVATE | MemMap.MAP_ANONYMOUS | MemMap.MAP_FIXED), -1, 0) }
    if (ret.toUIntNative() == UIntNative.Max) {
        ForwardDataError(72, 33)
    } else if (ret.toUIntNative() != address.toUIntNative()) {
        ForwardDataError(105, 25)
    }
    ForwardDataSpaceReset(space)
}

@When[os == "Windows"]
@NoHeapAlloc
public func ForwardDataSpaceRelease(space: CPointer<ForwardDataSpace>): Unit {
    let start = unsafe { CPointer<UIntNative>(CPointer<UInt8>(space) + 32).read(0) }
    let size = unsafe { CPointer<UIntNative>(CPointer<UInt8>(space) + 40).read(0) }
    let address = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(start)) }
    if (unsafe { VirtualFree(address, size, 0x4000u32) } == 0) { ForwardDataError(39, 33) }
    ForwardDataSpaceReset(space)
}

@NoHeapAlloc
private func ForwardDataSpaceReset(space: CPointer<ForwardDataSpace>): Unit {
    var index: UIntNative = 0
    while (index < FORWARD_ZONE_COUNT) {
        let zone = ZoneAddress(space, index)
        let start = unsafe { CPointer<UIntNative>(zone).read(0) }
        unsafe { cj_atomic_uintptr_store_seq_cst(CPointer<UIntNative>(CPointer<UInt8>(zone) + 8), start) }
        SetLastCommit(space, index, start)
        index++
    }
}

@NoHeapAlloc
public func ForwardDataGetLiveInfoDataSize(manager: CPointer<ForwardDataManager>, heapSize: UIntNative): UIntNative {
    let rounded = AllocUtilRndUp(heapSize, UIntNative(ALLOC_UTIL_PAGE_SIZE))
    let unitCount = rounded.wrappingDiv(UIntNative(ALLOC_UTIL_PAGE_SIZE))
    unsafe { CPointer<UIntNative>(CPointer<UInt8>(manager) + ForwardManagerUnitCountOffset()).write(0, unitCount) }
    let oneUnit = sizeOf<LiveInfo>().wrappingAdd(
        sizeOf<RegionBitmap>().wrappingAdd(UIntNative(ALLOC_UTIL_PAGE_SIZE).wrappingDiv(64)).wrappingMul(3))
    return unitCount.wrappingMul(oneUnit)
}

@When[os != "Windows"]
private func ForwardManagerUnitCountOffset(): Int64 { return 96 }
@When[os == "Windows"]
private func ForwardManagerUnitCountOffset(): Int64 { return 144 }

@NoHeapAlloc
public func ForwardDataInitializeForCapacity(manager: CPointer<ForwardDataManager>, maxHeapBytes: UIntNative): Unit {
    let liveInfoSize = AllocUtilRndUp(ForwardDataGetLiveInfoDataSize(manager, maxHeapBytes),
        UIntNative(ALLOC_UTIL_PAGE_SIZE))
    let total = liveInfoSize.wrappingMul(2)
    let startAddress = ForwardDataMap(total)
    let baseOffset = ForwardManagerUnitCountOffset()
    unsafe {
        CPointer<UIntNative>(CPointer<UInt8>(manager) + baseOffset + 8).write(0, startAddress)
        CPointer<UIntNative>(CPointer<UInt8>(manager) + baseOffset + 16).write(0, total)
    }
    let unitCount = unsafe { CPointer<UIntNative>(CPointer<UInt8>(manager) + baseOffset).read(0) }
    ForwardDataSpaceInitialize(CPointer<ForwardDataSpace>(manager), startAddress, liveInfoSize, unitCount)
    ForwardDataSpaceInitialize(unsafe { CPointer<ForwardDataSpace>(CPointer<UInt8>(manager) + baseOffset / 2) },
        startAddress.wrappingAdd(liveInfoSize), liveInfoSize, unitCount)
}

@NoHeapAlloc
public func ForwardDataInitialize(manager: CPointer<ForwardDataManager>): Unit {
    let heap = unsafe { _ZN12MapleRuntime4Heap7GetHeapEv() }
    let capacity = unsafe { _ZNK12MapleRuntime8HeapImpl14GetMaxCapacityEv(heap) }
    ForwardDataInitializeForCapacity(manager, capacity)
}

@When[os == "Linux" || env == "ohos"]
private func ForwardDataMap(size: UIntNative): UIntNative {
    let address = unsafe { mmap(CPointer<Unit>(), size, MemMap.PROT_READ | MemMap.PROT_WRITE,
        Int32(MemMap.MAP_PRIVATE | MemMap.MAP_ANONYMOUS), -1, 0) }
    if (address.toUIntNative() == UIntNative.Max) {
        ForwardDataError(207, 40)
        unsafe { abort() }
    }
    unsafe {
        let _ = madvise(address, size, MADV_NOHUGEPAGE)
        MRT_PRCTL(address, size, CString(CPointer<UInt8>(inout FORWARD_DATA_NAME)))
    }
    return address.toUIntNative()
}

@When[os == "macOS" || os == "iOS"]
private func ForwardDataMap(size: UIntNative): UIntNative {
    let address = unsafe { mmap(CPointer<Unit>(), size, MemMap.PROT_READ | MemMap.PROT_WRITE,
        Int32(MemMap.MAP_PRIVATE | MemMap.MAP_ANONYMOUS), -1, 0) }
    if (address.toUIntNative() == UIntNative.Max) {
        ForwardDataError(207, 40)
        unsafe { abort() }
    }
    return address.toUIntNative()
}

@When[os == "Windows"]
private func ForwardDataMap(size: UIntNative): UIntNative {
    let address = unsafe { VirtualAlloc(CPointer<Unit>(), size, MemMap.MEM_RESERVE, MemMap.PAGE_READWRITE) }
    if (address.isNull()) {
        ForwardDataError(207, 40)
        unsafe { abort() }
    }
    return address.toUIntNative()
}

@NoHeapAlloc
public func ForwardDataAllocateLiveInfo(manager: CPointer<ForwardDataManager>): CPointer<LiveInfo> {
    let tag = unsafe { CPointer<UInt16>(CPointer<UInt8>(manager) + ForwardManagerUnitCountOffset() + 24).read(0) }
    let spaceSize = UIntNative(ForwardManagerUnitCountOffset()).wrappingDiv(2)
    let space = unsafe { CPointer<ForwardDataSpace>(CPointer<UInt8>(manager) + Int64(UIntNative(tag) * spaceSize)) }
    let address = ForwardDataSpaceAllocate(space, LIVE_INFO_ZONE, sizeOf<LiveInfo>())
    return unsafe { CPointer<LiveInfo>(CPointer<UInt8>() + Int64(address)) }
}

@NoHeapAlloc
public func ForwardDataAllocateRegionBitmap(manager: CPointer<ForwardDataManager>,
    regionSize: UIntNative): CPointer<RegionBitmap> {
    let tag = unsafe { CPointer<UInt16>(CPointer<UInt8>(manager) + ForwardManagerUnitCountOffset() + 24).read(0) }
    let spaceSize = UIntNative(ForwardManagerUnitCountOffset()).wrappingDiv(2)
    let space = unsafe { CPointer<ForwardDataSpace>(CPointer<UInt8>(manager) + Int64(UIntNative(tag) * spaceSize)) }
    let bitmapSize = UIntNative(RegionBitmapSize(UInt64(regionSize)))
    let address = ForwardDataSpaceAllocate(space, BIT_MAP_ZONE, bitmapSize)
    let bitmap = unsafe { CPointer<RegionBitmap>(CPointer<UInt8>() + Int64(address)) }
    RegionBitmapConstruct(bitmap, UInt64(regionSize))
    return bitmap
}

@NoHeapAlloc
public func ForwardDataSetTagID(manager: CPointer<ForwardDataManager>, id: UInt16): Unit {
    unsafe { CPointer<UInt16>(CPointer<UInt8>(manager) + ForwardManagerUnitCountOffset() + 24).write(0, id) }
}

@NoHeapAlloc
public func ForwardDataGetPreviousTagID(manager: CPointer<ForwardDataManager>): UInt16 {
    return unsafe {
        CPointer<UInt16>(CPointer<UInt8>(manager) + ForwardManagerUnitCountOffset() + 24).read(0) ^ 1u16
    }
}

@NoHeapAlloc
public func ForwardDataClearPrevious(manager: CPointer<ForwardDataManager>): Unit {
    let previous = ForwardDataGetPreviousTagID(manager)
    let spaceSize = UIntNative(ForwardManagerUnitCountOffset()).wrappingDiv(2)
    let space = unsafe { CPointer<ForwardDataSpace>(CPointer<UInt8>(manager) + Int64(UIntNative(previous) * spaceSize)) }
    ForwardDataSpaceRelease(space)
}

@NoHeapAlloc
public func ForwardDataUnbindPrevious(manager: CPointer<ForwardDataManager>): Unit {
    let previous = ForwardDataGetPreviousTagID(manager)
    let spaceSize = UIntNative(ForwardManagerUnitCountOffset()).wrappingDiv(2)
    let space = unsafe { CPointer<ForwardDataSpace>(CPointer<UInt8>(manager) + Int64(UIntNative(previous) * spaceSize)) }
    let zone = ZoneAddress(space, LIVE_INFO_ZONE)
    var current = unsafe { CPointer<UIntNative>(zone).read(0) }
    let position = unsafe { cj_atomic_uintptr_load_seq_cst(CPointer<UIntNative>(CPointer<UInt8>(zone) + 8)) }
    while (current < position) {
        let liveInfo = unsafe { CPointer<LiveInfo>(CPointer<UInt8>() + Int64(current)) }
        let region = CPointer<RegionInfo>(unsafe { liveInfo.read(0).bindedRegion })
        if (region.isNull()) { unsafe { abort() } }
        RegionInfo.CheckAndClearLiveInfo(region, CPointer<Unit>(liveInfo))
        current = current.wrappingAdd(sizeOf<LiveInfo>())
    }
}

@NoHeapAlloc
public func ForwardDataDestroy(manager: CPointer<ForwardDataManager>): Unit {
    let offset = ForwardManagerUnitCountOffset()
    let start = unsafe { CPointer<UIntNative>(CPointer<UInt8>(manager) + offset + 8).read(0) }
    let size = unsafe { CPointer<UIntNative>(CPointer<UInt8>(manager) + offset + 16).read(0) }
    if (start == 0) { return }
    let address = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(start)) }
    ForwardDataDestroyImpl(address, size)
}

@When[os != "Windows"]
private func ForwardDataDestroyImpl(address: CPointer<Unit>, size: UIntNative): Unit {
    if (unsafe { munmap(address, size) } != 0) { ForwardDataError(130, 36) }
}

@When[os == "Windows"]
private func ForwardDataDestroyImpl(address: CPointer<Unit>, size: UIntNative): Unit {
    let _ = size
    if (unsafe { VirtualFree(address, 0, MEM_RELEASE) } == 0) { ForwardDataError(166, 41) }
}
