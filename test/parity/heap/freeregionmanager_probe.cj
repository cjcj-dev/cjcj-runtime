package rt.heap.allocator

main(): Int64 {
    let units: UIntNative = 24
    let metadata = AllocUtilRndUp(units * sizeOf<RegionInfo>(), RegionInfo.UNIT_SIZE)
    let mapSize = metadata + units * RegionInfo.UNIT_SIZE
    var mapping = MemMap.MapMemory(mapSize, mapSize)
    let mapped = unsafe { mapping.read() }
    let heap = mapped.GetBaseAddr().toUIntNative() + metadata
    RegionInfo.Initialize(units, heap)

    let storage = unsafe { malloc(sizeOf<FreeRegionManager>()) }
    let manager = CPointer<FreeRegionManager>(storage)
    FreeRegionManager.Construct(manager, CPointer<Unit>())
    manager.Initialize(units)

    manager.AddGarbageUnits(2u32, 4u32)
    manager.AddGarbageUnits(10u32, 2u32)
    manager.AddReleaseUnits(16u32, 3u32)
    unsafe {
        CPointer<UInt8>(heap + 2 * RegionInfo.UNIT_SIZE).write(0, 0xa5u8)
        CPointer<UInt8>(heap + 16 * RegionInfo.UNIT_SIZE).write(0, 0x5au8)
    }
    let dirty = manager.TakeRegion(2, SMALL_SIZED_UNITS, false)
    let dirtyFirst = !dirty.isNull() && dirty.GetUnitIdx() == 2 &&
        unsafe { CPointer<UInt8>(heap + 2 * RegionInfo.UNIT_SIZE).read(0) == 0u8 }
    let released = manager.TakeRegion(3, LARGE_SIZED_UNITS, false)
    let releasedFallback = !released.isNull() && released.GetUnitIdx() == 16 &&
        unsafe { CPointer<UInt8>(heap + 16 * RegionInfo.UNIT_SIZE).read(0) == 0x5au8 }

    manager.AddReleaseUnits(20u32, 2u32)
    unsafe { CPointer<UInt8>(heap + 20 * RegionInfo.UNIT_SIZE).write(0, 0x7cu8) }
    let prepared = manager.TakeRegion(2, SMALL_SIZED_UNITS, true)
    let physical = !prepared.isNull() && prepared.GetUnitIdx() == 20 &&
        unsafe { CPointer<UInt8>(heap + 20 * RegionInfo.UNIT_SIZE).read(0) == 0u8 }

    let dirtyBefore = manager.GetDirtyUnitCount()
    let dirtyMax = manager.GetDirtyMaxBlock()
    let dirtyNodes = manager.GetDirtyNodeCount()
    let moved = manager.ReleaseGarbageRegions(RegionInfo.UNIT_SIZE)
    let release = moved == UIntNative(dirtyBefore) * RegionInfo.UNIT_SIZE &&
        manager.GetDirtyUnitCount() == 0u32 && manager.GetReleasedUnitCount() == dirtyBefore &&
        manager.GetReleasedMaxBlock() == dirtyMax && manager.GetReleasedNodeCount() == dirtyNodes

    println("FREE_REGION_LAYOUT size=${sizeOf<FreeRegionManager>()} align=${alignOf<FreeRegionManager>()} " +
        "owner=0 released_mutex=8 released_tree=${8 + sizeOf<FreeRegionMutexStorage>()} " +
        "dirty_mutex=${8 + sizeOf<FreeRegionMutexStorage>() + sizeOf<CartesianTree>()} " +
        "dirty_tree=${8 + 2 * sizeOf<FreeRegionMutexStorage>() + sizeOf<CartesianTree>()}")
    println("FREE_REGION_PARITY dirty_first=${if (dirtyFirst) { 1 } else { 0 }} " +
        "released_fallback=${if (releasedFallback) { 1 } else { 0 }} " +
        "physical=${if (physical) { 1 } else { 0 }} release=${if (release) { 1 } else { 0 }} " +
        "dirty_before=${dirtyBefore} dirty_max=${dirtyMax} dirty_nodes=${dirtyNodes} moved=${moved}")

    FreeRegionManager.Destroy(manager)
    unsafe { free(storage) }
    MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout mapping))
    return if (dirtyFirst && releasedFallback && physical && release) { 0 } else { 1 }
}
