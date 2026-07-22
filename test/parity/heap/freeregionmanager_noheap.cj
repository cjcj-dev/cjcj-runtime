package rt.heap.allocator

// FreeRegionManager.h:24-168 and RegionManager.cpp:278-304. This single root
// reaches the complete ported production surface; emitted static roots are
// independently added by the closure checker.
@NoHeapAlloc
public func FreshFreeRegionManagerPolicy(manager: CPointer<FreeRegionManager>,
    region: CPointer<RegionInfo>): UIntNative {
    FreeRegionManager.Construct(manager, CPointer<Unit>())
    manager.Initialize(32)
    manager.AddGarbageUnits(1u32, 3u32)
    manager.AddReleaseUnits(8u32, 2u32)
    var bits = UIntNative(manager.GetDirtyUnitCount()) ^ UIntNative(manager.GetReleasedUnitCount())
    bits = bits ^ UIntNative(manager.GetDirtyMaxBlock()) ^ UIntNative(manager.GetReleasedMaxBlock())
    bits = bits ^ manager.GetDirtyNodeCount() ^ manager.GetReleasedNodeCount()
    bits = bits ^ manager.TakeRegion(1, SMALL_SIZED_UNITS, false).toUIntNative()
    bits = bits ^ manager.ReleaseGarbageRegions(0)
    let _ = region
    FreeRegionManager.Destroy(manager)
    return bits
}
