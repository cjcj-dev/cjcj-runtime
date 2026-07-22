package rt.objectmodel

foreign {
    func abort(): Unit
}

// ObjectModel/RefField.h:25-183.  Both atomic and non-atomic specializations
// are one native word; atomicity belongs to the operation, not to extra owner
// storage.  The visitor std::function alias is deliberately left with its
// Collector/ObjectModel owner rather than represented as a managed closure.
@C
public struct RefField {
    public var fieldValue: UIntNative

    public init(value!: UIntNative = 0) { fieldValue = value }
}

@When[arch == "arm"]
private func AddressMask(): UIntNative { return UIntNative(UInt32.Max) ^ 3 }
@When[arch != "arm"]
private func AddressMask(): UIntNative { return UIntNative(0x0000ffffffffffffu64) }

@When[arch == "arm"]
private func TaggedMask(): UIntNative { return 1 }
@When[arch != "arm"]
private func TaggedMask(): UIntNative { return UIntNative(0x0001000000000000u64) }

@When[arch == "arm"]
private func TagIdMask(): UIntNative { return 2 }
@When[arch != "arm"]
private func TagIdMask(): UIntNative { return UIntNative(0x0002000000000000u64) }

public func RefFieldFromAddress(object: CPointer<Unit>): RefField {
    return RefField(value: object.toUIntNative() & AddressMask())
}

public func RefFieldFromTaggedAddress(object: CPointer<Unit>, tagged: UInt16, tagId: UInt16): RefField {
    var value = object.toUIntNative() & AddressMask()
    if ((tagged & 1) != 0) { value |= TaggedMask() }
    if ((tagId & 1) != 0) { value |= TagIdMask() }
    return RefField(value: value)
}

public func RefFieldGetSize(): UIntNative { return sizeOf<UIntNative>() }
public func RefFieldGetAddress(field: CPointer<RefField>): UIntNative {
    return unsafe { field.read().fieldValue } & AddressMask()
}
public func RefFieldGetTargetObject(field: CPointer<RefField>): CPointer<Unit> {
    return CPointer<Unit>(RefFieldGetAddress(field))
}
public func RefFieldGetFieldValue(field: CPointer<RefField>): UIntNative {
    return unsafe { field.read().fieldValue }
}
public func RefFieldIsTagged(field: CPointer<RefField>): Bool {
    return (unsafe { field.read().fieldValue } & TaggedMask()) != 0
}
public func RefFieldGetTagId(field: CPointer<RefField>): UInt16 {
    return if ((unsafe { field.read().fieldValue } & TagIdMask()) != 0) { 1u16 } else { 0u16 }
}
public func RefFieldSetTargetObject(field: CPointer<RefField>, object: CPointer<Unit>): Unit {
    unsafe { CPointer<UIntNative>(field).write(0, object.toUIntNative() & AddressMask()) }
}
public func RefFieldSetFieldValue(field: CPointer<RefField>, value: UIntNative): Unit {
    unsafe { CPointer<UIntNative>(field).write(0, value) }
}

public func AtomicRefFieldGetFieldValue(field: CPointer<RefField>,
    order!: Int32 = MEMORY_ORDER_RELAXED): UIntNative {
    return AtomicFieldGet(CPointer<UIntNative>(field), order: order)
}
public func AtomicRefFieldGetTargetObject(field: CPointer<RefField>,
    order!: Int32 = MEMORY_ORDER_RELAXED): CPointer<Unit> {
    return CPointer<Unit>(AtomicRefFieldGetFieldValue(field, order: order) & AddressMask())
}
public func AtomicRefFieldSetTargetObject(field: CPointer<RefField>, object: CPointer<Unit>,
    order!: Int32 = MEMORY_ORDER_RELAXED): Unit {
    AtomicFieldSet(CPointer<UIntNative>(field), object.toUIntNative() & AddressMask(), order: order)
}
public func AtomicRefFieldSetFieldValue(field: CPointer<RefField>, value: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): Unit {
    AtomicFieldSet(CPointer<UIntNative>(field), value, order: order)
}
public func AtomicRefFieldCompareExchange(field: CPointer<RefField>, expectedValue: UIntNative,
    newValue: UIntNative, success!: Int32 = MEMORY_ORDER_RELAXED,
    failure!: Int32 = MEMORY_ORDER_RELAXED): Bool {
    if (newValue == UIntNative.Max) { unsafe { abort() } }
    return AtomicFieldCompareExchange(CPointer<UIntNative>(field), expectedValue, newValue,
        success: success, failure: failure)
}
public func AtomicRefFieldCompareExchange(field: CPointer<RefField>, expectedObject: CPointer<Unit>,
    newObject: CPointer<Unit>, success!: Int32 = MEMORY_ORDER_RELAXED,
    failure!: Int32 = MEMORY_ORDER_RELAXED): Bool {
    return AtomicRefFieldCompareExchange(field, expectedObject.toUIntNative(), newObject.toUIntNative(),
        success: success, failure: failure)
}
public func AtomicRefFieldExchange(field: CPointer<RefField>, newValue: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UIntNative {
    if (unsafe { CPointer<UIntNative>(field).read() } == UIntNative.Max) { unsafe { abort() } }
    return AtomicFieldExchange(CPointer<UIntNative>(field), newValue, order: order)
}
public func AtomicRefFieldExchange(field: CPointer<RefField>, object: CPointer<Unit>,
    order!: Int32 = MEMORY_ORDER_RELAXED): UIntNative {
    return AtomicRefFieldExchange(field, object.toUIntNative(), order: order)
}
