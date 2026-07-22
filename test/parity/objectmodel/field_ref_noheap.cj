package rt.objectmodel

@NoHeapAlloc
public func FieldRefNoHeapRoot(i8: CPointer<Int8>, i16: CPointer<Int16>, i32: CPointer<Int32>,
    field: CPointer<Int64>, f32: CPointer<Float32>, f64: CPointer<Float64>, ref: CPointer<RefField>): UInt64 {
    FieldSetI8(i8, 1)
    FieldSetI16(i16, 2)
    FieldSetI32(i32, 3)
    FieldSetI64(field, 7)
    FieldSetF32(f32, 4.0)
    FieldSetF64(f64, 5.0)
    let plain = FieldGetI8(i8) + Int8(FieldGetI16(i16)) + Int8(FieldGetI32(i32)) + Int8(FieldGetI64(field)) +
        Int8(FieldGetF32(f32)) + Int8(FieldGetF64(f64))
    let raw = CPointer<Unit>(field)
    AtomicFieldStoreBits(raw, 11, 8, order: MEMORY_ORDER_RELEASE)
    let loaded = AtomicFieldLoadBits(raw, 8, order: MEMORY_ORDER_ACQUIRE)
    let cas = AtomicFieldCompareExchangeBits(raw, 11, 13, 8,
        success: MEMORY_ORDER_ACQ_REL, failure: MEMORY_ORDER_ACQUIRE)
    let exchanged = AtomicFieldExchangeBits(raw, 17, 8)
    let added = AtomicFieldFetchAddBits(raw, 3, 8)
    let subbed = AtomicFieldFetchSubBits(raw, 2, 8)
    let anded = AtomicFieldFetchAndBits(raw, 0xff, 8)
    let ored = AtomicFieldFetchOrBits(raw, 0x100, 8)
    let xored = AtomicFieldFetchXorBits(raw, 0x10, 8)
    RefFieldSetFieldValue(ref, 0x1000)
    AtomicRefFieldSetFieldValue(ref, 0x2000)
    let refOld = AtomicRefFieldExchange(ref, UIntNative(0x3000))
    let refCas = AtomicRefFieldCompareExchange(ref, UIntNative(0x3000), UIntNative(0x4000))
    return UInt64(plain) + loaded + exchanged + added + subbed + anded + ored + xored + UInt64(refOld) +
        (if (cas && refCas) { 1 } else { 0 })
}
