package rt.heap.allocator

import rt.base.RwLock

func Fail(code: Int64, message: String): Int64 {
    println("REGIONINFO_PROBE FAIL ${message}")
    return code
}

main(): Int64 {
    var layout = UnitMetadata()
    let layoutBase = unsafe { CPointer<UInt8>(inout layout).toUIntNative() }
    let allocPtrOffset = unsafe { CPointer<UInt8>(inout layout.allocPtr).toUIntNative() } - layoutBase
    let regionEndOffset = unsafe { CPointer<UInt8>(inout layout.regionEnd).toUIntNative() } - layoutBase
    let nextRegionIdxOffset = unsafe { CPointer<UInt8>(inout layout.nextRegionIdx).toUIntNative() } - layoutBase
    let prevRegionIdxOffset = unsafe { CPointer<UInt8>(inout layout.prevRegionIdx).toUIntNative() } - layoutBase
    let liveByteCountOffset = unsafe { CPointer<UInt8>(inout layout.liveByteCount).toUIntNative() } - layoutBase
    let rawPointerObjectCountOffset = unsafe {
        CPointer<UInt8>(inout layout.rawPointerObjectCount).toUIntNative()
    } - layoutBase
    let liveInfoOffset = unsafe { CPointer<UInt8>(inout layout.liveInfo).toUIntNative() } - layoutBase
    let liveInfo0Offset = unsafe { CPointer<UInt8>(inout layout.liveInfo0).toUIntNative() } - layoutBase
    let regionEnd0Offset = unsafe { CPointer<UInt8>(inout layout.regionEnd0).toUIntNative() } - layoutBase
    let routeInfoOffset = unsafe { CPointer<UInt8>(inout layout.routeInfo).toUIntNative() } - layoutBase
    let nextRegionIdx0Offset = unsafe { CPointer<UInt8>(inout layout.nextRegionIdx0).toUIntNative() } - layoutBase
    let unitRoleBitFieldOffset = unsafe {
        CPointer<UInt8>(inout layout.unitRoleBitField).toUIntNative()
    } - layoutBase
    let regionStateBitFieldOffset = unsafe {
        CPointer<UInt8>(inout layout.regionStateBitField).toUIntNative()
    } - layoutBase
    let routeStateOffset = unsafe { CPointer<UInt8>(inout layout.routeState).toUIntNative() } - layoutBase
    let rwLockOffset = unsafe { CPointer<UInt8>(inout layout.rwLock).toUIntNative() } - layoutBase

    println("REGIONINFO_LAYOUT sizeof=${sizeOf<UnitMetadata>()} allocPtr=${allocPtrOffset} " +
        "regionEnd=${regionEndOffset} nextRegionIdx=${nextRegionIdxOffset} " +
        "prevRegionIdx=${prevRegionIdxOffset} liveByteCount=${liveByteCountOffset} " +
        "rawPointerObjectCount=${rawPointerObjectCountOffset} liveInfo=${liveInfoOffset} " +
        "liveInfo0=${liveInfo0Offset} regionEnd0=${regionEnd0Offset} routeInfo=${routeInfoOffset} " +
        "nextRegionIdx0=${nextRegionIdx0Offset} unitRoleBitField=${unitRoleBitFieldOffset} " +
        "regionStateBitField=${regionStateBitFieldOffset} routeState=${routeStateOffset} " +
        "rwLock=${rwLockOffset}")

    if (sizeOf<BitFieldU8>() != 1 || sizeOf<BitFieldU16>() != 2 ||
        sizeOf<RwLock>() != 4 || sizeOf<UnitInfo>() != 88 || sizeOf<RegionInfo>() != 88 ||
        sizeOf<UnitInfo>() != sizeOf<UnitMetadata>() || sizeOf<RegionInfo>() != sizeOf<UnitMetadata>()) {
        return Fail(1, "descriptor sizes differ")
    }

    let totalUnitCount: UIntNative = 8
    let mappedSize = (totalUnitCount + 1) * RegionInfo.UNIT_SIZE
    var memMap = MemMap.MapMemory(mappedSize, mappedSize)
    let mapped = unsafe { memMap.read() }
    let mapBase = mapped.GetBaseAddr()
    let heapAddress = mapBase.toUIntNative() + RegionInfo.UNIT_SIZE
    RegionInfo.Initialize(totalUnitCount, heapAddress)

    let idx: UIntNative = 1
    let regionUnitCount: UIntNative = 2
    RegionInfo.InitFreeRegion(idx, regionUnitCount)
    let region = RegionInfo.GetRegionInfo(UInt32(idx))
    let regionStart = heapAddress + idx * RegionInfo.UNIT_SIZE
    let metadata = unsafe { region.read().metadata }

    if (RegionInfo.GetUnitRole(region) != FREE_UNITS ||
        RegionInfo.GetRegionType(region) != FREE_REGION || !RegionInfo.IsFreeRegion(region)) {
        return Fail(2, "role/type")
    }
    if (metadata.allocPtr != regionStart ||
        metadata.regionEnd != regionStart + regionUnitCount * RegionInfo.UNIT_SIZE) {
        return Fail(3, "allocPtr/regionEnd")
    }
    if (!metadata.liveInfo.isNull()) {
        return Fail(4, "liveInfo")
    }
    let stateBits = UInt64(metadata.regionStateBitField.fieldVal)
    let initializedFlagMask = (1u64 << UInt64(TRACE_REGION_FLAG)) |
        (1u64 << UInt64(MARKED_REGION_FLAG)) |
        (1u64 << UInt64(ENQUEUED_REGION_FLAG)) |
        (1u64 << UInt64(RESURRECTED_REGION_FLAG))
    if ((stateBits & initializedFlagMask) != 0u64) {
        return Fail(5, "region flags")
    }
    if (RegionInfo.GetRegionStart(region) != regionStart ||
        RegionInfo.GetRegionAllocPtr(region) != regionStart ||
        RegionInfo.GetRegionSize(region) != regionUnitCount * RegionInfo.UNIT_SIZE ||
        RegionInfo.GetUnitCount(region) != regionUnitCount) {
        return Fail(6, "region accessors")
    }

    let unitAddress = RegionInfo.GetUnitAddress(idx)
    if (UnitInfo.GetUnitIdxAt(unitAddress) != idx ||
        RegionInfo.GetRegionInfoAt(unitAddress).toUIntNative() != region.toUIntNative()) {
        return Fail(7, "unit address round-trip")
    }

    RegionInfo.SetRegionType(region, FROM_REGION)
    RegionInfo.SetTraceRegionFlag(region, 1u8)
    RegionInfo.SetMarkedRegionFlag(region, 1u8)
    RegionInfo.SetEnqueuedRegionFlag(region, 1u8)
    RegionInfo.SetResurrectedRegionFlag(region, 1u8)
    let before = unsafe { region.read().metadata.regionStateBitField.fieldVal }
    let neighboringBits = (UInt16(FROM_REGION) << UInt16(REGION_TYPE_FLAG)) |
        (1u16 << UInt16(TRACE_REGION_FLAG)) |
        (1u16 << UInt16(MARKED_REGION_FLAG)) |
        (1u16 << UInt16(ENQUEUED_REGION_FLAG)) |
        (1u16 << UInt16(RESURRECTED_REGION_FLAG))
    let inGhostBit = 1u16 << UInt16(IN_GHOST_FROM_REGION_FLAG)
    if (before != neighboringBits || (before & inGhostBit) != 0u16) {
        return Fail(8, "SetInGhostRegion neighbor seed")
    }
    RegionInfo.SetInGhostRegion(region, 1u8)
    if (unsafe { region.read().metadata.regionStateBitField.fieldVal } != (before | inGhostBit)) {
        return Fail(9, "SetInGhostRegion static set")
    }
    RegionInfo.SetInGhostRegion(region, 0u8)
    if (unsafe { region.read().metadata.regionStateBitField.fieldVal } != before) {
        return Fail(10, "SetInGhostRegion static clear")
    }
    region.SetInGhostRegion(1u8)
    if (unsafe { region.read().metadata.regionStateBitField.fieldVal } != (before | inGhostBit)) {
        return Fail(11, "SetInGhostRegion pointer set")
    }
    region.SetInGhostRegion(0u8)
    if (unsafe { region.read().metadata.regionStateBitField.fieldVal } != before) {
        return Fail(12, "SetInGhostRegion pointer clear")
    }

    RegionInfo.ReleaseUnits(idx, regionUnitCount)

    var bitFieldU8 = BitFieldU8(0u8)
    let bitFieldU8Ptr = unsafe { CPointer<BitFieldU8>(inout bitFieldU8) }
    BitFieldU8.SetAtomicValue(bitFieldU8Ptr, 1, 3, 5u8)
    if (BitFieldU8.GetAtomicValue(bitFieldU8Ptr, 1, 3) != 0x0au8) {
        return Fail(13, "BitFieldU8")
    }
    var bitFieldU16 = BitFieldU16(0u16)
    let bitFieldU16Ptr = unsafe { CPointer<BitFieldU16>(inout bitFieldU16) }
    BitFieldU16.SetAtomicValue(bitFieldU16Ptr, 4, 4, 9u16)
    if (BitFieldU16.GetAtomicValue(bitFieldU16Ptr, 4, 4) != 0x0090u16) {
        return Fail(14, "BitFieldU16")
    }

    var routeInfo = RouteInfo()
    routeInfo.SetRouteInfo(regionStart, to1used: 32u32)
    if (routeInfo.toRegion1StartAddress != regionStart || routeInfo.toRegion1UsedBytes != 32u32 ||
        routeInfo.toRegion2Idx != RouteInfo.INVALID_VALUE) {
        return Fail(15, "RouteInfo")
    }

    MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout memMap))
    println("REGIONINFO_PROBE PASS")
    return 0
}
