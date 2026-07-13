import rt.common.*

// Common/RegisterX86-64.h:23-82. The mandatory executable parity host is Linux x86_64.
main(): Int64 {
    if (sizeOf<RegisterId>() != 4) { return 1 }
    let ids: Array<RegisterId> = [
        RAX, RDX, RCX, RBX, RSI, RDI, RBP, RSP, R8, R9, R10, R11, R12, R13, R14, R15, RIP,
        XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7, XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15
    ]
    let names: Array<String> = [
        "rax", "rdx", "rcx", "rbx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip",
        "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15"
    ]
    let callees: Array<RegisterId> = [RBX, R12, R13, R14, R15]
    if (REGISTERS_COUNT != UInt32(ids.size) || ids.size != names.size) { return 2 }
    println("SIZE:${sizeOf<RegisterId>()}")
    println("COUNT:${REGISTERS_COUNT}")
    for (idx in 0..ids.size) {
        if (ids[idx] != UInt32(idx)) { return 3 }
        let actualName = GetRegisterName(UInt32(idx)).toString()
        if (actualName != names[idx]) { return 4 }
        println("${idx}:${actualName}")
    }
    let invalidName = GetRegisterName(REGISTERS_COUNT).toString()
    if (invalidName != "wrong register") { return 5 }
    println("${REGISTERS_COUNT}:${invalidName}")
    for (idx in 0..callees.size) {
        let actualRegister = ResolveCalleeSaved(UInt32(idx))
        if (actualRegister != callees[idx]) { return 6 }
        println("CALLEE:${idx}:${actualRegister}")
    }
    return 0
}
