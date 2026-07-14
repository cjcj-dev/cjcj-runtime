package rt.heap.allocator

import rt.base.*

foreign { func exit(status: Int32): Unit }

class CartesianModel {
    var indices: VArray<Index, $2048> = VArray<Index, $2048>(repeat: 0u32)
    var counts: VArray<Count, $2048> = VArray<Count, $2048>(repeat: 0u32)
    var size: Int64 = 0

    func Total(): UInt64 {
        var total = 0u64
        var i: Int64 = 0
        while (i < size) {
            total += UInt64(counts[i])
            i += 1
        }
        return total
    }

    func AnyFit(count: Count): Bool {
        var i: Int64 = 0
        while (i < size) {
            if (counts[i] >= count) {
                return true
            }
            i += 1
        }
        return false
    }

    func Insert(index: Index, count: Count): Bool {
        if (size == 0) {
            indices[0] = index
            counts[0] = count
            size = 1
            return true
        }
        if (count == 0u32) {
            return false
        }
        let end = index + count
        var pos: Int64 = 0
        while (pos < size && indices[pos] < index) {
            pos += 1
        }
        if (pos > 0 && index < indices[pos - 1] + counts[pos - 1]) {
            return false
        }
        if (pos < size && end > indices[pos]) {
            return false
        }
        let joinLeft = pos > 0 && indices[pos - 1] + counts[pos - 1] == index
        let joinRight = pos < size && end == indices[pos]
        if (joinLeft && joinRight) {
            counts[pos - 1] += count + counts[pos]
            var i = pos
            while (i + 1 < size) {
                indices[i] = indices[i + 1]
                counts[i] = counts[i + 1]
                i += 1
            }
            size -= 1
        } else if (joinLeft) {
            counts[pos - 1] += count
        } else if (joinRight) {
            indices[pos] = index
            counts[pos] += count
        } else {
            var i = size
            while (i > pos) {
                indices[i] = indices[i - 1]
                counts[i] = counts[i - 1]
                i -= 1
            }
            indices[pos] = index
            counts[pos] = count
            size += 1
        }
        return true
    }

    func TakeAt(index: Index, count: Count): Bool {
        var i: Int64 = 0
        while (i < size) {
            if (indices[i] == index && counts[i] >= count) {
                indices[i] += count
                counts[i] -= count
                if (counts[i] == 0u32) {
                    var j = i
                    while (j + 1 < size) {
                        indices[j] = indices[j + 1]
                        counts[j] = counts[j + 1]
                        j += 1
                    }
                    size -= 1
                }
                return true
            }
            i += 1
        }
        return false
    }

    func BestFit(count: Count, index: CPointer<Index>): Bool {
        var found = false
        var bestCount = 0u32
        var bestIndex = unsafe { index.read(0) }
        var i: Int64 = 0
        while (i < size) {
            if (counts[i] >= count && (!found || counts[i] < bestCount ||
                (counts[i] == bestCount && indices[i] < bestIndex))) {
                found = true
                bestCount = counts[i]
                bestIndex = indices[i]
            }
            i += 1
        }
        if (found) {
            unsafe { index.write(0, bestIndex) }
        }
        return found
    }
}

var cartesianOperations = 0u64
var cartesianRecords = 0u64
var cartesianLifetimes = 0u64

func Require(condition: Bool): Unit {
    if (!condition) {
        unsafe { exit(1) }
    }
}

func CheckHeap(node: CPointer<CartesianNode>, low: UInt64, high: UInt64): Unit {
    if (node.isNull()) {
        return
    }
    let begin = UInt64(node.GetIndex())
    let end = begin + UInt64(node.GetCount())
    Require(begin >= low && end <= high)
    let left = unsafe { CPointer<CPointer<CartesianNode>>(node).read(0) }
    if (!left.isNull()) {
        Require(UInt64(left.GetIndex()) + UInt64(left.GetCount()) < begin)
        Require(left.GetCount() <= node.GetCount())
        CheckHeap(left, low, begin)
    }
    let right = unsafe {
        CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8).read(0)
    }
    if (!right.isNull()) {
        Require(end < UInt64(right.GetIndex()))
        Require(right.GetCount() <= node.GetCount())
        CheckHeap(right, end, high)
    }
}

func Validate(tree: CPointer<CartesianTree>, model: CartesianModel): Unit {
    var actualIndices = VArray<Index, $2048>(repeat: 0u32)
    var actualCounts = VArray<Count, $2048>(repeat: 0u32)
    var actualSize: Int64 = 0
    var iterator = Iterator(tree)
    cartesianLifetimes += 1
    var node = iterator.Next()
    while (!node.isNull()) {
        Require(actualSize < 2048)
        actualIndices[actualSize] = node.GetIndex()
        actualCounts[actualSize] = node.GetCount()
        actualSize += 1
        node = iterator.Next()
    }
    var i: Int64 = 0
    while (i < actualSize) {
        var j = i + 1
        while (j < actualSize) {
            if (actualIndices[j] < actualIndices[i]) {
                let swapIndex = actualIndices[i]
                let swapCount = actualCounts[i]
                actualIndices[i] = actualIndices[j]
                actualCounts[i] = actualCounts[j]
                actualIndices[j] = swapIndex
                actualCounts[j] = swapCount
            }
            j += 1
        }
        i += 1
    }
    Require(actualSize == model.size)
    i = 0
    while (i < actualSize) {
        Require(actualIndices[i] == model.indices[i] && actualCounts[i] == model.counts[i])
        i += 1
    }
    var forward = ForwardIterator(tree)
    cartesianLifetimes += 1
    var slotCount: Int64 = 0
    var slot = forward.Next()
    while (!slot.isNull()) {
        Require(!(unsafe { slot.read(0) }).isNull())
        slotCount += 1
        slot = forward.Next()
    }
    Require(slotCount == model.size)
    Require(tree.GetNodeCount() == UIntNative(model.size))
    Require(UInt64(tree.GetTotalCount()) == model.Total())
    Require(tree.Empty() == (model.size == 0))
    if (!tree.Empty()) {
        let root = tree.RootNode()
        Require(!root.isNull())
        CheckHeap(root, 0u64, UInt64.Max)
    }
}

func EmitState(step: UInt32, action: UInt32, argumentIndex: Index,
    argumentCount: Count, result: Bool, resultIndex: Index, model: CartesianModel): Unit {
    println("T ${step} ${action} ${argumentIndex} ${argumentCount} " +
        "${if (result) { 1 } else { 0 }} ${resultIndex} ${model.Total()} ${model.size}")
    cartesianRecords += 1
    var i: Int64 = 0
    while (i < model.size) {
        println("E ${step} ${i} ${model.indices[i]} ${model.counts[i]}")
        cartesianRecords += 1
        i += 1
    }
}

func RunFixedCases(): Unit {
    var treeValue = CartesianTree()
    let tree = unsafe { CPointer<CartesianTree>(inout treeValue) }
    tree.Init(256)
    let model = CartesianModel()
    var out = 0xfeedu32
    Require(!tree.TakeUnits(1u32, CPointer<Index>(inout out), refreshRegionInfo: false))
    Require(tree.MergeInsert(10u32, 0u32, false) == model.Insert(10u32, 0u32))
    Validate(tree, model)
    tree.ClearTree()
    model.size = 0
    Require(tree.MergeInsert(10u32, 4u32, false) == model.Insert(10u32, 4u32))
    Require(!tree.MergeInsert(20u32, 0u32, false))
    Require(tree.MergeInsert(30u32, 5u32, false) == model.Insert(30u32, 5u32))
    Require(tree.MergeInsert(11u32, 2u32, false) == model.Insert(11u32, 2u32))
    Require(tree.MergeInsert(14u32, 3u32, false) == model.Insert(14u32, 3u32))
    Require(tree.MergeInsert(27u32, 3u32, false) == model.Insert(27u32, 3u32))
    Require(tree.MergeInsert(17u32, 10u32, false) == model.Insert(17u32, 10u32))
    Require(tree.MergeInsert(100u32, 2u32, false) == model.Insert(100u32, 2u32))
    Require(tree.MergeInsert(50u32, 8u32, false) == model.Insert(50u32, 8u32))
    Require(tree.MergeInsert(150u32, 9u32, false) == model.Insert(150u32, 9u32))
    Require(tree.MergeInsert(200u32, 9u32, false) == model.Insert(200u32, 9u32))
    Validate(tree, model)
    out = 0u32
    var result = tree.TakeUnits(3u32, CPointer<Index>(inout out), refreshRegionInfo: false)
    Require(result && model.TakeAt(out, 3u32))
    Validate(tree, model)
    out = 0u32
    result = tree.TakeUnits(1000u32, CPointer<Index>(inout out), refreshRegionInfo: false)
    Require(!result && !model.AnyFit(1000u32))
    Validate(tree, model)
    tree.ClearTree()
    model.size = 0
    Require(tree.MergeInsert(100u32, 8u32, false) == model.Insert(100u32, 8u32))
    Require(tree.MergeInsert(300u32, 5u32, false) == model.Insert(300u32, 5u32))
    Require(tree.MergeInsert(500u32, 5u32, false) == model.Insert(500u32, 5u32))
    var expected = 0u32
    Require(model.BestFit(4u32, CPointer<Index>(inout expected)))
    out = 0u32
    result = tree.TakeUnitsLowAddr(4u32, CPointer<Index>(inout out),
        refreshRegionInfo: false)
    Require(result && out == expected && model.TakeAt(out, 4u32))
    Validate(tree, model)
    expected = 0u32
    Require(model.BestFit(5u32, CPointer<Index>(inout expected)))
    out = 0u32
    result = tree.TakeUnitsLowAddr(5u32, CPointer<Index>(inout out),
        refreshRegionInfo: false)
    Require(result && out == expected && model.TakeAt(out, 5u32))
    Validate(tree, model)
    tree.ClearTree()
    model.size = 0
    Require(tree.MergeInsert(700u32, 4u32, false) == model.Insert(700u32, 4u32))
    out = 0u32
    let rootSlot = unsafe {
        CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(tree) + 8)
    }
    result = tree.AllocateLowestAddressFromNode(rootSlot, 2u32,
        CPointer<Index>(inout out))
    Require(result && model.TakeAt(out, 2u32))
    Validate(tree, model)
    tree.ClearTree()
    model.size = 0
    Validate(tree, model)
    tree.Fini()
    println("F fixed=PASS")
    cartesianRecords += 1
}

func RunLargeTrees(): Unit {
    var pass = 0u32
    while (pass < 2u32) {
        var treeValue = CartesianTree()
        let tree = unsafe { CPointer<CartesianTree>(inout treeValue) }
        tree.Init(1200)
        var i = 0u32
        while (i < 600u32) {
            Require(tree.MergeInsert(i * 2u32 + pass, 1u32, false))
            i += 1
        }
        Require(tree.GetNodeCount() == 600 && tree.GetTotalCount() == 600u32)
        var iterator = Iterator(tree)
        cartesianLifetimes += 1
        var count: Int64 = 0
        while (!iterator.Next().isNull()) {
            count += 1
        }
        Require(count == 600)
        println("D ${pass} 600 ${count}")
        cartesianRecords += 1
        tree.Fini()
        pass += 1
    }
}

func RunIteratorLifetimes(): Unit {
    var treeValue = CartesianTree()
    let tree = unsafe { CPointer<CartesianTree>(inout treeValue) }
    tree.Init(8)
    Require(tree.MergeInsert(10u32, 2u32, false))
    Require(tree.MergeInsert(20u32, 1u32, false))
    var i = 0u32
    while (i < 1100u32) {
        var iterator = Iterator(tree)
        cartesianLifetimes += 1
        Require(!iterator.Next().isNull() && !iterator.Next().isNull() &&
            iterator.Next().isNull())
        i += 1
    }
    tree.Fini()
    println("L 1100 PASS")
    cartesianRecords += 1
}

func RunTrace(): Unit {
    var treeValue = CartesianTree()
    let tree = unsafe { CPointer<CartesianTree>(inout treeValue) }
    tree.Init(4096)
    let model = CartesianModel()
    var seed = 0x4341525445534941u64
    var step = 0u32
    while (step < 1200u32) {
        seed = seed * 6364136223846793005u64 + 1442695040888963407u64
        let action = UInt32((seed >> 32u64) % 3u64)
        let argumentIndex = UInt32(((seed >> 12u64) % 1800u64) * 2u64)
        let argumentCount = UInt32(seed % 9u64 + 1u64)
        var resultIndex = 0xffffffffu32
        var result = false
        if (action == 0u32) {
            let expected = model.Insert(argumentIndex, argumentCount)
            result = tree.MergeInsert(argumentIndex, argumentCount, false)
            Require(result == expected)
        } else if (action == 1u32) {
            let expected = model.AnyFit(argumentCount)
            result = tree.TakeUnits(argumentCount, CPointer<Index>(inout resultIndex),
                refreshRegionInfo: false)
            Require(result == expected)
            if (result) {
                Require(model.TakeAt(resultIndex, argumentCount))
            }
        } else {
            var expectedIndex = 0xffffffffu32
            let expected = model.BestFit(argumentCount,
                CPointer<Index>(inout expectedIndex))
            result = tree.TakeUnitsLowAddr(argumentCount,
                CPointer<Index>(inout resultIndex), refreshRegionInfo: false)
            Require(result == expected)
            if (result) {
                Require(resultIndex == expectedIndex)
                Require(model.TakeAt(resultIndex, argumentCount))
            }
        }
        cartesianOperations += 1
        Validate(tree, model)
        EmitState(step, action, argumentIndex, argumentCount, result, resultIndex, model)
        step += 1
    }
    tree.Fini()
    println("R seed=${seed} operations=1200")
    cartesianRecords += 1
}

func RunRegionInfo(): Unit {
    let units: UIntNative = 16
    let mapSize = (units + 1) * RegionInfo.UNIT_SIZE
    var mapping = MemMap.MapMemory(mapSize, mapSize)
    let mapped = unsafe { mapping.read() }
    let heap = mapped.GetBaseAddr().toUIntNative() + RegionInfo.UNIT_SIZE
    RegionInfo.Initialize(units, heap)
    var treeValue = CartesianTree()
    let tree = unsafe { CPointer<CartesianTree>(inout treeValue) }
    tree.Init(16)
    Require(tree.MergeInsert(2u32, 3u32, true))
    let region = RegionInfo.GetRegionInfo(2u32)
    let metadata = unsafe { region.read(0).metadata }
    let state = metadata.regionStateBitField.fieldVal
    println("G refresh ${(metadata.allocPtr - heap) / RegionInfo.UNIT_SIZE} " +
        "${(metadata.regionEnd - heap) / RegionInfo.UNIT_SIZE} ${metadata.nextRegionIdx} " +
        "${metadata.prevRegionIdx} ${metadata.liveByteCount} " +
        "${if (metadata.liveInfo.isNull()) { 0 } else { 1 }} ${region.GetRegionType()} " +
        "${region.GetUnitRole()} ${(state >> UInt16(TRACE_REGION_FLAG)) & 1u16} " +
        "${(state >> UInt16(MARKED_REGION_FLAG)) & 1u16} " +
        "${(state >> UInt16(ENQUEUED_REGION_FLAG)) & 1u16} " +
        "${(state >> UInt16(RESURRECTED_REGION_FLAG)) & 1u16} " +
        "${metadata.rawPointerObjectCount}")
    cartesianRecords += 1
    tree.ClearTree()
    let unit = unsafe {
        CPointer<UInt8>(CPointer<UInt8>() + Int64(heap + RegionInfo.UNIT_SIZE))
    }
    unsafe { unit.write(0, 0xabu8) }
    Require(tree.MergeInsert(1u32, 1u32, false))
    tree.ReleaseRootNode()
    Require(unsafe { unit.read(0) == 0u8 } && tree.Empty() && tree.GetTotalCount() == 0u32)
    println("G release 1 0")
    cartesianRecords += 1
    tree.Fini()
    MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout mapping))
}

func DumpLayout(): Unit {
    var node = CartesianNode(0u32, 0u32, false)
    let base = unsafe { CPointer<UInt8>(inout node).toUIntNative() }
    let left = unsafe { CPointer<UInt8>(inout node.l).toUIntNative() - base }
    let right = unsafe { CPointer<UInt8>(inout node.r).toUIntNative() - base }
    let index = unsafe { CPointer<UInt8>(inout node.index).toUIntNative() - base }
    let count = unsafe { CPointer<UInt8>(inout node.count).toUIntNative() - base }
    println("CARTESIAN_NODE_LAYOUT sizeof=${sizeOf<CartesianNode>()} " +
        "align=${alignOf<CartesianNode>()} l=${left} r=${right} index=${index} count=${count}")
    println("CARTESIAN_NODE_FIELDS l_width=${sizeOf<CPointer<CartesianNode>>()} " +
        "r_width=${sizeOf<CPointer<CartesianNode>>()} index_width=${sizeOf<Index>()} " +
        "count_width=${sizeOf<Count>()}")
    cartesianRecords += 2
}

main(): Int64 {
    DumpLayout()
    RunFixedCases()
    RunLargeTrees()
    RunIteratorLifetimes()
    RunTrace()
    RunRegionInfo()
    println("S operations=${cartesianOperations} lifetimes=${cartesianLifetimes} " +
        "records=${cartesianRecords}")
    return 0
}
