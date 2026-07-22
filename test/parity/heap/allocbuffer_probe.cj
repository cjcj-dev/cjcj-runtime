package rt.heap.allocator

foreign {
    func CJRT_TestAllocBufferWorkStackNew(): CPointer<Unit>
    func CJRT_TestAllocBufferWorkStackDelete(stack: CPointer<Unit>): Unit
    func CJRT_TestAllocBufferWorkStackEmpty(stack: CPointer<Unit>): Int32
    func CJRT_TestAllocBufferWorkStackBack(stack: CPointer<Unit>): CPointer<Unit>
    func CJRT_TestAllocBufferWorkStackPop(stack: CPointer<Unit>): Unit
    func CJRT_TestAllocBufferRootsEmpty(storage: CPointer<Unit>): Int32
    func CJRT_TestAllocBufferDestroyRoots(storage: CPointer<Unit>): Unit
    func CJRT_TestAllocBufferNames(buffer: CPointer<AllocBuffer>): Int32
}

private func SamePointer(left: CPointer<Unit>, right: CPointer<Unit>): Bool {
    return left.toUIntNative() == right.toUIntNative()
}

@When[!debug]
private func ExerciseClear(buffer: CPointer<AllocBuffer>, root: CPointer<Unit>,
    nullRegion: CPointer<RegionInfo>): Bool {
    buffer.SetRegion(CPointer<RegionInfo>(root))
    var result = buffer.GetRegion().toUIntNative() == root.toUIntNative()
    buffer.ClearRegion()
    result = result && buffer.GetRegion().toUIntNative() == nullRegion.toUIntNative()
    buffer.ClearRegion()
    return result && buffer.GetRegion().toUIntNative() == nullRegion.toUIntNative()
}

// A fabricated pointer cannot supply RegionInfo fields to the debug DLOG
// arguments. The debug executable covers the sentinel early return; the
// non-sentinel branch remains rooted and scanned by the noheap closure probe.
@When[debug]
private func ExerciseClear(buffer: CPointer<AllocBuffer>, root: CPointer<Unit>,
    nullRegion: CPointer<RegionInfo>): Bool {
    buffer.SetRegion(CPointer<RegionInfo>(root))
    var result = buffer.GetRegion().toUIntNative() == root.toUIntNative()
    buffer.SetRegion(nullRegion)
    buffer.ClearRegion()
    return result && buffer.GetRegion().toUIntNative() == nullRegion.toUIntNative()
}

main(): Int64 {
    let storage = unsafe { malloc(sizeOf<AllocBuffer>()) }
    let buffer = CPointer<AllocBuffer>(storage)
    AllocBuffer.Construct(buffer)
    let nullRegion = unsafe { CJRT_AllocBufferNullRegion() }
    let largeOffset: Int64 = 16 + Int64(sizeOf<RegionList>())
    let rootsOffset: Int64 = 16 + 2 * Int64(sizeOf<RegionList>())
    let rootsStorage = unsafe { CPointer<Unit>(CPointer<UInt8>(buffer) + rootsOffset) }

    let initialized = buffer.GetRegion().toUIntNative() == nullRegion.toUIntNative() &&
        buffer.GetPreparedRegion().isNull() &&
        unsafe { CJRT_TestAllocBufferRootsEmpty(rootsStorage) != 0 }
    let names = unsafe { CJRT_TestAllocBufferNames(buffer) != 0 }

    let root1 = unsafe { CPointer<Unit>(CPointer<UInt8>() + 0x1110) }
    let root2 = unsafe { CPointer<Unit>(CPointer<UInt8>() + 0x2220) }
    let root3 = unsafe { CPointer<Unit>(CPointer<UInt8>() + 0x3330) }
    let region = ExerciseClear(buffer, root1, nullRegion)

    var prepared = buffer.SetPreparedRegion(CPointer<RegionInfo>(root2))
    prepared = prepared && buffer.GetPreparedRegion().toUIntNative() == root2.toUIntNative()
    prepared = prepared && !buffer.SetPreparedRegion(CPointer<RegionInfo>(root3))
    prepared = prepared && buffer.GetPreparedRegion().toUIntNative() == root2.toUIntNative()

    let workStack = unsafe { CJRT_TestAllocBufferWorkStackNew() }
    buffer.PushRoot(root1)
    buffer.PushRoot(root2)
    buffer.PushRoot(root3)
    buffer.MergeRoots(workStack)
    var roots = unsafe { CJRT_TestAllocBufferRootsEmpty(rootsStorage) != 0 }
    roots = roots && SamePointer(unsafe { CJRT_TestAllocBufferWorkStackBack(workStack) }, root3)
    unsafe { CJRT_TestAllocBufferWorkStackPop(workStack) }
    roots = roots && SamePointer(unsafe { CJRT_TestAllocBufferWorkStackBack(workStack) }, root2)
    unsafe { CJRT_TestAllocBufferWorkStackPop(workStack) }
    roots = roots && SamePointer(unsafe { CJRT_TestAllocBufferWorkStackBack(workStack) }, root1)
    unsafe { CJRT_TestAllocBufferWorkStackPop(workStack) }
    roots = roots && unsafe { CJRT_TestAllocBufferWorkStackEmpty(workStack) != 0 }
    buffer.MergeRoots(workStack)
    roots = roots && unsafe { CJRT_TestAllocBufferWorkStackEmpty(workStack) != 0 }

    println("ALLOC_BUFFER_LAYOUT size=${sizeOf<AllocBuffer>()} align=${alignOf<AllocBuffer>()} " +
        "tlRegion=0 prepared=8 raw=16 large=${largeOffset} roots=${rootsOffset}")
    println("ALLOC_BUFFER_PARITY init=${if (initialized) { 1 } else { 0 }} " +
        "names=${if (names) { 1 } else { 0 }} region=${if (region) { 1 } else { 0 }} " +
        "prepared=${if (prepared) { 1 } else { 0 }} roots=${if (roots) { 1 } else { 0 }}")

    unsafe {
        CJRT_TestAllocBufferWorkStackDelete(workStack)
        CJRT_TestAllocBufferDestroyRoots(rootsStorage)
        RegionList.Destroy(CPointer<RegionList>(CPointer<UInt8>(buffer) + largeOffset))
        RegionList.Destroy(CPointer<RegionList>(CPointer<UInt8>(buffer) + 16))
        free(storage)
    }
    return if (initialized && names && region && prepared && roots &&
        sizeOf<AllocBuffer>() == 16 + 2 * sizeOf<RegionList>() + 24 &&
        alignOf<AllocBuffer>() == 8) { 0 } else { 1 }
}
