package rt.heap.allocator

import rt.base.*

// Heap/Allocator/CartesianTree.h:18-30. MRT_DEBUG defines
// DEBUG_CARTESIAN_TREE. This package is the release runtime, so CTREE_ASSERT,
// CTREE_CHECK_PARENT_AND_LCHILD, and CTREE_CHECK_PARENT_AND_RCHILD are exact
// no-ops. The debug-only DumpTree/Check*/VerifyTree bodies at :526-571 and
// CartesianTree.cpp:92-122 are therefore outside this release translation.

// Heap/Allocator/CartesianTree.h:42-43.
public type Index = UInt32
public type Count = UInt32

// CartesianTree.h:135-190. Every live node is placement-created in native
// RTAllocatorT storage. This is the actual production record, not a mirror.
@C
public struct CartesianNode {
    public var l: CPointer<CartesianNode>
    public var r: CPointer<CartesianNode>
    var index: Index
    var count: Count

    // CartesianTree.h:136-141.
    public init(idx: Index, num: Count, refreshRegionInfo: Bool) {
        l = CPointer<CartesianNode>()
        r = CPointer<CartesianNode>()
        index = idx
        count = num
        if (refreshRegionInfo) {
            RegionInfo.InitFreeRegion(UIntNative(idx), UIntNative(num))
        }
    }
}

// CartesianTree.h:294-298.
type MergeResult = UInt8
const MERGE_SUCCESS: MergeResult = 0u8
const MERGE_MISS: MergeResult = 1u8
const MERGE_ERROR: MergeResult = 2u8

// CartesianTree.h:272.
type RTAllocator = RTAllocatorT

// CartesianTree.h:278-283. These are the five and only five persistent fields.
// @C places the actual root slot in AS0 when a tree value is stack/native backed;
// the three accepted helper objects remain their existing managed references.
@C
public struct CartesianTree {
    var totalCount: Count
    var root: CPointer<CartesianNode>
    let sud: SingleUseDeque
    let traversalSud: SingleUseDeque
    let nodeAllocator: RTAllocator

    // CartesianTree.h:45-46 and in-class initializers at :279-283.
    public init() {
        totalCount = 0u32
        root = CPointer<CartesianNode>()
        sud = SingleUseDeque()
        traversalSud = SingleUseDeque()
        nodeAllocator = RTAllocatorT()
    }
}

// CartesianTree.h:196-225. Fresh operation-local backwards level iterator.
public struct Iterator {
    private var localQueue: LocalDeque

    // CartesianTree.h:198-203.
    public init(tree: CPointer<CartesianTree>) {
        let traversalSud = unsafe { tree.read(0).traversalSud }
        localQueue = LocalDeque(traversalSud)
        let rootSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(tree) + 8)
        }
        let treeRoot = unsafe { rootSlot.read(0) }
        if (!treeRoot.isNull()) {
            localQueue.Push(CPointer<Unit>(treeRoot))
        }
    }

    // CartesianTree.h:207-221. Right is enqueued before left.
    public mut func Next(): CPointer<CartesianNode> {
        if (localQueue.Empty()) {
            return CPointer<CartesianNode>()
        }
        let front = CPointer<CartesianNode>(localQueue.Front())
        let rightSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(front) + 8)
        }
        let right = unsafe { rightSlot.read(0) }
        if (!right.isNull()) {
            localQueue.Push(CPointer<Unit>(right))
        }
        let leftSlot = CPointer<CPointer<CartesianNode>>(front)
        let left = unsafe { leftSlot.read(0) }
        if (!left.isNull()) {
            localQueue.Push(CPointer<Unit>(left))
        }
        localQueue.PopFront()
        return front
    }
}

// CartesianTree.h:229-259. Fresh operation-local lvalue iterator.
public struct ForwardIterator {
    private var localQueue: LocalDeque

    // CartesianTree.h:231-236.
    public init(tree: CPointer<CartesianTree>) {
        let sud = unsafe { tree.read(0).sud }
        localQueue = LocalDeque(sud)
        let rootSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(tree) + 8)
        }
        let treeRoot = unsafe { rootSlot.read(0) }
        if (!treeRoot.isNull()) {
            localQueue.Push(CPointer<Unit>(rootSlot))
        }
    }

    // CartesianTree.h:240-255. Node** queue, right before left.
    public mut func Next(): CPointer<CPointer<CartesianNode>> {
        if (localQueue.Empty()) {
            return CPointer<CPointer<CartesianNode>>()
        }
        let topElement = CPointer<CPointer<CartesianNode>>(localQueue.Front())
        let node = unsafe { topElement.read(0) }
        let rightSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8)
        }
        if (!(unsafe { rightSlot.read(0) }).isNull()) {
            localQueue.Push(CPointer<Unit>(rightSlot))
        }
        let leftSlot = CPointer<CPointer<CartesianNode>>(node)
        if (!(unsafe { leftSlot.read(0) }).isNull()) {
            localQueue.Push(CPointer<Unit>(leftSlot))
        }
        localQueue.PopFront()
        return topElement
    }
}

extend CPointer<CartesianNode> {
    // CartesianTree.h:149.
    public func GetIndex(): Index {
        return unsafe { CPointer<Index>(CPointer<UInt8>(this) + 16).read(0) }
    }

    // CartesianTree.h:151.
    public func GetCount(): Count {
        return unsafe { CPointer<Count>(CPointer<UInt8>(this) + 20).read(0) }
    }

    // CartesianTree.h:153-159.
    public func IncCount(num: Count, refreshRegionInfo: Bool): Unit {
        let newCount = GetCount() + num
        unsafe { CPointer<Count>(CPointer<UInt8>(this) + 20).write(0, newCount) }
        if (refreshRegionInfo && newCount > 0u32) {
            RefreshFreeRegionInfo()
        }
    }

    // CartesianTree.h:161.
    public func ClearCount(): Unit {
        unsafe { CPointer<Count>(CPointer<UInt8>(this) + 20).write(0, 0u32) }
    }

    // CartesianTree.h:163-172.
    public func UpdateNode(idx: Index, cnt: Count, refreshRegionInfo: Bool): Unit {
        unsafe {
            CPointer<Index>(CPointer<UInt8>(this) + 16).write(0, idx)
            CPointer<Count>(CPointer<UInt8>(this) + 20).write(0, cnt)
        }
        if (refreshRegionInfo && cnt > 0u32) {
            RefreshFreeRegionInfo()
        }
    }

    // CartesianTree.h:174-179.
    public func IsProperNode(): Bool {
        let left = unsafe { CPointer<CPointer<CartesianNode>>(this).read(0) }
        let right = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8).read(0)
        }
        let leftCount = if (left.isNull()) { 0u32 } else { left.GetCount() }
        let rightCount = if (right.isNull()) { 0u32 } else { right.GetCount() }
        let nodeCount = GetCount()
        return nodeCount >= leftCount && nodeCount >= rightCount
    }

    // CartesianTree.cpp:124-129.
    public func RefreshFreeRegionInfo(): Unit {
        RegionInfo.InitFreeRegion(UIntNative(GetIndex()), UIntNative(GetCount()))
    }

    // CartesianTree.cpp:131-136.
    public func ReleaseMemory(): Unit {
        RegionInfo.ReleaseUnits(UIntNative(GetIndex()), UIntNative(GetCount()))
    }
}

extend CPointer<CartesianTree> {
    // CartesianTree.h:48-60.
    public func Init(memoryBlockCount: UIntNative): Unit {
        let nodeCount = (memoryBlockCount >> 1) + 1
        let nodeSize = AllocUtilRndUp(sizeOf<CartesianNode>(), alignOf<CartesianNode>())
        let nativeSize = (nodeCount + 7) * nodeSize
        let nativeMapSize = AllocUtilRndUp(nativeSize, UIntNative(ALLOC_UTIL_PAGE_SIZE))
        let tree = unsafe { this.read(0) }
        tree.nodeAllocator.Init(Int64(nodeSize), nativeMapSize)
        let dequeSize = nodeCount * sizeOf<CPointer<CartesianNode>>()
        let dequeMapSize = AllocUtilRndUp(dequeSize, UIntNative(ALLOC_UTIL_PAGE_SIZE))
        tree.sud.Init(dequeMapSize)
        tree.traversalSud.Init(tree.sud.GetMemMap())
    }

    // CartesianTree.h:62-67. Order is exact.
    public func Fini(): Unit {
        ClearTree()
        let tree = unsafe { this.read(0) }
        tree.sud.Fini()
        tree.nodeAllocator.Fini()
    }

    // CartesianTree.h:69-80.
    public func ClearTree(): Unit {
        var it = Iterator(this)
        var node = it.Next()
        while (!node.isNull()) {
            DeleteNode(node)
            node = it.Next()
        }
        let rootSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8)
        }
        unsafe {
            rootSlot.write(0, CPointer<CartesianNode>())
            CPointer<Count>(this).write(0, 0u32)
        }
    }

    // CartesianTree.h:82.
    public func GetTotalCount(): Count {
        return unsafe { CPointer<Count>(this).read(0) }
    }

    // CartesianTree.h:84.
    func IncTotalCount(cnt: Count): Unit {
        unsafe { CPointer<Count>(this).write(0, GetTotalCount() + cnt) }
    }

    // CartesianTree.h:86-92.
    func DecTotalCount(cnt: Count): Unit {
        let total = GetTotalCount()
        if (total < cnt) {
            unsafe { abort() }
        }
        unsafe { CPointer<Count>(this).write(0, total - cnt) }
    }

    // CartesianTree.h:99-113.
    public func MergeInsert(idx: Index, num: Count, refreshRegionInfo: Bool): Bool {
        let rootSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8)
        }
        if ((unsafe { rootSlot.read(0) }).isNull()) {
            let nodeAllocator = unsafe { this.read(0).nodeAllocator }
            let root = CPointer<CartesianNode>(nodeAllocator.Allocate())
            unsafe { root.write(0, CartesianNode(idx, num, refreshRegionInfo)) }
            unsafe { rootSlot.write(0, root) }
            IncTotalCount(num)
            return true
        }
        if (num == 0u32) {
            return false
        }
        return MergeInsertInternal(idx, num, refreshRegionInfo)
    }

    // CartesianTree.h:116-123.
    public func TakeUnits(num: Count, idx: CPointer<Index>,
        refreshRegionInfo!: Bool = true): Bool {
        let root = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8).read(0)
        }
        if (root.isNull() || num == 0u32) {
            return false
        }
        return TakeUnitsImpl(num, idx, refreshRegionInfo)
    }

    // CartesianTree.h:126-133.
    public func TakeUnitsLowAddr(num: Count, idx: CPointer<Index>,
        refreshRegionInfo!: Bool = true): Bool {
        let root = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8).read(0)
        }
        if (root.isNull() || num == 0u32) {
            return false
        }
        return TakeUnitsLowAddrImpl(num, idx, refreshRegionInfo)
    }

    // CartesianTree.h:261.
    public func Empty(): Bool {
        return unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8).read(0).isNull()
        }
    }

    // CartesianTree.h:262.
    public func RootNode(): CPointer<CartesianNode> {
        return unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8).read(0)
        }
    }

    // CartesianTree.cpp:138-146.
    public func GetNodeCount(): UIntNative {
        var nodeCount: UIntNative = 0
        var it = Iterator(this)
        while (!it.Next().isNull()) {
            nodeCount += 1
        }
        return nodeCount
    }

    // CartesianTree.h:266-270.
    public func ReleaseRootNode(): Unit {
        let rootSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8)
        }
        let root = unsafe { rootSlot.read(0) }
        root.ReleaseMemory()
        RemoveNode(rootSlot)
    }

    // CartesianTree.h:285-291.
    func DeleteNode(node: CPointer<CartesianNode>): Unit {
        if (node.isNull()) {
            return
        }
        let nodeAllocator = unsafe { this.read(0).nodeAllocator }
        nodeAllocator.Deallocate(CPointer<Unit>(node))
    }

    // CartesianTree.h:300-315.
    func MergeAt(node: CPointer<CartesianNode>, idx: Index, num: Count,
        refreshRegionInfo: Bool): MergeResult {
        let endIdx = idx + num
        if (idx == node.GetIndex() + node.GetCount()) {
            return MergeToRight(node, endIdx, num, refreshRegionInfo)
        }
        if (endIdx == node.GetIndex()) {
            return MergeToLeft(node, idx, num, refreshRegionInfo)
        }
        return MERGE_MISS
    }

    // CartesianTree.h:319-356.
    func MergeToRight(node: CPointer<CartesianNode>, endIdx: Index, num: Count,
        refreshRegionInfo: Bool): MergeResult {
        var parent = node
        let nodeRightSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8)
        }
        var nearest = unsafe { nodeRightSlot.read(0) }
        while (!nearest.isNull()) {
            if (nearest.GetIndex() == endIdx) {
                let nearestLeft = unsafe { CPointer<CPointer<CartesianNode>>(nearest).read(0) }
                if (!nearestLeft.isNull()) {
                    return MERGE_ERROR
                }
                break
            } else if (nearest.GetIndex() < endIdx) {
                return MERGE_ERROR
            } else {
                parent = nearest
                nearest = unsafe { CPointer<CPointer<CartesianNode>>(nearest).read(0) }
            }
        }
        node.IncCount(num, refreshRegionInfo)
        IncTotalCount(num)
        if (!nearest.isNull()) {
            node.IncCount(nearest.GetCount(), refreshRegionInfo)
            let nearestRight = unsafe {
                CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(nearest) + 8).read(0)
            }
            if (parent.toUIntNative() == node.toUIntNative()) {
                unsafe { nodeRightSlot.write(0, nearestRight) }
            } else {
                unsafe { CPointer<CPointer<CartesianNode>>(parent).write(0, nearestRight) }
            }
            let nodeAllocator = unsafe { this.read(0).nodeAllocator }
            nodeAllocator.Deallocate(CPointer<Unit>(nearest))
        }
        return MERGE_SUCCESS
    }

    // CartesianTree.h:360-395.
    func MergeToLeft(node: CPointer<CartesianNode>, startIdx: Index, num: Count,
        refreshRegionInfo: Bool): MergeResult {
        var parent = node
        let nodeLeftSlot = CPointer<CPointer<CartesianNode>>(node)
        var nearest = unsafe { nodeLeftSlot.read(0) }
        while (!nearest.isNull()) {
            if (nearest.GetIndex() + nearest.GetCount() == startIdx) {
                let nearestRight = unsafe {
                    CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(nearest) + 8).read(0)
                }
                if (!nearestRight.isNull()) {
                    return MERGE_ERROR
                }
                break
            } else if (nearest.GetIndex() + nearest.GetCount() > startIdx) {
                return MERGE_ERROR
            } else {
                parent = nearest
                nearest = unsafe {
                    CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(nearest) + 8).read(0)
                }
            }
        }
        node.UpdateNode(startIdx, node.GetCount() + num, refreshRegionInfo)
        IncTotalCount(num)
        if (!nearest.isNull()) {
            let nearestLeft = unsafe { CPointer<CPointer<CartesianNode>>(nearest).read(0) }
            if (parent.toUIntNative() == node.toUIntNative()) {
                unsafe { nodeLeftSlot.write(0, nearestLeft) }
            } else {
                let parentRightSlot = unsafe {
                    CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(parent) + 8)
                }
                unsafe { parentRightSlot.write(0, nearestLeft) }
            }
            node.UpdateNode(nearest.GetIndex(), node.GetCount() + nearest.GetCount(),
                refreshRegionInfo)
            let nodeAllocator = unsafe { this.read(0).nodeAllocator }
            nodeAllocator.Deallocate(CPointer<Unit>(nearest))
        }
        return MERGE_SUCCESS
    }

    // CartesianTree.cpp:13-90.
    func MergeInsertInternal(idx: Index, num: Count, refreshRegionInfo: Bool): Bool {
        let rootSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8)
        }
        var node = unsafe { rootSlot.read(0) }
        var nodeSlot = rootSlot
        let sud = unsafe { this.read(0).sud }
        var nodeSlotStack = LocalDeque(sud)
        let endIdx = idx + num
        while (true) {
            if (node.isNull()) {
                let nodeAllocator = unsafe { this.read(0).nodeAllocator }
                node = CPointer<CartesianNode>(nodeAllocator.Allocate())
                unsafe { node.write(0, CartesianNode(idx, num, refreshRegionInfo)) }
                unsafe { nodeSlot.write(0, node) }
                IncTotalCount(num)
                break
            }
            let result = MergeAt(node, idx, num, refreshRegionInfo)
            if (result == MERGE_SUCCESS) {
                break
            } else if (result == MERGE_ERROR) {
                return false
            }
            if (endIdx < node.GetIndex()) {
                nodeSlotStack.Push(CPointer<Unit>(nodeSlot))
                nodeSlot = CPointer<CPointer<CartesianNode>>(node)
                node = unsafe { nodeSlot.read(0) }
            } else if (idx > node.GetIndex() + node.GetCount()) {
                nodeSlotStack.Push(CPointer<Unit>(nodeSlot))
                nodeSlot = unsafe {
                    CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8)
                }
                node = unsafe { nodeSlot.read(0) }
            } else {
                return false
            }
        }
        while (!nodeSlotStack.Empty()) {
            nodeSlot = CPointer<CPointer<CartesianNode>>(nodeSlotStack.Top())
            nodeSlotStack.Pop()
            node = unsafe { nodeSlot.read(0) }
            if (endIdx < node.GetIndex()) {
                let left = unsafe { CPointer<CPointer<CartesianNode>>(node).read(0) }
                if (node.GetCount() < left.GetCount()) {
                    unsafe { nodeSlot.write(0, RotateLeftChild(node)) }
                } else {
                    break
                }
            } else if (idx > node.GetIndex() + node.GetCount()) {
                let right = unsafe {
                    CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8).read(0)
                }
                if (node.GetCount() < right.GetCount()) {
                    unsafe { nodeSlot.write(0, RotateRightChild(node)) }
                } else {
                    break
                }
            } else {
                return false
            }
        }
        return true
    }

    // CartesianTree.h:401-407.
    func RotateLeftChild(node: CPointer<CartesianNode>): CPointer<CartesianNode> {
        let nodeLeftSlot = CPointer<CPointer<CartesianNode>>(node)
        let newRoot = unsafe { nodeLeftSlot.read(0) }
        let newRootRightSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(newRoot) + 8)
        }
        unsafe {
            nodeLeftSlot.write(0, newRootRightSlot.read(0))
            newRootRightSlot.write(0, node)
        }
        return newRoot
    }

    // CartesianTree.h:410-416.
    func RotateRightChild(node: CPointer<CartesianNode>): CPointer<CartesianNode> {
        let nodeRightSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8)
        }
        let newRoot = unsafe { nodeRightSlot.read(0) }
        let newRootLeftSlot = CPointer<CPointer<CartesianNode>>(newRoot)
        unsafe {
            nodeRightSlot.write(0, newRootLeftSlot.read(0))
            newRootLeftSlot.write(0, node)
        }
        return newRoot
    }

    // CartesianTree.h:429-457.
    func LowerNode(node: CPointer<CartesianNode>): CPointer<CartesianNode> {
        let leftSlot = CPointer<CPointer<CartesianNode>>(node)
        let rightSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8)
        }
        let left = unsafe { leftSlot.read(0) }
        if (!left.isNull() && left.GetCount() > node.GetCount()) {
            let right = unsafe { rightSlot.read(0) }
            if (!right.isNull() && right.GetCount() > left.GetCount()) {
                let newRoot = RotateRightChild(node)
                let newRootLeftSlot = CPointer<CPointer<CartesianNode>>(newRoot)
                unsafe { newRootLeftSlot.write(0, LowerNode(newRootLeftSlot.read(0))) }
                return newRoot
            }
            let newRoot = RotateLeftChild(node)
            let newRootRightSlot = unsafe {
                CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(newRoot) + 8)
            }
            unsafe { newRootRightSlot.write(0, LowerNode(newRootRightSlot.read(0))) }
            return newRoot
        }
        let right = unsafe { rightSlot.read(0) }
        if (!right.isNull() && right.GetCount() > node.GetCount()) {
            let newRoot = RotateRightChild(node)
            let newRootLeftSlot = CPointer<CPointer<CartesianNode>>(newRoot)
            unsafe { newRootLeftSlot.write(0, LowerNode(newRootLeftSlot.read(0))) }
            return newRoot
        }
        return node
    }

    // CartesianTree.h:460-484. Returns the actual new slot containing the
    // lowered node, preserving Node*& rather than copied-node writeback.
    func LowerImproperNodeOnce(nodeSlot: CPointer<CPointer<CartesianNode>>):
        CPointer<CPointer<CartesianNode>> {
        let node = unsafe { nodeSlot.read(0) }
        let left = unsafe { CPointer<CPointer<CartesianNode>>(node).read(0) }
        if (!left.isNull()) {
            let right = unsafe {
                CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8).read(0)
            }
            if (!right.isNull() && right.GetCount() >= left.GetCount()) {
                let newRoot = RotateRightChild(node)
                unsafe { nodeSlot.write(0, newRoot) }
                return CPointer<CPointer<CartesianNode>>(newRoot)
            }
            let newRoot = RotateLeftChild(node)
            unsafe { nodeSlot.write(0, newRoot) }
            return unsafe {
                CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(newRoot) + 8)
            }
        }
        let right = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(node) + 8).read(0)
        }
        if (!right.isNull()) {
            let newRoot = RotateRightChild(node)
            unsafe { nodeSlot.write(0, newRoot) }
            return CPointer<CPointer<CartesianNode>>(newRoot)
        }
        return nodeSlot
    }

    // CartesianTree.h:488-495.
    func MaintainHeapPropertyForZeroNode(nodeSlot: CPointer<CPointer<CartesianNode>>):
        CPointer<CPointer<CartesianNode>> {
        var currentSlot = nodeSlot
        var current = unsafe { currentSlot.read(0) }
        var left = unsafe { CPointer<CPointer<CartesianNode>>(current).read(0) }
        var right = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(current) + 8).read(0)
        }
        while (!left.isNull() || !right.isNull()) {
            currentSlot = LowerImproperNodeOnce(currentSlot)
            current = unsafe { currentSlot.read(0) }
            left = unsafe { CPointer<CPointer<CartesianNode>>(current).read(0) }
            right = unsafe {
                CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(current) + 8).read(0)
            }
        }
        return currentSlot
    }

    // CartesianTree.h:499-506.
    func MaintainHeapPropertyForNonZeroNode(
        nodeSlot: CPointer<CPointer<CartesianNode>>): Unit {
        var currentSlot = nodeSlot
        while (!(unsafe { currentSlot.read(0) }).IsProperNode()) {
            currentSlot = LowerImproperNodeOnce(currentSlot)
        }
    }

    // CartesianTree.h:508-514.
    func RemoveZeroNode(nodeSlot: CPointer<CPointer<CartesianNode>>): Unit {
        let leafSlot = MaintainHeapPropertyForZeroNode(nodeSlot)
        let leaf = unsafe { leafSlot.read(0) }
        let leafLeft = unsafe { CPointer<CPointer<CartesianNode>>(leaf).read(0) }
        let leafRight = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(leaf) + 8).read(0)
        }
        if (!leafLeft.isNull() || !leafRight.isNull()) {
            unsafe { abort() }
        }
        let nodeAllocator = unsafe { this.read(0).nodeAllocator }
        nodeAllocator.Deallocate(CPointer<Unit>(leaf))
        unsafe { leafSlot.write(0, CPointer<CartesianNode>()) }
    }

    // CartesianTree.h:516-521.
    func RemoveNode(nodeSlot: CPointer<CPointer<CartesianNode>>): Unit {
        let node = unsafe { nodeSlot.read(0) }
        DecTotalCount(node.GetCount())
        node.ClearCount()
        RemoveZeroNode(nodeSlot)
    }

    // CartesianTree.h:524.
    func LowerNonZeroNode(nodeSlot: CPointer<CPointer<CartesianNode>>): Unit {
        MaintainHeapPropertyForNonZeroNode(nodeSlot)
    }

    // CartesianTree.cpp:148-187.
    func TakeUnitsImpl(num: Count, idx: CPointer<Index>,
        refreshRegionInfo: Bool): Bool {
        var it = ForwardIterator(this)
        var nodeSlot = it.Next()
        if (nodeSlot.isNull()) {
            return false
        }
        var node = unsafe { nodeSlot.read(0) }
        if (!node.isNull() && node.GetCount() < num) {
            return false
        }
        var nextNodeSlot = it.Next()
        while (!nextNodeSlot.isNull()) {
            let nextNode = unsafe { nextNodeSlot.read(0) }
            if (!nextNode.isNull() && nextNode.GetCount() < num) {
                break
            }
            nodeSlot = nextNodeSlot
            nextNodeSlot = it.Next()
        }
        node = unsafe { nodeSlot.read(0) }
        let nodeIndex = node.GetIndex()
        unsafe { idx.write(0, nodeIndex) }
        let nodeCount = node.GetCount()
        node.UpdateNode(nodeIndex + num, nodeCount - num, refreshRegionInfo)
        DecTotalCount(num)
        if (node.GetCount() == 0u32) {
            RemoveZeroNode(nodeSlot)
        } else {
            LowerNonZeroNode(nodeSlot)
        }
        return true
    }

    // CartesianTree.cpp:190-234.
    func FindBestFitLowAddrPtr(nodeSlot: CPointer<CPointer<CartesianNode>>, num: Count,
        initialBest: CPointer<CPointer<CartesianNode>>): CPointer<CPointer<CartesianNode>> {
        let sud = unsafe { this.read(0).sud }
        var stack = LocalDeque(sud)
        var best = initialBest
        if (!nodeSlot.isNull()) {
            let node = unsafe { nodeSlot.read(0) }
            if (!node.isNull() && node.GetCount() >= num) {
                stack.Push(CPointer<Unit>(nodeSlot))
            }
        }
        while (!stack.Empty()) {
            let current = CPointer<CPointer<CartesianNode>>(stack.Top())
            stack.Pop()
            if (current.isNull()) {
                continue
            }
            let currentNode = unsafe { current.read(0) }
            if (currentNode.isNull() || currentNode.GetCount() < num) {
                continue
            }
            if (best.isNull()) {
                best = current
            } else {
                let bestNode = unsafe { best.read(0) }
                if (currentNode.GetCount() < bestNode.GetCount() ||
                    (currentNode.GetCount() == bestNode.GetCount() &&
                    currentNode.GetIndex() < bestNode.GetIndex())) {
                    best = current
                }
            }
            let bestNode = unsafe { best.read(0) }
            if (bestNode.GetCount() == num) {
                let leftSlot = CPointer<CPointer<CartesianNode>>(currentNode)
                let left = unsafe { leftSlot.read(0) }
                if (!left.isNull() && left.GetCount() >= num) {
                    stack.Push(CPointer<Unit>(leftSlot))
                }
            } else {
                let rightSlot = unsafe {
                    CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(currentNode) + 8)
                }
                let right = unsafe { rightSlot.read(0) }
                if (!right.isNull() && right.GetCount() >= num) {
                    stack.Push(CPointer<Unit>(rightSlot))
                }
                let leftSlot = CPointer<CPointer<CartesianNode>>(currentNode)
                let left = unsafe { leftSlot.read(0) }
                if (!left.isNull() && left.GetCount() >= num) {
                    stack.Push(CPointer<Unit>(leftSlot))
                }
            }
        }
        return best
    }

    // CartesianTree.cpp:239-261.
    func TakeUnitsLowAddrImpl(num: Count, idx: CPointer<Index>,
        refreshRegionInfo: Bool): Bool {
        let rootSlot = unsafe {
            CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(this) + 8)
        }
        let nodeSlot = FindBestFitLowAddrPtr(rootSlot, num,
            CPointer<CPointer<CartesianNode>>())
        if (nodeSlot.isNull()) {
            return false
        }
        let node = unsafe { nodeSlot.read(0) }
        let nodeIndex = node.GetIndex()
        unsafe { idx.write(0, nodeIndex) }
        let nodeCount = node.GetCount()
        node.UpdateNode(nodeIndex + num, nodeCount - num, refreshRegionInfo)
        DecTotalCount(num)
        if (node.GetCount() == 0u32) {
            RemoveZeroNode(nodeSlot)
        } else {
            LowerNonZeroNode(nodeSlot)
        }
        return true
    }

    // CartesianTree.cpp:263-281.
    func AllocateLowestAddressFromNode(nodeSlot: CPointer<CPointer<CartesianNode>>,
        count: Count, index: CPointer<Index>): Bool {
        let node = unsafe { nodeSlot.read(0) }
        let nodeCount = node.GetCount()
        if (nodeCount < count) {
            return false
        }
        let nodeIndex = node.GetIndex()
        unsafe { index.write(0, nodeIndex) }
        node.UpdateNode(nodeIndex + count, nodeCount - count, false)
        DecTotalCount(count)
        if (node.GetCount() == 0u32) {
            RemoveZeroNode(nodeSlot)
        } else {
            LowerNonZeroNode(nodeSlot)
        }
        return true
    }
}
