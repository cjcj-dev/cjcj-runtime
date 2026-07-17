package rt.heap.allocator

main(): Int64 {
    let units: UIntNative = 16
    let mapSize = (units + 1) * RegionInfo.UNIT_SIZE
    var mapping = MemMap.MapMemory(mapSize, mapSize)
    let mapped = unsafe { mapping.read() }
    let heap = mapped.GetBaseAddr().toUIntNative() + RegionInfo.UNIT_SIZE
    RegionInfo.Initialize(units, heap)

    var treeValue = CartesianTree()
    let tree = unsafe { CPointer<CartesianTree>(inout treeValue) }
    Init(tree, 16)
    let releasedUnit = unsafe {
        CPointer<UInt8>(CPointer<UInt8>() + Int64(heap + RegionInfo.UNIT_SIZE))
    }
    unsafe { releasedUnit.write(0, 0xabu8) }
    let result = CartesianTreeNoHeapRoot(tree, 1u32, 5u32)
    let releasedByte = unsafe { releasedUnit.read(0) }
    if (result != 43 || releasedByte != 0u8 ||
        !Empty(tree) || tree.GetTotalCount() != 0u32) {
        return 1
    }
    Fini(tree)
    MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout mapping))
    println("CARTESIAN_TREE_NOHEAP_EXEC result=43 release=PASS")
    return 0
}
