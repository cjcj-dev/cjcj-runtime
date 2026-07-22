import rt.exception.*

func emit(name: String, bytes: Array<UInt8>): Unit {
    var storage = VArray<UInt8, $16>(repeat: 0u8)
    for (idx in 0..bytes.size) { storage[idx] = bytes[idx] }
    var cursor = unsafe { CPointer<UInt8>(inout storage) }
    let start = cursor.toUIntNative()
    let value = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout cursor) })
    println("ULEB ${name} ${value} ${cursor.toUIntNative() - start}")
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
    var abnormal: VArray<UInt32, $2> = [0x55555555u32, 0x12345678u32]
    let abnormalPtr = unsafe { CPointer<UInt8>(inout abnormal) }
    let normalPtr = unsafe { CPointer<UInt8>(CPointer<UInt32>(inout abnormal) + 1) }
    println("ABNORMAL ${IsAbnormalEHTable(CPointer<UInt8>())} ${IsAbnormalEHTable(abnormalPtr)} ${IsAbnormalEHTable(normalPtr)}")
    return 0
}
