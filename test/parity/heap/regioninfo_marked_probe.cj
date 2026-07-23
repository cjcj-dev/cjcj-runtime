package rt.heap.allocator

func CheckMarked(large: Bool, markedOffset: Int64, queryOffset: UIntNative): Unit {
    let unitCount: UIntNative = 10
    let metadataSize = unitCount * sizeOf<UnitInfo>()
    let arenaSize = metadataSize + unitCount * RegionInfo.UNIT_SIZE
    let arena = CPointer<UInt8>(unsafe { malloc(arenaSize) })
    unsafe { let _ = memset(CPointer<Unit>(arena), 0, arenaSize) }
    let heapStart = unsafe { (arena + Int64(metadataSize)).toUIntNative() }
    RegionInfo.Initialize(unitCount, heapStart)
    let region = RegionInfo.InitRegion(4, 1,
        if (large) { LARGE_SIZED_UNITS } else { SMALL_SIZED_UNITS })

    var liveInfo = LiveInfo()
    var bitmapStorage = VArray<UInt64, $16>(repeat: 0)
    if (large) {
        region.SetMarkedRegionFlag(if (markedOffset >= 0) { 1u8 } else { 0u8 })
    } else if (markedOffset >= 0) {
        let bitmap = unsafe { CPointer<RegionBitmap>(CPointer<UInt64>(inout bitmapStorage)) }
        RegionBitmapConstruct(bitmap, UInt64(RegionInfo.UNIT_SIZE))
        let _ = RegionBitmapMarkBits(bitmap, UInt64(markedOffset), 8u64, UInt64(RegionInfo.UNIT_SIZE))
        liveInfo.bindedRegion = CPointer<Unit>(region)
        liveInfo.markBitmap = bitmap
        let liveInfoPointer = unsafe { CPointer<LiveInfo>(inout liveInfo) }
        unsafe { CPointer<CPointer<LiveInfo>>(CPointer<UInt8>(region) + 32).write(0, liveInfoPointer) }
    }

    let object = unsafe {
        CPointer<Unit>(CPointer<UInt8>() + Int64(heapStart + 4 * RegionInfo.UNIT_SIZE + queryOffset))
    }
    let address = region.IsMarkedObject(object)
    let offset = region.IsMarkedObject(queryOffset)
    println("REGIONINFO_MARKED large=${if (large) { 1 } else { 0 }} marked=${markedOffset} " +
        "query=${queryOffset} address=${if (address) { 1 } else { 0 }} offset=${if (offset) { 1 } else { 0 }}")
    unsafe { free(CPointer<Unit>(arena)) }
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
