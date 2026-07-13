package rt.common

// Common/Dataref.h:16-34. The type parameter is the C++ pointee type and does not add storage.
@C
public struct DataRefOffset32<T> where T <: CType {
    // Common/Dataref.h:21. The sole inline field is the signed 32-bit self-relative offset.
    public var refOffset: Int32

    // Common/Dataref.h:20-22. This is aggregate initialisation of the sole C++ field.
    public init(refOffset: Int32) {
        this.refOffset = refOffset
    }
}

// Common/Dataref.h:36-50. The type parameter is the C++ pointee type and does not add storage.
@C
public struct DataRefOffset64<T> where T <: CType {
    // Common/Dataref.h:37. The sole inline field is the signed 64-bit self-relative offset.
    public var refOffset: Int64

    // Common/Dataref.h:36-38. This is aggregate initialisation of the sole C++ field.
    public init(refOffset: Int64) {
        this.refOffset = refOffset
    }
}

// Common/Dataref.h:23-33. A pointer receiver preserves the address denoted by C++ `this`;
// a DataRefOffset32 value receiver would copy the wrapper before computing the relative address.
public func GetDataRef<T>(self: CPointer<DataRefOffset32<T>>): CPointer<T> where T <: CType {
    // Common/Dataref.h:26. Read the offset from the original inline wrapper object.
    let refOffset = unsafe { self.read().refOffset }
    // Common/Dataref.h:25-27,32. Zero is the encoded null reference.
    if (refOffset == 0) {
        return unsafe { CPointer<T>() }
    }
    // Common/Dataref.h:28-30. Sign-extend I32, add it to the wrapper address, then cast to T*.
    let ref = unsafe { CPointer<UInt8>(self) + Int64(refOffset) }
    return unsafe { CPointer<T>(ref) }
}

// Common/Dataref.h:39-49. A pointer receiver preserves the address denoted by C++ `this`;
// a DataRefOffset64 value receiver would copy the wrapper before computing the relative address.
public func GetDataRef<T>(self: CPointer<DataRefOffset64<T>>): CPointer<T> where T <: CType {
    // Common/Dataref.h:42. Read the offset from the original inline wrapper object.
    let refOffset = unsafe { self.read().refOffset }
    // Common/Dataref.h:41-43,48. Zero is the encoded null reference.
    if (refOffset == 0) {
        return unsafe { CPointer<T>() }
    }
    // Common/Dataref.h:44-46. Add signed I64 to the wrapper address, then cast to T*.
    let ref = unsafe { CPointer<UInt8>(self) + refOffset }
    return unsafe { CPointer<T>(ref) }
}
