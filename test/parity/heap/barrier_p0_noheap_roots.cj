package rt.heap.allocator

import rt.objectmodel.*

// Common/BaseObject.cpp:139-150.
@FastNative
@NoHeapAlloc
public func BarrierP0BaseObjectSizeRoot(object: CPointer<BaseObject>): UIntNative {
    return BaseObjectGetSize(object)
}

// Heap/Allocator/RegionInfo.h:395-406.
@FastNative
@NoHeapAlloc
public func BarrierP0MarkedObjectRoot(region: CPointer<RegionInfo>, object: CPointer<Unit>): Bool {
    return region.IsMarkedObject(object)
}

// Heap/Allocator/RegionInfo.h:408-418.
@FastNative
@NoHeapAlloc
public func BarrierP0MarkedOffsetRoot(region: CPointer<RegionInfo>, offset: UIntNative): Bool {
    return region.IsMarkedObject(offset)
}
