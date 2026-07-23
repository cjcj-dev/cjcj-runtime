package rt.heap.allocator

foreign {
    func CJRT_TestSetupMarkedRegion(arena: CPointer<Unit>, liveInfo: CPointer<Unit>,
        bitmap: CPointer<Unit>, large: UInt8, markedOffset: Int64): CPointer<Unit>
    func CJRT_TestIsMarkedObjectAddress(region: CPointer<Unit>, object: CPointer<Unit>): UInt8
    func CJRT_TestIsMarkedObjectOffset(region: CPointer<Unit>, offset: UIntNative): UInt8
    func abort(): Unit
}

func CheckMarked(large: Bool, markedOffset: Int64, queryOffset: UIntNative): Unit {
    var arena = VArray<UInt64, $523>(repeat: 0)
    var liveInfo = VArray<UInt64, $4>(repeat: 0)
    var bitmap = VArray<UInt64, $16>(repeat: 0)
    let arenaPointer = unsafe { CPointer<Unit>(CPointer<UInt64>(inout arena)) }
    let region = unsafe { CJRT_TestSetupMarkedRegion(arenaPointer,
        CPointer<Unit>(CPointer<UInt64>(inout liveInfo)), CPointer<Unit>(CPointer<UInt64>(inout bitmap)),
        if (large) { 1u8 } else { 0u8 }, markedOffset) }
    let heapStart = arenaPointer.toUIntNative() + sizeOf<RegionInfo>()
    RegionInfo.Initialize(1, heapStart)
    let object = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(heapStart + queryOffset)) }
    let cppAddress = unsafe { CJRT_TestIsMarkedObjectAddress(region, object) }
    let cppOffset = unsafe { CJRT_TestIsMarkedObjectOffset(region, queryOffset) }
    let cjAddress = CPointer<RegionInfo>(region).IsMarkedObject(object)
    let cjOffset = CPointer<RegionInfo>(region).IsMarkedObject(queryOffset)
    println("REGIONINFO_MARKED large=${large} marked=${markedOffset} query=${queryOffset} " +
        "cpp=${cppAddress}/${cppOffset} cj=${cjAddress}/${cjOffset}")
    let expectedAddress = cppAddress != 0u8
    let expectedOffset = cppOffset != 0u8
    if (cjAddress != expectedAddress || cjOffset != expectedOffset) { unsafe { abort() } }
}

main(): Int64 {
    CheckMarked(true, -1, 0)
    CheckMarked(true, 0, 24)
    CheckMarked(false, -1, 0)
    CheckMarked(false, 24, 0)
    CheckMarked(false, 24, 24)
    CheckMarked(false, 520, 520)
    return 0
}
