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
private const SIGNED_FLAG: UInt8 = 0x40u8

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

// Exception/EhTable.cpp:68-88. Decode the signed action-table displacement,
// including the C++ 64-bit sign extension after the terminating byte.
@NoHeapAlloc
public func ReadSLEB128(data: CPointer<CPointer<UInt8>>): Int64 {
    var value = 0u64
    var shift = 0u64
    var byte = 0u8
    var p = unsafe { data.read() }
    do {
        byte = unsafe { p.read() }
        p = unsafe { p + 1 }
        value |= UInt64(byte & VALUE_MASK) << shift
        shift += SHIFT_LENGTH
    } while ((byte & BYTE_MAX_BIT) != 0u8)
    if (shift < 64u64 && (byte & SIGNED_FLAG) != 0u8) {
        value |= UInt64.Max << shift
    }
    unsafe { data.write(p) }
    return Int64(value)
}

// Exception/EhTable.cpp:29-33. Read a four-byte unsigned type-table entry and
// preserve its zero-extension into a native pointer value.
@NoHeapAlloc
public func ReadUData4(p: CPointer<UInt8>): CPointer<Unit> {
    let value = unsafe { CPointer<UInt32>(p).read() }
    return unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(UInt64(value))) }
}

// Exception/EhTable.cpp:35-44. The encoded UInt32 displacement is relative to
// its own address; zero is the distinguished null catch-all entry.
@NoHeapAlloc
public func ReadIndirPcRelSData4(p: CPointer<UInt8>): CPointer<Unit> {
    let offset = unsafe { CPointer<UInt32>(p).read() }
    if (offset == 0u32) {
        return CPointer<Unit>()
    }
    let address = unsafe { p + Int64(UInt64(offset)) }
    let value = unsafe { CPointer<UInt64>(address).read() }
    return unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(value)) }
}

// Exception/EhTable.cpp:46-51. The eight-byte encoding has no zero-offset
// special case in the C++ implementation.
@NoHeapAlloc
public func ReadIndirPcRelSData8(p: CPointer<UInt8>): CPointer<Unit> {
    let offset = unsafe { CPointer<UInt64>(p).read() }
    let address = unsafe { p + Int64(offset) }
    let value = unsafe { CPointer<UInt64>(address).read() }
    return unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(value)) }
}

// Exception/EhTable.cpp:17-27. ARM32 stores a signed GOT-relative displacement;
// every other supported target stores the absolute eight-byte pointer value.
@When[arch == "arm"]
@NoHeapAlloc
public func ReadAbsPtr(p: CPointer<UInt8>): CPointer<Unit> {
    let offset = unsafe { CPointer<Int32>(p).read() }
    let address = unsafe { p + Int64(offset) }
    let value = unsafe { CPointer<UInt32>(address).read() }
    return unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(UInt64(value))) }
}

@When[arch != "arm"]
@NoHeapAlloc
public func ReadAbsPtr(p: CPointer<UInt8>): CPointer<Unit> {
    let value = unsafe { CPointer<UInt64>(p).read() }
    return unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(value)) }
}

// Exception/EhTable.h:66-72. Null and the compatibility sentinel both mark
// an abnormal table; non-null memory is read as the header's UInt32 tag.
@NoHeapAlloc
public func IsAbnormalEHTable(lsda: CPointer<UInt8>): Bool {
    return lsda.isNull() || unsafe { CPointer<UInt32>(lsda).read() == ABNORMAL_EH_TABLE_TAG }
}
