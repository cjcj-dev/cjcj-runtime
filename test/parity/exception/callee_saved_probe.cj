import rt.exception.*

main(): Int64 {
    var context = CalleeSavedRegisterContext()
    let base = unsafe { CPointer<UInt8>(inout context) }.toUIntNative()
    let rbxOffset = unsafe { CPointer<UInt8>(inout context.rbx) }.toUIntNative() - base
    let r12Offset = unsafe { CPointer<UInt8>(inout context.r12) }.toUIntNative() - base
    let rbpOffset = unsafe { CPointer<UInt8>(inout context.rbp) }.toUIntNative() - base
    let rspOffset = unsafe { CPointer<UInt8>(inout context.rsp) }.toUIntNative() - base
    println("CALLEE_LAYOUT ${sizeOf<CalleeSavedRegisterContext>()} ${alignOf<CalleeSavedRegisterContext>()} ${rbxOffset} ${r12Offset} ${rbpOffset} ${rspOffset}")
    context.SetValueByIdx(0u32, 101u64)
    context.SetValueByIdx(1u32, 202u64)
    context.SetValueByIdx(5u32, 606u64)
    context.SetValueByIdx(6u32, 707u64)
    println("CALLEE_VALUES ${context.rbx} ${context.r12} ${context.r13} ${context.r14} ${context.r15} ${context.rbp} ${context.rsp}")
    return 0
}
