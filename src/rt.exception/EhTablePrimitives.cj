package rt.exception

// Exception/EhTable.h:14-38. The scan result is an inline native record;
// C++ value-initialization sets all three fields to zero/false.
@C
public struct ScanResult {
    public var typeIndex: UInt64
    public var landingPad: UInt64
    public var isCaught: Bool

    public init() {
        typeIndex = 0u64
        landingPad = 0u64
        isCaught = false
    }
}

// Exception/EhTable.h:53-59. C++ scoped-enum values used in LSDA bytes.
public type TTypeEncoding = Int32
public const ABS_PTR: TTypeEncoding = 0
public const U_DATA_4: TTypeEncoding = 3
public const INDIR_PC_REL_S_DATA_4: TTypeEncoding = 155
public const INDIR_PC_REL_S_DATA_8: TTypeEncoding = 156

private const ABNORMAL_EH_TABLE_TAG: UInt32 = 0x55555555u32
private const SHIFT_LENGTH: UInt64 = 7u64
private const VALUE_MASK: UInt8 = 0x7fu8
private const BYTE_MAX_BIT: UInt8 = 0x80u8

// Exception/EhTable.cpp:52-65. Decode one unsigned LEB128 value and advance
// the caller-owned byte pointer exactly past the terminating byte.
@NoHeapAlloc
public func ReadULEB128(data: CPointer<CPointer<UInt8>>): UInt64 {
    var value = 0u64
    var shift = 0u64
    var byte = 0u8
    var p = unsafe { data.read() }
    do {
        byte = unsafe { p.read() }
        p = unsafe { p + 1 }
        // The C++ left operand is promoted from uint8_t to signed int before
        // shifting, then sign-extended into uint64_t by |=. Preserve that
        // published behavior for fifth-byte values whose bit 31 becomes set.
        let promoted = Int32(UInt32(byte & VALUE_MASK) << UInt32(shift & 31u64))
        value |= UInt64(Int64(promoted))
        shift += SHIFT_LENGTH
    } while ((byte & BYTE_MAX_BIT) != 0u8)
    unsafe { data.write(p) }
    return value
}

// Exception/EhTable.h:66-72. Null and the compatibility sentinel both mark
// an abnormal table; non-null memory is read as the header's UInt32 tag.
@NoHeapAlloc
public func IsAbnormalEHTable(lsda: CPointer<UInt8>): Bool {
    return lsda.isNull() || unsafe { CPointer<UInt32>(lsda).read() == ABNORMAL_EH_TABLE_TAG }
}
