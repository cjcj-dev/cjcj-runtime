package rt.heap.allocator

// RegionInfo.h:534-551,759-799,1180-1208. The caller supplies initialized
// native metadata storage; this root performs only the production in-place
// initialization and atomic field accesses needed by the allocator layers.
@NoHeapAlloc
public func RegionInfoNoHeapRoot(heapAddress: UIntNative): UIntNative {
    RegionInfo.InitFreeRegion(1, 3)
    let freeRegion = RegionInfo.GetRegionInfo(1u32)

    let smallRegion = RegionInfo.InitRegion(4, 2, SMALL_SIZED_UNITS)
    let largeRegion = RegionInfo.InitRegionAt(
        heapAddress + 7 * RegionInfo.UNIT_SIZE, 1, LARGE_SIZED_UNITS)

    return UIntNative(RegionInfo.GetUnitRole(freeRegion)) +
        UIntNative(RegionInfo.GetRegionType(freeRegion)) +
        UIntNative(RegionInfo.GetUnitRole(smallRegion)) +
        UIntNative(RegionInfo.GetRegionType(smallRegion)) +
        UIntNative(RegionInfo.GetUnitRole(largeRegion)) +
        UIntNative(RegionInfo.GetRegionType(largeRegion))
}
