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

// Barrier.inline.h:16-51 is the complete production instantiation set.  Using
// concrete leaves also avoids the mandated compiler's heap-classified
// llvm.cj.alloca.generic lowering for CPointer<T>.read/write.
public func FieldGetI8(field: CPointer<Int8>): Int8 { return unsafe { field.read() } }
public func FieldSetI8(field: CPointer<Int8>, value: Int8): Unit { unsafe { field.write(0, value) } }
public func FieldGetI16(field: CPointer<Int16>): Int16 { return unsafe { field.read() } }
public func FieldSetI16(field: CPointer<Int16>, value: Int16): Unit { unsafe { field.write(0, value) } }
public func FieldGetI32(field: CPointer<Int32>): Int32 { return unsafe { field.read() } }
public func FieldSetI32(field: CPointer<Int32>, value: Int32): Unit { unsafe { field.write(0, value) } }
public func FieldGetI64(field: CPointer<Int64>): Int64 { return unsafe { field.read() } }
public func FieldSetI64(field: CPointer<Int64>, value: Int64): Unit { unsafe { field.write(0, value) } }
public func FieldGetF32(field: CPointer<Float32>): Float32 { return unsafe { field.read() } }
public func FieldSetF32(field: CPointer<Float32>, value: Float32): Unit { unsafe { field.write(0, value) } }
public func FieldGetF64(field: CPointer<Float64>): Float64 { return unsafe { field.read() } }
public func FieldSetF64(field: CPointer<Float64>, value: Float64): Unit { unsafe { field.write(0, value) } }

// The mandated compiler cannot take `inout` of a generic T even under a CType
// constraint.  Field's instantiated atomic storage is therefore carried as its
// exact 1/2/4/8-byte bit pattern; no managed box or alternate owner is created.
public func AtomicFieldLoadBits(field: CPointer<Unit>, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UInt64 {
    return unsafe { cj_atomic_field_load(field, size, order) }
}

public func AtomicFieldStoreBits(field: CPointer<Unit>, value: UInt64, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): Unit {
    var desired = value
    unsafe { cj_atomic_field_store(field, CPointer<Unit>(CPointer<UInt64>(inout desired)), size, order) }
}

public func AtomicFieldCompareExchangeBits(field: CPointer<Unit>, expectedValue: UInt64, newValue: UInt64,
    size: UIntNative, success!: Int32 = MEMORY_ORDER_RELAXED, failure!: Int32 = MEMORY_ORDER_RELAXED): Bool {
    var expected = expectedValue
    var desired = newValue
    return unsafe { cj_atomic_field_compare_exchange(field, CPointer<Unit>(CPointer<UInt64>(inout expected)),
        CPointer<Unit>(CPointer<UInt64>(inout desired)), size, success, failure) != 0 }
}

public func AtomicFieldExchangeBits(field: CPointer<Unit>, newValue: UInt64, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UInt64 {
    var desired = newValue
    return unsafe { cj_atomic_field_exchange(field, CPointer<Unit>(CPointer<UInt64>(inout desired)), size, order) }
}

private func AtomicFieldFetchBits(field: CPointer<Unit>, value: UInt64, size: UIntNative, order: Int32,
    operation: Int32): UInt64 {
    var operand = value
    let pointer = CPointer<Unit>(CPointer<UInt64>(inout operand))
    let bits = unsafe {
        if (operation == 0) { cj_atomic_field_fetch_add(field, pointer, size, order) }
        else if (operation == 1) { cj_atomic_field_fetch_sub(field, pointer, size, order) }
        else if (operation == 2) { cj_atomic_field_fetch_and(field, pointer, size, order) }
        else if (operation == 3) { cj_atomic_field_fetch_or(field, pointer, size, order) }
        else { cj_atomic_field_fetch_xor(field, pointer, size, order) }
    }
    return bits
}

public func AtomicFieldFetchAddBits(field: CPointer<Unit>, value: UInt64, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UInt64 { return AtomicFieldFetchBits(field, value, size, order, 0) }
public func AtomicFieldFetchSubBits(field: CPointer<Unit>, value: UInt64, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UInt64 { return AtomicFieldFetchBits(field, value, size, order, 1) }
public func AtomicFieldFetchAndBits(field: CPointer<Unit>, value: UInt64, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UInt64 { return AtomicFieldFetchBits(field, value, size, order, 2) }
public func AtomicFieldFetchOrBits(field: CPointer<Unit>, value: UInt64, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UInt64 { return AtomicFieldFetchBits(field, value, size, order, 3) }
public func AtomicFieldFetchXorBits(field: CPointer<Unit>, value: UInt64, size: UIntNative,
    order!: Int32 = MEMORY_ORDER_RELAXED): UInt64 { return AtomicFieldFetchBits(field, value, size, order, 4) }
