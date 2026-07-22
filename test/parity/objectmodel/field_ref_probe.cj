package rt.objectmodel

main(): Int64 {
    var plain = -17i32
    println("LAYOUT field_i32=${sizeOf<Int32>()}/${alignOf<Int32>()} " +
        "ref=${sizeOf<RefField>()}/${alignOf<RefField>()}")
    println("PLAIN get=${FieldGet(unsafe { CPointer<Int32>(inout plain) })}")

    var atomic = 0u32
    let atomicPtr = unsafe { CPointer<UInt32>(inout atomic) }
    AtomicFieldSet(atomicPtr, 10u32, order: MEMORY_ORDER_RELEASE)
    let load = AtomicFieldGet(atomicPtr, order: MEMORY_ORDER_ACQUIRE)
    let casOk = AtomicFieldCompareExchange(atomicPtr, 10u32, 20u32,
        success: MEMORY_ORDER_ACQ_REL, failure: MEMORY_ORDER_ACQUIRE)
    let casFail = AtomicFieldCompareExchange(atomicPtr, 10u32, 30u32,
        success: MEMORY_ORDER_SEQ_CST, failure: MEMORY_ORDER_SEQ_CST)
    let exchanged = AtomicFieldExchange(atomicPtr, 40u32, order: MEMORY_ORDER_SEQ_CST)
    let added = AtomicFieldFetchAdd(atomicPtr, 2u32)
    let subbed = AtomicFieldFetchSub(atomicPtr, 3u32)
    let anded = AtomicFieldFetchAnd(atomicPtr, 0x2fu32)
    let ored = AtomicFieldFetchOr(atomicPtr, 0x80u32)
    let xored = AtomicFieldFetchXor(atomicPtr, 0x0fu32)
    println("ATOMIC load=${load} cas_ok=${casOk} cas_fail=${casFail} exchange=${exchanged} " +
        "add=${added} sub=${subbed} and=${anded} or=${ored} xor=${xored} final=${AtomicFieldGet(atomicPtr)}")

    var plainRef = RefFieldFromTaggedAddress(CPointer<Unit>(UIntNative(0x123456789ab0u64)), 1u16, 1u16)
    let plainRefPtr = unsafe { CPointer<RefField>(inout plainRef) }
    println("REF raw=${RefFieldGetFieldValue(plainRefPtr).toString(radix: 16)} " +
        "address=${RefFieldGetAddress(plainRefPtr).toString(radix: 16)} tagged=${RefFieldIsTagged(plainRefPtr)} " +
        "tag=${RefFieldGetTagId(plainRefPtr)}")
    RefFieldSetTargetObject(plainRefPtr, CPointer<Unit>(UIntNative(0x223344556670u64)))
    println("REF_SET raw=${RefFieldGetFieldValue(plainRefPtr).toString(radix: 16)} " +
        "target=${RefFieldGetTargetObject(plainRefPtr).toUIntNative().toString(radix: 16)}")

    var atomicRef = RefFieldFromAddress(CPointer<Unit>(UIntNative(0x1000u64)))
    let atomicRefPtr = unsafe { CPointer<RefField>(inout atomicRef) }
    let old = AtomicRefFieldExchange(atomicRefPtr, UIntNative(0x2000u64), order: MEMORY_ORDER_ACQ_REL)
    let refCasOk = AtomicRefFieldCompareExchange(atomicRefPtr, UIntNative(0x2000u64), UIntNative(0x3000u64),
        success: MEMORY_ORDER_SEQ_CST, failure: MEMORY_ORDER_ACQUIRE)
    let refCasFail = AtomicRefFieldCompareExchange(atomicRefPtr, UIntNative(0x2000u64), UIntNative(0x4000u64),
        success: MEMORY_ORDER_SEQ_CST, failure: MEMORY_ORDER_ACQUIRE)
    println("ATOMIC_REF old=${old.toString(radix: 16)} " +
        "final=${AtomicRefFieldGetFieldValue(atomicRefPtr).toString(radix: 16)} " +
        "cas_ok=${refCasOk} cas_fail=${refCasFail}")
    return 0
}
