import rt.heap.allocator.*

main(): Int64 {
    let requestedSize: UIntNative = UIntNative(64 * 1024)
    var memMap = MemMap.MapMemory(requestedSize, requestedSize)
    let mapped = unsafe { memMap.read() }
    let base = mapped.GetBaseAddr()
    let size = mapped.GetMappedSize()
    let bytes = CPointer<UInt8>(base)

    unsafe {
        bytes.write(0, 0x5au8)
        bytes.write(Int64(requestedSize - UIntNative(1)), 0xa5u8)
    }
    if (unsafe { bytes.read(0) } != 0x5au8 ||
        unsafe { bytes.read(Int64(requestedSize - UIntNative(1))) } != 0xa5u8) {
        return 1
    }

    MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout memMap))
    if (!memMap.isNull()) {
        return 2
    }
    println("MEMMAP_PROBE PASS base=${base.toUIntNative()} size=${size}")
    return 0
}
