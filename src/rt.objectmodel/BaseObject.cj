package rt.objectmodel

import std.overflow.*

// Common/BaseObject.h:18-101. The only inline owner is the eight-byte StateWord.
@C
public struct BaseObject {
    var stateWordBits: UInt64
    public init(stateWordBits!: UInt64 = 0) { this.stateWordBits = stateWordBits }
}

// ObjectModel/MClass.h:558-762 is packed to four bytes off ARM and naturally
// four-byte aligned on ARM. This slice uses the target-exact live field offsets
// without claiming ownership of the remaining metadata fields.
@C
public struct TypeInfo {
    var opaque: UInt8
    public init(opaque!: UInt8 = 0) { this.opaque = opaque }
}

// ObjectModel/MArray.h:17-56. StateWord and MIndex make the complete header 16 bytes.
@C
public struct MArray {
    var stateWordBits: UInt64
    var length: UInt64
    public init(stateWordBits!: UInt64 = 0, length!: UInt64 = 0) {
        this.stateWordBits = stateWordBits
        this.length = length
    }
}

private const TYPE_KIND_CLASS: Int8 = -128
private const TYPE_KIND_INTERFACE: Int8 = -127
private const TYPE_KIND_RAWARRAY: Int8 = -126
private const TYPE_KIND_FUNC: Int8 = -125
private const TYPE_KIND_TEMP_ENUM: Int8 = -124
private const TYPE_KIND_WEAKREF_CLASS: Int8 = -123
private const TYPE_KIND_FOREIGN_PROXY: Int8 = -122
private const TYPE_KIND_EXPORTED_REF: Int8 = -121
private const TYPE_KIND_TUPLE: Int8 = 21
private const TYPE_KIND_STRUCT: Int8 = 22
private const TYPE_KIND_ENUM: Int8 = 23
private const FLAG_HAS_REF_FIELD: UInt8 = 1u8
private const MARRAY_CONTENT_OFFSET: UIntNative = 16

@When[arch == "arm"]
private func TypeInfoTypeOffset(): Int64 { return 4 }
@When[arch != "arm"]
private func TypeInfoTypeOffset(): Int64 { return 8 }

@When[arch == "arm"]
private func TypeInfoGCTibOffset(): Int64 { return 12 }
@When[arch != "arm"]
private func TypeInfoGCTibOffset(): Int64 { return 16 }

@When[arch == "arm"]
private func TypeInfoComponentOffset(): Int64 { return 36 }
@When[arch != "arm"]
private func TypeInfoComponentOffset(): Int64 { return 64 }

@When[arch == "arm"]
private func TypeInfoGetInstanceSize(typeInfo: CPointer<TypeInfo>): UIntNative {
    return UIntNative(unsafe { CPointer<UInt32>(TypeInfoBytes(typeInfo) + 8).read() })
}
@When[arch != "arm"]
private func TypeInfoGetInstanceSize(typeInfo: CPointer<TypeInfo>): UIntNative {
    return UIntNative(unsafe { CPointer<UInt32>(TypeInfoBytes(typeInfo) + 12).read() })
}

@When[arch == "arm"]
private func TypeInfoPointerSize(): UIntNative { return 8 }
@When[arch != "arm"]
private func TypeInfoPointerSize(): UIntNative { return 8 }

private func TypeInfoBytes(typeInfo: CPointer<TypeInfo>): CPointer<UInt8> {
    return CPointer<UInt8>(typeInfo)
}

@NoHeapAlloc
@When[arch == "arm"]
public func BaseObjectGetTypeInfo(object: CPointer<BaseObject>): CPointer<TypeInfo> {
    let address = UIntNative(unsafe { CPointer<UInt32>(object).read() })
    var bits = address
    return unsafe { CPointer<CPointer<TypeInfo>>(CPointer<UIntNative>(inout bits)).read() }
}

@NoHeapAlloc
@When[arch != "arm"]
public func BaseObjectGetTypeInfo(object: CPointer<BaseObject>): CPointer<TypeInfo> {
    let bytes = CPointer<UInt8>(object)
    let low = UInt64(unsafe { CPointer<UInt32>(bytes).read() })
    let high = UInt64(unsafe { CPointer<UInt16>(bytes + 4).read() })
    var bits = UIntNative((high << 32) | low)
    return unsafe { CPointer<CPointer<TypeInfo>>(CPointer<UIntNative>(inout bits)).read() }
}

@NoHeapAlloc
public func TypeInfoGetType(typeInfo: CPointer<TypeInfo>): Int8 {
    return unsafe { CPointer<Int8>(TypeInfoBytes(typeInfo) + TypeInfoTypeOffset()).read() }
}

@NoHeapAlloc
public func TypeInfoGetGCTib(typeInfo: CPointer<TypeInfo>): CPointer<GCTib> {
    return unsafe { CPointer<GCTib>(TypeInfoBytes(typeInfo) + TypeInfoGCTibOffset()) }
}

@NoHeapAlloc
public func TypeInfoGetComponentTypeInfo(typeInfo: CPointer<TypeInfo>): CPointer<TypeInfo> {
    return unsafe { CPointer<CPointer<TypeInfo>>(TypeInfoBytes(typeInfo) + TypeInfoComponentOffset()).read() }
}

@NoHeapAlloc
public func TypeInfoIsRawArray(typeInfo: CPointer<TypeInfo>): Bool {
    return TypeInfoGetType(typeInfo) == TYPE_KIND_RAWARRAY
}

@NoHeapAlloc
public func TypeInfoIsRef(typeInfo: CPointer<TypeInfo>): Bool { return TypeInfoGetType(typeInfo) < 0 }

@NoHeapAlloc
public func TypeInfoIsStructType(typeInfo: CPointer<TypeInfo>): Bool {
    let kind = TypeInfoGetType(typeInfo)
    return kind == TYPE_KIND_STRUCT || kind == TYPE_KIND_TUPLE || kind == TYPE_KIND_ENUM
}

@NoHeapAlloc
public func TypeInfoIsObjectLike(typeInfo: CPointer<TypeInfo>): Bool {
    let kind = TypeInfoGetType(typeInfo)
    return kind == TYPE_KIND_CLASS || kind == TYPE_KIND_WEAKREF_CLASS || kind == TYPE_KIND_TEMP_ENUM ||
        kind == TYPE_KIND_FUNC || kind == TYPE_KIND_FOREIGN_PROXY || kind == TYPE_KIND_EXPORTED_REF ||
        kind == TYPE_KIND_RAWARRAY || kind == TYPE_KIND_INTERFACE
}

@NoHeapAlloc
public func TypeInfoHasRefField(typeInfo: CPointer<TypeInfo>): Bool {
    if (TypeInfoIsRawArray(typeInfo)) {
        let component = TypeInfoGetComponentTypeInfo(typeInfo)
        return if (TypeInfoIsRef(component)) { true } else { TypeInfoHasRefField(component) }
    }
    let flagOffset = TypeInfoTypeOffset() + 1
    return (unsafe { (TypeInfoBytes(typeInfo) + flagOffset).read() } & FLAG_HAS_REF_FIELD) != 0
}

@NoHeapAlloc
public func MArrayGetLength(array: CPointer<MArray>): UInt64 {
    return unsafe { CPointer<UInt64>(CPointer<UInt8>(array) + 8).read() }
}

@NoHeapAlloc
public func MArrayGetElementSize(array: CPointer<MArray>): UIntNative {
    let component = TypeInfoGetComponentTypeInfo(BaseObjectGetTypeInfo(CPointer<BaseObject>(array)))
    if (TypeInfoIsRef(component)) { return sizeOf<CPointer<Unit>>() }
    return UIntNative(unsafe { CPointer<UInt32>(TypeInfoBytes(component) + TypeInfoTypeOffset() + 4).read() })
}

// Common/BaseObject.cpp:139-150; MArray.inline.h:22,33-48;
// ObjectModel/MClass.inline.h:85; Common/PageAllocator.h:50-51.
@NoHeapAlloc
public func BaseObjectGetSize(object: CPointer<BaseObject>): UIntNative {
    let typeInfo = BaseObjectGetTypeInfo(object)
    let size = if (TypeInfoIsRawArray(typeInfo)) {
        UIntNative(MArrayGetLength(CPointer<MArray>(object))).wrappingMul(
            MArrayGetElementSize(CPointer<MArray>(object))).wrappingAdd(MARRAY_CONTENT_OFFSET)
    } else {
        TypeInfoGetInstanceSize(typeInfo).wrappingAdd(TypeInfoPointerSize())
    }
    return size.wrappingAdd(7) & (UIntNative.Max - 7)
}

@NoHeapAlloc
public func MArrayForEachRefFieldInRange(array: CPointer<MArray>, visitor: GCTibVisitor,
    context: CPointer<Unit>, fieldStart: UIntNative, fieldEnd: UInt64): Unit {
    let component = TypeInfoGetComponentTypeInfo(BaseObjectGetTypeInfo(CPointer<BaseObject>(array)))
    let size = UInt64(fieldEnd) - UInt64(fieldStart)
    if (TypeInfoIsStructType(component)) {
        let elementSize = UInt64(MArrayGetElementSize(array))
        if (elementSize == 0) { unsafe { abort() } }
        let limit = size.wrappingDiv(elementSize)
        var index = 0u64
        var current = fieldStart
        while (index < limit) {
            GCTibForEachBitmapWord(TypeInfoGetGCTib(component), current, visitor, context)
            current += UIntNative(elementSize)
            index++
        }
    } else if (TypeInfoIsObjectLike(component)) {
        let limit = size.wrappingDiv(UInt64(sizeOf<RefField>()))
        var index = 0u64
        var current = fieldStart
        while (index < limit) {
            GCTibVisit(visitor, current, context)
            current += sizeOf<RefField>()
            index++
        }
    } else {
        unsafe { abort() }
    }
}

@NoHeapAlloc
private func BaseObjectForEachArrayElement(object: CPointer<BaseObject>, typeInfo: CPointer<TypeInfo>,
    visitor: GCTibVisitor, context: CPointer<Unit>): Unit {
    let array = CPointer<MArray>(object)
    let component = TypeInfoGetComponentTypeInfo(typeInfo)
    let length = MArrayGetLength(array)
    var index = 0u64
    var current = object.toUIntNative() + MARRAY_CONTENT_OFFSET
    if (TypeInfoIsStructType(component)) {
        let elementSize = MArrayGetElementSize(array)
        while (index < length) {
            GCTibForEachBitmapWord(TypeInfoGetGCTib(component), current, visitor, context)
            current += elementSize
            index++
        }
    } else if (TypeInfoIsObjectLike(component)) {
        while (index < length) {
            GCTibVisit(visitor, current, context)
            current += sizeOf<RefField>()
            index++
        }
    } else {
        unsafe { abort() }
    }
}

@NoHeapAlloc
public func BaseObjectForEachRefField(object: CPointer<BaseObject>, visitor: GCTibVisitor,
    context: CPointer<Unit>): Unit {
    let typeInfo = BaseObjectGetTypeInfo(object)
    if (!TypeInfoHasRefField(typeInfo)) { return }
    if (TypeInfoIsRawArray(typeInfo)) {
        BaseObjectForEachArrayElement(object, typeInfo, visitor, context)
    } else {
        GCTibForEachBitmapWord(TypeInfoGetGCTib(typeInfo), object.toUIntNative() + TypeInfoPointerSize(),
            visitor, context)
    }
}

@NoHeapAlloc
public func BaseObjectForEachRefInStruct(object: CPointer<BaseObject>, visitor: GCTibVisitor,
    context: CPointer<Unit>, aggregateStart: UIntNative, aggregateEnd: UIntNative): Unit {
    let typeInfo = BaseObjectGetTypeInfo(object)
    if (!TypeInfoHasRefField(typeInfo)) { return }
    if (TypeInfoIsRawArray(typeInfo)) {
        let array = CPointer<MArray>(object)
        let component = TypeInfoGetComponentTypeInfo(typeInfo)
        if (!TypeInfoIsStructType(component)) { unsafe { abort() } }
        let content = object.toUIntNative() + MARRAY_CONTENT_OFFSET
        let elementSize = MArrayGetElementSize(array)
        if (elementSize == 0) { unsafe { abort() } }
        let startIndex = (aggregateStart - content).wrappingDiv(elementSize)
        var current = content + startIndex * elementSize
        var index = UInt64(startIndex)
        let length = MArrayGetLength(array)
        while (index < length && current < aggregateEnd) {
            GCTibForEachBitmapWord(TypeInfoGetGCTib(component), current, visitor, context)
            current += elementSize
            index++
        }
    } else {
        GCTibForEachBitmapWordInRange(TypeInfoGetGCTib(typeInfo),
            object.toUIntNative() + TypeInfoPointerSize(), visitor, context, aggregateStart, aggregateEnd)
    }
}
