package rt.objectmodel

@NoHeapAlloc
public func FieldRefNoHeapRoot(field: CPointer<UInt64>, ref: CPointer<RefField>): UInt64 {
    FieldSet(field, 7u64)
    let plain = FieldGet(field)
    AtomicFieldSet(field, 11u64, order: MEMORY_ORDER_RELEASE)
    let loaded = AtomicFieldGet(field, order: MEMORY_ORDER_ACQUIRE)
    let cas = AtomicFieldCompareExchange(field, 11u64, 13u64,
        success: MEMORY_ORDER_ACQ_REL, failure: MEMORY_ORDER_ACQUIRE)
    let exchanged = AtomicFieldExchange(field, 17u64)
    let added = AtomicFieldFetchAdd(field, 3u64)
    let subbed = AtomicFieldFetchSub(field, 2u64)
    let anded = AtomicFieldFetchAnd(field, 0xffu64)
    let ored = AtomicFieldFetchOr(field, 0x100u64)
    let xored = AtomicFieldFetchXor(field, 0x10u64)
    RefFieldSetFieldValue(ref, 0x1000)
    AtomicRefFieldSetFieldValue(ref, 0x2000)
    let refOld = AtomicRefFieldExchange(ref, UIntNative(0x3000))
    let refCas = AtomicRefFieldCompareExchange(ref, UIntNative(0x3000), UIntNative(0x4000))
    return plain + loaded + exchanged + added + subbed + anded + ored + xored + UInt64(refOld) +
        (if (cas && refCas) { 1 } else { 0 })
}
