package rt.heap.allocator

// AllocBuffer.h:20-63. One operation root reaches every ported data-plane
// entry; emitted static initializers are added independently by the closure gate.
@NoHeapAlloc
public func FreshAllocBufferDataPlane(buffer: CPointer<AllocBuffer>, region: CPointer<RegionInfo>,
    root: CPointer<Unit>, stack: CPointer<Unit>): UIntNative {
    AllocBuffer.Construct(buffer)
    var bits = buffer.GetRegion().toUIntNative()
    bits = bits ^ buffer.GetPreparedRegion().toUIntNative()
    buffer.SetRegion(region)
    buffer.ClearRegion()
    if (buffer.SetPreparedRegion(region)) { bits = bits ^ 1 }
    buffer.PushRoot(root)
    buffer.MergeRoots(stack)
    return bits
}
