import rt.exception.*

func emit(name: String, bytes: Array<UInt8>): Unit {
    var storage = VArray<UInt8, $16>(repeat: 0u8)
    for (idx in 0..bytes.size) { storage[idx] = bytes[idx] }
    var cursor = unsafe { CPointer<UInt8>(inout storage) }
    let start = cursor.toUIntNative()
    let value = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout cursor) })
    println("ULEB ${name} ${value} ${cursor.toUIntNative() - start}")
}

func emitSigned(name: String, bytes: Array<UInt8>): Unit {
    var storage = VArray<UInt8, $16>(repeat: 0u8)
    for (idx in 0..bytes.size) { storage[idx] = bytes[idx] }
    var cursor = unsafe { CPointer<UInt8>(inout storage) }
    let start = cursor.toUIntNative()
    let value = ReadSLEB128(unsafe { CPointer<CPointer<UInt8>>(inout cursor) })
    println("SLEB ${name} ${value} ${cursor.toUIntNative() - start}")
}

func emitFrame(name: String, bytes: Array<UInt8>, initialPos: UInt32): Unit {
    var storage = VArray<UInt8, $16>(repeat: 0u8)
    for (idx in 0..bytes.size) { storage[idx] = bytes[idx] }
    let start = unsafe { CPointer<UInt8>(inout storage) }
    var cursor = unsafe { CPointer<UIntNative>(start) }
    var validPos = initialPos
    let value = ReadEHFrameVarInt(unsafe { CPointer<CPointer<UIntNative>>(inout cursor) },
        unsafe { CPointer<UInt32>(inout validPos) })
    println("FRAME ${name} ${value} ${CPointer<UInt8>(cursor).toUIntNative() - start.toUIntNative()} ${validPos}")
}

main(): Int64 {
    var result = ScanResult()
    let base = unsafe { CPointer<UInt8>(inout result) }.toUIntNative()
    let typeOffset = unsafe { CPointer<UInt8>(inout result.typeIndex) }.toUIntNative() - base
    let landingOffset = unsafe { CPointer<UInt8>(inout result.landingPad) }.toUIntNative() - base
    let caughtOffset = unsafe { CPointer<UInt8>(inout result.isCaught) }.toUIntNative() - base
    println("SCAN_RESULT ${sizeOf<ScanResult>()} ${alignOf<ScanResult>()} ${typeOffset} ${landingOffset} ${caughtOffset} ${result.typeIndex} ${result.landingPad} ${result.isCaught}")
    println("TTYPE ${ABS_PTR} ${U_DATA_4} ${INDIR_PC_REL_S_DATA_4} ${INDIR_PC_REL_S_DATA_8}")
    emit("zero", [0x00u8])
    emit("one", [0x01u8])
    emit("127", [0x7fu8])
    emit("128", [0x80u8, 0x01u8])
    emit("624485", [0xe5u8, 0x8eu8, 0x26u8])
    emit("u32max", [0xffu8, 0xffu8, 0xffu8, 0xffu8, 0x0fu8])
    emit("u64max", [0xffu8, 0xffu8, 0xffu8, 0xffu8, 0xffu8, 0xffu8, 0xffu8, 0xffu8, 0xffu8, 0x01u8])
    emitSigned("zero", [0x00u8])
    emitSigned("minus1", [0x7fu8])
    emitSigned("63", [0x3fu8])
    emitSigned("minus64", [0x40u8])
    emitSigned("64", [0xc0u8, 0x00u8])
    emitSigned("minus65", [0xbfu8, 0x7fu8])
    emitSigned("minus624485", [0x9bu8, 0xf1u8, 0x59u8])

    var pointerData: VArray<UInt64, $4> = [8u64, 0x1122334455667788u64, 0u64, 0u64]
    let pointerBase = unsafe { CPointer<UInt8>(inout pointerData) }
    println("TREAD ${ReadAbsPtr(unsafe { pointerBase + 8 }).toUIntNative()} " +
        "${ReadUData4(unsafe { pointerBase + 8 }).toUIntNative()} " +
        "${ReadIndirPcRelSData4(pointerBase).toUIntNative()} " +
        "${ReadIndirPcRelSData8(pointerBase).toUIntNative()}")
    pointerData[0] = 0u64
    println("TREAD_ZERO ${ReadIndirPcRelSData4(pointerBase).isNull()}")

    emitFrame("inline_low", [0xa5u8], 0u32)
    emitFrame("inline_high", [0xa5u8], 1u32)
    emitFrame("u8_low", [0xbcu8, 0x0au8], 0u32)
    emitFrame("u16_high", [0xd0u8, 0x34u8, 0x12u8], 1u32)
    emitFrame("u24_low", [0xeeu8, 0xdeu8, 0xbcu8, 0x0au8], 0u32)
    emitFrame("u32_high", [0xf0u8, 0x78u8, 0x56u8, 0x34u8, 0x12u8], 1u32)
    var abnormal: VArray<UInt32, $2> = [0x55555555u32, 0x12345678u32]
    let abnormalPtr = unsafe { CPointer<UInt8>(inout abnormal) }
    let normalPtr = unsafe { CPointer<UInt8>(CPointer<UInt32>(inout abnormal) + 1) }
    println("ABNORMAL ${IsAbnormalEHTable(CPointer<UInt8>())} ${IsAbnormalEHTable(abnormalPtr)} ${IsAbnormalEHTable(normalPtr)}")

    var lsda = VArray<UInt8, $32>(repeat: 0u8)
    lsda[0] = 0u8; lsda[1] = UInt8(ABS_PTR); lsda[2] = 26u8
    lsda[3] = 0u8; lsda[4] = 8u8
    lsda[5] = 0u8; lsda[6] = 4u8; lsda[7] = 16u8; lsda[8] = 0u8
    lsda[9] = 4u8; lsda[10] = 4u8; lsda[11] = 32u8; lsda[12] = 1u8
    lsda[13] = 1u8; lsda[14] = 0u8
    let lsdaBase = unsafe { CPointer<UInt8>(inout lsda) }
    var table = EHTable(lsdaBase)
    let tableWords = unsafe { CPointer<CPointer<UInt8>>(inout table) }
    println("EHTABLE ${sizeOf<EHTable>()} ${alignOf<EHTable>()} " +
        "${unsafe { tableWords.read(0) }.toUIntNative() - lsdaBase.toUIntNative()} " +
        "${unsafe { tableWords.read(1) }.toUIntNative() - lsdaBase.toUIntNative()} " +
        "${unsafe { tableWords.read(2) }.toUIntNative() - lsdaBase.toUIntNative()} " +
        "${unsafe { tableWords.read(3) }.toUIntNative() - lsdaBase.toUIntNative()} " +
        "${unsafe { tableWords.read(4) }.toUIntNative() - lsdaBase.toUIntNative()}")
    var code = VArray<UInt32, $16>(repeat: 0u32)
    let codeStart = unsafe { CPointer<UInt32>(inout code) }
    var cleanup = ScanResult()
    table.ScanEHTable(unsafe { CPointer<UInt32>(CPointer<UInt8>(codeStart) + 3) }, CPointer<Unit>(), codeStart,
        unsafe { CPointer<ScanResult>(inout cleanup) })
    var caught = ScanResult()
    table.ScanEHTable(unsafe { CPointer<UInt32>(CPointer<UInt8>(codeStart) + 6) }, CPointer<Unit>(), codeStart,
        unsafe { CPointer<ScanResult>(inout caught) })
    println("EHSCAN ${cleanup.typeIndex} ${cleanup.landingPad - UInt64(codeStart.toUIntNative())} ${cleanup.isCaught} " +
        "${caught.typeIndex} ${caught.landingPad - UInt64(codeStart.toUIntNative())} ${caught.isCaught}")
    println("CALLEE_CONTEXT ${sizeOf<CalleeSavedRegisterContext>()} ${alignOf<CalleeSavedRegisterContext>()}")
    return 0
}
