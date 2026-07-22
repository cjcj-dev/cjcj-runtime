package rt.heap.allocator

import rt.gc.*

@NoHeapAlloc
public func ForwardDataNoHeapRoot(manager: CPointer<ForwardDataManager>, region: CPointer<RegionInfo>): UIntNative {
    ForwardDataInitializeForCapacity(manager, 8192)
    let live = ForwardDataAllocateLiveInfo(manager)
    unsafe {
        CPointer<CPointer<Unit>>(CPointer<UInt8>(region) + 32).write(0, CPointer<Unit>(live))
        CPointer<CPointer<Unit>>(live).write(0, CPointer<Unit>(region))
    }
    let bitmap = ForwardDataAllocateRegionBitmap(manager, 8192)
    let _ = RegionBitmapMarkBits(bitmap, 0, 8, 8192)
    ForwardDataSetTagID(manager, 1u16)
    ForwardDataUnbindPrevious(manager)
    ForwardDataClearPrevious(manager)
    let result = RegionBitmapGetLiveBytes(bitmap)
    ForwardDataDestroy(manager)
    return UIntNative(result)
}
