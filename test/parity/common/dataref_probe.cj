import rt.common.*

// Common/Dataref.h:16-50. Compute wire layout and exercise the actual typed Cangjie GetDataRef ports.
main(): Int64 {
    // Common/Dataref.h:20-21,36-37. Compute size, alignment, and the sole field offset at runtime.
    var layout32u8 = DataRefOffset32(0)
    let layout32u8Base = unsafe {
        CPointer<UInt8>(CPointer<DataRefOffset32>(inout layout32u8)).toUIntNative()
    }
    let layout32u8Field = unsafe { CPointer<UInt8>(CPointer<Int32>(inout layout32u8.refOffset)).toUIntNative() }
    let layout32u8Offset = layout32u8Field - layout32u8Base
    var layout64u8 = DataRefOffset64(0)
    let layout64u8Base = unsafe {
        CPointer<UInt8>(CPointer<DataRefOffset64>(inout layout64u8)).toUIntNative()
    }
    let layout64u8Field = unsafe { CPointer<UInt8>(CPointer<Int64>(inout layout64u8.refOffset)).toUIntNative() }
    let layout64u8Offset = layout64u8Field - layout64u8Base
    println("DATAREF_LAYOUT d32_size=${sizeOf<DataRefOffset32>()} " +
        "d32_align=${alignOf<DataRefOffset32>()} d32_refOffset=${layout32u8Offset} " +
        "d64_size=${sizeOf<DataRefOffset64>()} d64_align=${alignOf<DataRefOffset64>()} " +
        "d64_refOffset=${layout64u8Offset}")

    // Common/Dataref.h:20-21,36-37. A second pointee type proves T contributes no inline storage.
    var layout32u64 = DataRefOffset32(0)
    let layout32u64Base = unsafe {
        CPointer<UInt8>(CPointer<DataRefOffset32>(inout layout32u64)).toUIntNative()
    }
    let layout32u64Field = unsafe { CPointer<UInt8>(CPointer<Int32>(inout layout32u64.refOffset)).toUIntNative() }
    let layout32u64Offset = layout32u64Field - layout32u64Base
    var layout64u64 = DataRefOffset64(0)
    let layout64u64Base = unsafe {
        CPointer<UInt8>(CPointer<DataRefOffset64>(inout layout64u64)).toUIntNative()
    }
    let layout64u64Field = unsafe { CPointer<UInt8>(CPointer<Int64>(inout layout64u64.refOffset)).toUIntNative() }
    let layout64u64Offset = layout64u64Field - layout64u64Base
    println("DATAREF_LAYOUT_T d32_u64_size=${sizeOf<DataRefOffset32>()} " +
        "d32_u64_align=${alignOf<DataRefOffset32>()} d32_u64_refOffset=${layout32u64Offset} " +
        "d64_u64_size=${sizeOf<DataRefOffset64>()} " +
        "d64_u64_align=${alignOf<DataRefOffset64>()} d64_u64_refOffset=${layout64u64Offset}")

    // Common/Dataref.h:28-30,44-46. Align a stack buffer, then place wrappers at nonzero offsets.
    var storage = VArray<UInt8, $272>(repeat: 0u8)
    let rawStorage = unsafe { CPointer<UInt8>(inout storage) }
    let rawAddress = unsafe { rawStorage.toUIntNative() }
    let alignmentAdjustment = Int64((8 - (rawAddress % 8)) % 8)
    let base = unsafe { rawStorage + alignmentAdjustment }

    // Common/Dataref.h:20-33. DataRefOffset32<UInt8> at base+20 (4-aligned, deliberately not 8-aligned).
    let d32u8Wrapper = unsafe { CPointer<DataRefOffset32>(base + 20) }
    unsafe { d32u8Wrapper.write(DataRefOffset32(0)) }
    let d32u8Zero = unsafe { GetDataRef<UInt8>(d32u8Wrapper) }
    let d32u8ZeroNull = if (unsafe { d32u8Zero.isNull() }) { 1 } else { 0 }
    println("DATAREF_CASE type=d32_u8 kind=zero null=${d32u8ZeroNull}")
    unsafe { d32u8Wrapper.write(DataRefOffset32(13)) }
    let d32u8Positive = unsafe { GetDataRef<UInt8>(d32u8Wrapper) }
    let d32u8PositiveTarget = unsafe { CPointer<UInt8>(base + 33) }
    let d32u8PositiveAddress = unsafe { d32u8Positive.toUIntNative() }
    let d32u8WrapperAddress = unsafe { d32u8Wrapper.toUIntNative() }
    let d32u8PositiveDelta = Int64(d32u8PositiveAddress - d32u8WrapperAddress)
    let d32u8PositiveExact = if (unsafe { d32u8Positive.toUIntNative() == d32u8PositiveTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d32_u8 kind=positive exact=${d32u8PositiveExact} delta=${d32u8PositiveDelta}")
    unsafe { d32u8Wrapper.write(DataRefOffset32(-9)) }
    let d32u8Negative = unsafe { GetDataRef<UInt8>(d32u8Wrapper) }
    let d32u8NegativeTarget = unsafe { CPointer<UInt8>(base + 11) }
    let d32u8NegativeAddress = unsafe { d32u8Negative.toUIntNative() }
    let d32u8NegativeDelta = -Int64(d32u8WrapperAddress - d32u8NegativeAddress)
    let d32u8NegativeExact = if (unsafe { d32u8Negative.toUIntNative() == d32u8NegativeTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d32_u8 kind=negative exact=${d32u8NegativeExact} delta=${d32u8NegativeDelta}")

    // Common/Dataref.h:20-33. DataRefOffset32<UInt64> proves the pointee type does not change semantics.
    let d32u64Wrapper = unsafe { CPointer<DataRefOffset32>(base + 52) }
    unsafe { d32u64Wrapper.write(DataRefOffset32(0)) }
    let d32u64Zero = unsafe { GetDataRef<UInt64>(d32u64Wrapper) }
    let d32u64ZeroNull = if (unsafe { d32u64Zero.isNull() }) { 1 } else { 0 }
    println("DATAREF_CASE type=d32_u64 kind=zero null=${d32u64ZeroNull}")
    unsafe { d32u64Wrapper.write(DataRefOffset32(36)) }
    let d32u64Positive = unsafe { GetDataRef<UInt64>(d32u64Wrapper) }
    let d32u64PositiveTarget = unsafe { CPointer<UInt64>(base + 88) }
    let d32u64PositiveAddress = unsafe { d32u64Positive.toUIntNative() }
    let d32u64WrapperAddress = unsafe { d32u64Wrapper.toUIntNative() }
    let d32u64PositiveDelta = Int64(d32u64PositiveAddress - d32u64WrapperAddress)
    let d32u64PositiveExact = if (unsafe { d32u64Positive.toUIntNative() == d32u64PositiveTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d32_u64 kind=positive exact=${d32u64PositiveExact} delta=${d32u64PositiveDelta}")
    unsafe { d32u64Wrapper.write(DataRefOffset32(-28)) }
    let d32u64Negative = unsafe { GetDataRef<UInt64>(d32u64Wrapper) }
    let d32u64NegativeTarget = unsafe { CPointer<UInt64>(base + 24) }
    let d32u64NegativeAddress = unsafe { d32u64Negative.toUIntNative() }
    let d32u64NegativeDelta = -Int64(d32u64WrapperAddress - d32u64NegativeAddress)
    let d32u64NegativeExact = if (unsafe { d32u64Negative.toUIntNative() == d32u64NegativeTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d32_u64 kind=negative exact=${d32u64NegativeExact} delta=${d32u64NegativeDelta}")

    // Common/Dataref.h:36-49. DataRefOffset64<UInt8> at a nonzero aligned buffer position.
    let d64u8Wrapper = unsafe { CPointer<DataRefOffset64>(base + 40) }
    unsafe { d64u8Wrapper.write(DataRefOffset64(0)) }
    let d64u8Zero = unsafe { GetDataRef<UInt8>(d64u8Wrapper) }
    let d64u8ZeroNull = if (unsafe { d64u8Zero.isNull() }) { 1 } else { 0 }
    println("DATAREF_CASE type=d64_u8 kind=zero null=${d64u8ZeroNull}")
    unsafe { d64u8Wrapper.write(DataRefOffset64(17)) }
    let d64u8Positive = unsafe { GetDataRef<UInt8>(d64u8Wrapper) }
    let d64u8PositiveTarget = unsafe { CPointer<UInt8>(base + 57) }
    let d64u8PositiveAddress = unsafe { d64u8Positive.toUIntNative() }
    let d64u8WrapperAddress = unsafe { d64u8Wrapper.toUIntNative() }
    let d64u8PositiveDelta = Int64(d64u8PositiveAddress - d64u8WrapperAddress)
    let d64u8PositiveExact = if (unsafe { d64u8Positive.toUIntNative() == d64u8PositiveTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d64_u8 kind=positive exact=${d64u8PositiveExact} delta=${d64u8PositiveDelta}")
    unsafe { d64u8Wrapper.write(DataRefOffset64(-11)) }
    let d64u8Negative = unsafe { GetDataRef<UInt8>(d64u8Wrapper) }
    let d64u8NegativeTarget = unsafe { CPointer<UInt8>(base + 29) }
    let d64u8NegativeAddress = unsafe { d64u8Negative.toUIntNative() }
    let d64u8NegativeDelta = -Int64(d64u8WrapperAddress - d64u8NegativeAddress)
    let d64u8NegativeExact = if (unsafe { d64u8Negative.toUIntNative() == d64u8NegativeTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d64_u8 kind=negative exact=${d64u8NegativeExact} delta=${d64u8NegativeDelta}")

    // Common/Dataref.h:36-49. DataRefOffset64<UInt64> proves the pointee type does not change semantics.
    let d64u64Wrapper = unsafe { CPointer<DataRefOffset64>(base + 72) }
    unsafe { d64u64Wrapper.write(DataRefOffset64(0)) }
    let d64u64Zero = unsafe { GetDataRef<UInt64>(d64u64Wrapper) }
    let d64u64ZeroNull = if (unsafe { d64u64Zero.isNull() }) { 1 } else { 0 }
    println("DATAREF_CASE type=d64_u64 kind=zero null=${d64u64ZeroNull}")
    unsafe { d64u64Wrapper.write(DataRefOffset64(32)) }
    let d64u64Positive = unsafe { GetDataRef<UInt64>(d64u64Wrapper) }
    let d64u64PositiveTarget = unsafe { CPointer<UInt64>(base + 104) }
    let d64u64PositiveAddress = unsafe { d64u64Positive.toUIntNative() }
    let d64u64WrapperAddress = unsafe { d64u64Wrapper.toUIntNative() }
    let d64u64PositiveDelta = Int64(d64u64PositiveAddress - d64u64WrapperAddress)
    let d64u64PositiveExact = if (unsafe { d64u64Positive.toUIntNative() == d64u64PositiveTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d64_u64 kind=positive exact=${d64u64PositiveExact} delta=${d64u64PositiveDelta}")
    unsafe { d64u64Wrapper.write(DataRefOffset64(-40)) }
    let d64u64Negative = unsafe { GetDataRef<UInt64>(d64u64Wrapper) }
    let d64u64NegativeTarget = unsafe { CPointer<UInt64>(base + 32) }
    let d64u64NegativeAddress = unsafe { d64u64Negative.toUIntNative() }
    let d64u64NegativeDelta = -Int64(d64u64WrapperAddress - d64u64NegativeAddress)
    let d64u64NegativeExact = if (unsafe { d64u64Negative.toUIntNative() == d64u64NegativeTarget.toUIntNative() }) {
        1
    } else {
        0
    }
    println("DATAREF_CASE type=d64_u64 kind=negative exact=${d64u64NegativeExact} delta=${d64u64NegativeDelta}")
    return 0
}
