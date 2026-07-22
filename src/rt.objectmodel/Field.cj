package rt.objectmodel

// ObjectModel/Field.h:18-123. The C++ template owns exactly one inline T.  The
// phantom `isAtomic` parameter does not change layout, so the port operates on
// caller-owned CPointer<T> storage and keeps the same byte representation.

public const MEMORY_ORDER_RELAXED: Int32 = 0
public const MEMORY_ORDER_CONSUME: Int32 = 1
public const MEMORY_ORDER_ACQUIRE: Int32 = 2
public const MEMORY_ORDER_RELEASE: Int32 = 3
public const MEMORY_ORDER_ACQ_REL: Int32 = 4
public const MEMORY_ORDER_SEQ_CST: Int32 = 5

foreign {
    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_load(p: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_load(p: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Windows"]
    func cj_atomic_field_load(p: CPointer<Unit>, size: UIntNative, order: Int32): UInt64

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_store(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): Unit
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_store(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): Unit
    @When[os == "Windows"]
    func cj_atomic_field_store(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): Unit

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_compare_exchange(p: CPointer<Unit>, expected: CPointer<Unit>, desired: CPointer<Unit>,
        size: UIntNative, success: Int32, failure: Int32): Int32
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_compare_exchange(p: CPointer<Unit>, expected: CPointer<Unit>, desired: CPointer<Unit>,
        size: UIntNative, success: Int32, failure: Int32): Int32
    @When[os == "Windows"]
    func cj_atomic_field_compare_exchange(p: CPointer<Unit>, expected: CPointer<Unit>, desired: CPointer<Unit>,
        size: UIntNative, success: Int32, failure: Int32): Int32

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_exchange(p: CPointer<Unit>, desired: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_exchange(p: CPointer<Unit>, desired: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Windows"]
    func cj_atomic_field_exchange(p: CPointer<Unit>, desired: CPointer<Unit>, size: UIntNative, order: Int32): UInt64

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_fetch_add(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_fetch_add(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Windows"]
    func cj_atomic_field_fetch_add(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_fetch_sub(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_fetch_sub(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Windows"]
    func cj_atomic_field_fetch_sub(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_fetch_and(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_fetch_and(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Windows"]
    func cj_atomic_field_fetch_and(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_fetch_or(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_fetch_or(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Windows"]
    func cj_atomic_field_fetch_or(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_field_fetch_xor(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_field_fetch_xor(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
    @When[os == "Windows"]
    func cj_atomic_field_fetch_xor(p: CPointer<Unit>, value: CPointer<Unit>, size: UIntNative, order: Int32): UInt64
}

public func FieldGet<T>(field: CPointer<T>): T where T <: CType {
    return unsafe { field.read() }
}

public func FieldSet<T>(field: CPointer<T>, value: T): Unit where T <: CType {
    unsafe { field.write(0, value) }
}

private func BitsToValue<T>(bits: UInt64): T where T <: CType {
    var storage = bits
    return unsafe { CPointer<T>(CPointer<UInt64>(inout storage)).read() }
}

public func AtomicFieldGet<T>(field: CPointer<T>, order!: Int32 = MEMORY_ORDER_RELAXED): T where T <: CType {
    let bits = unsafe { cj_atomic_field_load(CPointer<Unit>(field), sizeOf<T>(), order) }
    return BitsToValue<T>(bits)
}

public func AtomicFieldSet<T>(field: CPointer<T>, value: T,
    order!: Int32 = MEMORY_ORDER_RELAXED): Unit where T <: CType {
    var desired = value
    unsafe { cj_atomic_field_store(CPointer<Unit>(field), CPointer<Unit>(CPointer<T>(inout desired)), sizeOf<T>(), order) }
}

public func AtomicFieldCompareExchange<T>(field: CPointer<T>, expectedValue: T, newValue: T,
    success!: Int32 = MEMORY_ORDER_RELAXED, failure!: Int32 = MEMORY_ORDER_RELAXED): Bool where T <: CType {
    var expected = expectedValue
    var desired = newValue
    return unsafe { cj_atomic_field_compare_exchange(CPointer<Unit>(field),
        CPointer<Unit>(CPointer<T>(inout expected)), CPointer<Unit>(CPointer<T>(inout desired)),
        sizeOf<T>(), success, failure) != 0 }
}

public func AtomicFieldExchange<T>(field: CPointer<T>, newValue: T,
    order!: Int32 = MEMORY_ORDER_RELAXED): T where T <: CType {
    var desired = newValue
    return BitsToValue<T>(unsafe { cj_atomic_field_exchange(CPointer<Unit>(field),
        CPointer<Unit>(CPointer<T>(inout desired)), sizeOf<T>(), order) })
}

private func AtomicFieldFetch<T>(field: CPointer<T>, value: T, order: Int32,
    operation: Int32): T where T <: CType {
    var operand = value
    let pointer = CPointer<Unit>(CPointer<T>(inout operand))
    let bits = unsafe {
        if (operation == 0) { cj_atomic_field_fetch_add(CPointer<Unit>(field), pointer, sizeOf<T>(), order) }
        else if (operation == 1) { cj_atomic_field_fetch_sub(CPointer<Unit>(field), pointer, sizeOf<T>(), order) }
        else if (operation == 2) { cj_atomic_field_fetch_and(CPointer<Unit>(field), pointer, sizeOf<T>(), order) }
        else if (operation == 3) { cj_atomic_field_fetch_or(CPointer<Unit>(field), pointer, sizeOf<T>(), order) }
        else { cj_atomic_field_fetch_xor(CPointer<Unit>(field), pointer, sizeOf<T>(), order) }
    }
    return BitsToValue<T>(bits)
}

public func AtomicFieldFetchAdd<T>(field: CPointer<T>, value: T,
    order!: Int32 = MEMORY_ORDER_RELAXED): T where T <: CType { return AtomicFieldFetch(field, value, order, 0) }
public func AtomicFieldFetchSub<T>(field: CPointer<T>, value: T,
    order!: Int32 = MEMORY_ORDER_RELAXED): T where T <: CType { return AtomicFieldFetch(field, value, order, 1) }
public func AtomicFieldFetchAnd<T>(field: CPointer<T>, value: T,
    order!: Int32 = MEMORY_ORDER_RELAXED): T where T <: CType { return AtomicFieldFetch(field, value, order, 2) }
public func AtomicFieldFetchOr<T>(field: CPointer<T>, value: T,
    order!: Int32 = MEMORY_ORDER_RELAXED): T where T <: CType { return AtomicFieldFetch(field, value, order, 3) }
public func AtomicFieldFetchXor<T>(field: CPointer<T>, value: T,
    order!: Int32 = MEMORY_ORDER_RELAXED): T where T <: CType { return AtomicFieldFetch(field, value, order, 4) }
