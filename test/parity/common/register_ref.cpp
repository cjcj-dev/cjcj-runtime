// Standalone parity oracle copied from Common/RegisterX86-64.h:23-82,
// Common/RegisterAarch64.h:33-121, and Common/RegisterArm.h:14-85.
#include <cstdint>
#include <iostream>

#if defined(__aarch64__)
// Common/RegisterAarch64.h:33-99.
enum RegisterId : uint32_t {
    X0, X1, X2, X3, X4, X5, X6, X7, X8, X9, X10, X11, X12, X13, X14, X15,
    X16, X17, X18, X19, X20, X21, X22, X23, X24, X25, X26, X27, X28, X29, X30, X31,
    D0, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D11, D12, D13, D14, D15,
    D16, D17, D18, D19, D20, D21, D22, D23, D24, D25, D26, D27, D28, D29, D30, D31,
    REGISTERS_COUNT
};
// Common/RegisterAarch64.h:105-110.
static constexpr const char* REGISTER_NAMES[] = {
    "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
    "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23", "x24", "x25", "x26", "x27", "x28", "x29", "x30", "x31",
    "d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9", "d10", "d11", "d12", "d13", "d14", "d15",
    "d16", "d17", "d18", "d19", "d20", "d21", "d22", "d23", "d24", "d25", "d26", "d27", "d28", "d29", "d30", "d31"
};
// Common/RegisterAarch64.h:115-117.
static constexpr RegisterId CALLEE_SAVED[] = {
    X19, X20, X21, X22, X23, X24, X25, X26, X27, X28, X29, X30, D8, D9, D10, D11, D12, D13, D14, D15
};
#elif defined(__arm__)
// Common/RegisterArm.h:14-64.
enum RegisterId : uint32_t {
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15,
    D0, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D11, D12, D13, D14, D15,
    D16, D17, D18, D19, D20, D21, D22, D23, D24, D25, D26, D27, D28, D29, D30, D31,
    REGISTERS_COUNT
};
// Common/RegisterArm.h:70-74.
static constexpr const char* REGISTER_NAMES[] = {
    "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
    "d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9", "d10", "d11", "d12", "d13", "d14", "d15",
    "d16", "d17", "d18", "d19", "d20", "d21", "d22", "d23", "d24", "d25", "d26", "d27", "d28", "d29", "d30", "d31"
};
// Common/RegisterArm.h:79-81.
static constexpr RegisterId CALLEE_SAVED[] = {
    R4, R5, R6, R7, R8, R9, R10, R11, R14, D8, D9, D10, D11, D12, D13, D14, D15
};
#else
// Common/RegisterX86-64.h:23-58.
enum RegisterId : uint32_t {
    RAX, RDX, RCX, RBX, RSI, RDI, RBP, RSP, R8, R9, R10, R11, R12, R13, R14, R15, RIP,
    XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7, XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15,
    REGISTERS_COUNT
};
// Common/RegisterX86-64.h:64-67.
static constexpr const char* REGISTER_NAMES[] = {
    "rax", "rdx", "rcx", "rbx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip",
    "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15"
};
#if defined(_WIN64)
// Common/RegisterX86-64.h:72-75.
static constexpr RegisterId CALLEE_SAVED[] = {
    RBX, RSI, RDI, R12, R13, R14, R15, XMM6, XMM7, XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15
};
#else
// Common/RegisterX86-64.h:76-79.
static constexpr RegisterId CALLEE_SAVED[] = {RBX, R12, R13, R14, R15};
#endif
#endif

// Common/RegisterX86-64.h:61-63, RegisterAarch64.h:102-104, RegisterArm.h:67-69.
static constexpr const char* WRONG_REGISTER = "wrong register";

int main()
{
    static_assert(sizeof(RegisterId) == sizeof(uint32_t), "RegisterId must be four bytes");
    std::cout << "SIZE:" << sizeof(RegisterId) << '\n';
    std::cout << "COUNT:" << static_cast<uint32_t>(REGISTERS_COUNT) << '\n';
    for (uint32_t idx = 0; idx < static_cast<uint32_t>(REGISTERS_COUNT); ++idx) {
        std::cout << idx << ':' << REGISTER_NAMES[idx] << '\n';
    }
    std::cout << static_cast<uint32_t>(REGISTERS_COUNT) << ':' << WRONG_REGISTER << '\n';
    for (uint32_t idx = 0; idx < sizeof(CALLEE_SAVED) / sizeof(CALLEE_SAVED[0]); ++idx) {
        std::cout << "CALLEE:" << idx << ':' << static_cast<uint32_t>(CALLEE_SAVED[idx]) << '\n';
    }
    return 0;
}
