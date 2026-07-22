package eh.noheap

import rt.exception.*

@C
public func EHReadULEBRoot(data: CPointer<CPointer<UInt8>>): UInt64 {
    return ReadULEB128(data)
}

@C
public func EHAbnormalRoot(data: CPointer<UInt8>): Bool {
    return IsAbnormalEHTable(data)
}

@C
public func EHReadSLEBRoot(data: CPointer<CPointer<UInt8>>): Int64 {
    return ReadSLEB128(data)
}

@C
public func EHReadAbsPtrRoot(data: CPointer<UInt8>): CPointer<Unit> {
    return ReadAbsPtr(data)
}

@C
public func EHReadUData4Root(data: CPointer<UInt8>): CPointer<Unit> {
    return ReadUData4(data)
}

@C
public func EHReadIndir4Root(data: CPointer<UInt8>): CPointer<Unit> {
    return ReadIndirPcRelSData4(data)
}

@C
public func EHReadIndir8Root(data: CPointer<UInt8>): CPointer<Unit> {
    return ReadIndirPcRelSData8(data)
}

@C
public func EHFrameVarIntRoot(point: CPointer<CPointer<UIntNative>>, validPos: CPointer<UInt32>): UInt32 {
    return ReadEHFrameVarInt(point, validPos)
}

@C
public func EHTableScanRoot(table: CPointer<EHTable>, pc: CPointer<UInt32>, exceptionRef: CPointer<Unit>,
    startIp: CPointer<UInt32>, result: CPointer<ScanResult>): Unit {
    unsafe { table.read().ScanEHTable(pc, exceptionRef, startIp, result) }
}

@C
public func EHContextLayoutRoot(): UIntNative {
    return sizeOf<CalleeSavedRegisterContext>() + alignOf<CalleeSavedRegisterContext>()
}
