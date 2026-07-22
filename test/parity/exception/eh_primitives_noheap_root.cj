package eh.noheap

import rt.exception.*

public CFunc func EHReadULEBRoot(data: CPointer<CPointer<UInt8>>): UInt64 {
    return ReadULEB128(data)
}

public CFunc func EHAbnormalRoot(data: CPointer<UInt8>): Bool {
    return IsAbnormalEHTable(data)
}
