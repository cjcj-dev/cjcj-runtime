package rt.exception

@When[arch == "arm"]
private type EHFrameArchUInt = UInt32

@When[arch != "arm"]
private type EHFrameArchUInt = UInt64

// Exception/EhFrameInfo.h:186-216. Stack-map values begin with a nibble tag:
// 0..11 are inline; 12..15 select the following 8/16/24/32 payload bits.
// `point` and `validPos` are caller-owned because adjacent values can share a byte.
@NoHeapAlloc
public func ReadEHFrameVarInt(point: CPointer<CPointer<UIntNative>>, validPos: CPointer<UInt32>): UInt32 {
    var p = unsafe { CPointer<UInt8>(point.read()) }
    var pos = unsafe { validPos.read() }
    let tag = UInt32(unsafe { p.read() } >> (4u32 * pos)) & 0x0fu32

    if (pos == 1u32) {
        p = unsafe { p + 1 }
        pos = 0u32
    } else {
        pos = 1u32
    }
    unsafe {
        point.write(CPointer<UIntNative>(p))
        validPos.write(pos)
    }

    if (tag <= 11u32) {
        return tag
    }

    var bitsLen = 32u32
    if (tag == 12u32) {
        bitsLen = 8u32
    } else if (tag == 13u32) {
        bitsLen = 16u32
    } else if (tag == 14u32) {
        bitsLen = 24u32
    }
    let bitsMask = if (bitsLen == 32u32) { UInt32.Max } else { (1u32 << bitsLen) - 1u32 }
    let value = UInt32(unsafe { CPointer<EHFrameArchUInt>(p).read() } >> (4u32 * pos)) & bitsMask
    p = unsafe { p + Int64(bitsLen >> 3u32) }
    unsafe { point.write(CPointer<UIntNative>(p)) }
    return value
}
