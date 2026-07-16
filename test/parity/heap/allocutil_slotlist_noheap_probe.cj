package allocutil.slotlist.noheap

import rt.heap.allocator.SlotList

// Heap/Allocator/SlotList.h:21-27.
@NoHeapAlloc
public func SlotListPushFrontNoHeapRoot(slot: CPointer<Unit>): Unit {
    var list = SlotList()
    list.PushFront(slot)
}

// Heap/Allocator/SlotList.h:29-38.
@NoHeapAlloc
public func SlotListPopFrontNoHeapRoot(size: UIntNative): UIntNative {
    var list = SlotList()
    return list.PopFront(size)
}

// Heap/Allocator/SlotList.h:42-50.
@NoHeapAlloc
public func SlotListClearExtraContentNoHeapRoot(slot: CPointer<Unit>): Unit {
    let list = SlotList()
    list.ClearExtraContent(slot)
}
