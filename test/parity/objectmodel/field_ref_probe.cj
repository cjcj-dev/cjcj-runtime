package rt.objectmodel

main(): Int64 {
    var plain = -17i32
    println("LAYOUT field_i32=${sizeOf<Int32>()}/${alignOf<Int32>()} " +
        "ref=${sizeOf<RefField>()}/${alignOf<RefField>()}")
    println("PLAIN get=${FieldGet(unsafe { CPointer<Int32>(inout plain) })}")

    var atomic = 0u32
    let atomicPtr = unsafe { CPointer<UInt32>(inout atomic) }
    let atomicRaw = CPointer<Unit>(atomicPtr)
    AtomicFieldStoreBits(atomicRaw, 10, 4, order: MEMORY_ORDER_RELEASE)
    let load = AtomicFieldLoadBits(atomicRaw, 4, order: MEMORY_ORDER_ACQUIRE)
    let casOk = AtomicFieldCompareExchangeBits(atomicRaw, 10, 20, 4,
        success: MEMORY_ORDER_ACQ_REL, failure: MEMORY_ORDER_ACQUIRE)
    let casFail = AtomicFieldCompareExchangeBits(atomicRaw, 10, 30, 4,
        success: MEMORY_ORDER_SEQ_CST, failure: MEMORY_ORDER_SEQ_CST)
    let exchanged = AtomicFieldExchangeBits(atomicRaw, 40, 4, order: MEMORY_ORDER_SEQ_CST)
    let added = AtomicFieldFetchAddBits(atomicRaw, 2, 4)
    let subbed = AtomicFieldFetchSubBits(atomicRaw, 3, 4)
    let anded = AtomicFieldFetchAndBits(atomicRaw, 0x2f, 4)
    let ored = AtomicFieldFetchOrBits(atomicRaw, 0x80, 4)
    let xored = AtomicFieldFetchXorBits(atomicRaw, 0x0f, 4)
    println("ATOMIC load=${load} cas_ok=${casOk} cas_fail=${casFail} exchange=${exchanged} " +
        "add=${added} sub=${subbed} and=${anded} or=${ored} xor=${xored} final=${AtomicFieldLoadBits(atomicRaw, 4)}")

    var plainRef = RefFieldFromTaggedAddress(RefFieldPointerFromAddress(UIntNative(0x123456789ab0u64)), 1u16, 1u16)
    let plainRefPtr = unsafe { CPointer<RefField>(inout plainRef) }
    println("REF raw=${RefFieldGetFieldValue(plainRefPtr)} " +
        "address=${RefFieldGetAddress(plainRefPtr)} tagged=${RefFieldIsTagged(plainRefPtr)} " +
        "tag=${RefFieldGetTagId(plainRefPtr)}")
    RefFieldSetTargetObject(plainRefPtr, RefFieldPointerFromAddress(UIntNative(0x223344556670u64)))
    println("REF_SET raw=${RefFieldGetFieldValue(plainRefPtr)} " +
        "target=${RefFieldGetTargetObject(plainRefPtr).toUIntNative()}")

    var atomicRef = RefFieldFromAddress(RefFieldPointerFromAddress(UIntNative(0x1000u64)))
    let atomicRefPtr = unsafe { CPointer<RefField>(inout atomicRef) }
    let old = AtomicRefFieldExchange(atomicRefPtr, UIntNative(0x2000u64), order: MEMORY_ORDER_ACQ_REL)
    let refCasOk = AtomicRefFieldCompareExchange(atomicRefPtr, UIntNative(0x2000u64), UIntNative(0x3000u64),
        success: MEMORY_ORDER_SEQ_CST, failure: MEMORY_ORDER_ACQUIRE)
    let refCasFail = AtomicRefFieldCompareExchange(atomicRefPtr, UIntNative(0x2000u64), UIntNative(0x4000u64),
        success: MEMORY_ORDER_SEQ_CST, failure: MEMORY_ORDER_ACQUIRE)
    println("ATOMIC_REF old=${old} " +
        "final=${AtomicRefFieldGetFieldValue(atomicRefPtr)} " +
        "cas_ok=${refCasOk} cas_fail=${refCasFail}")
    return 0
}
