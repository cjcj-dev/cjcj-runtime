package rt.heap.allocator

@NoHeapAlloc
public func CartesianTreeNoHeapRoot(tree: CPointer<CartesianTree>,
    firstIndex: UInt32, secondIndex: UInt32): UIntNative {
    var result: UIntNative = 0
    var index = 0u32
    if (tree.MergeInsert(firstIndex, 3u32, false)) {
        result += 1
    }
    if (tree.MergeInsert(secondIndex, 2u32, true)) {
        result += 2
    }
    if (tree.TakeUnits(1u32, CPointer<UInt32>(inout index), refreshRegionInfo: false)) {
        result += UIntNative(index) + 4
    }
    if (tree.TakeUnitsLowAddr(1u32, CPointer<UInt32>(inout index),
        refreshRegionInfo: false)) {
        result += UIntNative(index) + 8
    }
    result += tree.GetNodeCount()
    tree.ClearTree()
    if (tree.MergeInsert(firstIndex, 1u32, false)) {
        result += 16
    }
    tree.ReleaseRootNode()
    return result
}
