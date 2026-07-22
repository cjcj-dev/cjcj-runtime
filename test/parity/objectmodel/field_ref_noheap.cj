package rt.objectmodel

@NoHeapAlloc
public func FieldRefNoHeapRoot(field: CPointer<UInt64>, ref: CPointer<RefField>): UInt64 {
    FieldSet(field, 7u64)
    let plain = FieldGet(field)
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
    return plain + loaded + exchanged + added + subbed + anded + ored + xored + UInt64(refOld) +
        (if (cas && refCas) { 1 } else { 0 })
}
