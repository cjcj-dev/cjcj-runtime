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
