package rt.common

// Common/RegisterX86-64.h:23, RegisterAarch64.h:33, RegisterArm.h:14.
// Cangjie has no @C integer enum; the UInt32 alias is the exact four-byte RegisterId representation.
public type RegisterId = UInt32

// Common/RegisterX86-64.h:23-58.
@When[arch == "x86_64"]
public const RAX: RegisterId = 0u32
@When[arch == "x86_64"]
public const RDX: RegisterId = 1u32
@When[arch == "x86_64"]
public const RCX: RegisterId = 2u32
@When[arch == "x86_64"]
public const RBX: RegisterId = 3u32
@When[arch == "x86_64"]
public const RSI: RegisterId = 4u32
@When[arch == "x86_64"]
public const RDI: RegisterId = 5u32
@When[arch == "x86_64"]
public const RBP: RegisterId = 6u32
@When[arch == "x86_64"]
public const RSP: RegisterId = 7u32
@When[arch == "x86_64"]
public const R8: RegisterId = 8u32
@When[arch == "x86_64"]
public const R9: RegisterId = 9u32
@When[arch == "x86_64"]
public const R10: RegisterId = 10u32
@When[arch == "x86_64"]
public const R11: RegisterId = 11u32
@When[arch == "x86_64"]
public const R12: RegisterId = 12u32
@When[arch == "x86_64"]
public const R13: RegisterId = 13u32
@When[arch == "x86_64"]
public const R14: RegisterId = 14u32
@When[arch == "x86_64"]
public const R15: RegisterId = 15u32
@When[arch == "x86_64"]
public const RIP: RegisterId = 16u32
@When[arch == "x86_64"]
public const XMM0: RegisterId = 17u32
@When[arch == "x86_64"]
public const XMM1: RegisterId = 18u32
@When[arch == "x86_64"]
public const XMM2: RegisterId = 19u32
@When[arch == "x86_64"]
public const XMM3: RegisterId = 20u32
@When[arch == "x86_64"]
public const XMM4: RegisterId = 21u32
@When[arch == "x86_64"]
public const XMM5: RegisterId = 22u32
@When[arch == "x86_64"]
public const XMM6: RegisterId = 23u32
@When[arch == "x86_64"]
public const XMM7: RegisterId = 24u32
@When[arch == "x86_64"]
public const XMM8: RegisterId = 25u32
@When[arch == "x86_64"]
public const XMM9: RegisterId = 26u32
@When[arch == "x86_64"]
public const XMM10: RegisterId = 27u32
@When[arch == "x86_64"]
public const XMM11: RegisterId = 28u32
@When[arch == "x86_64"]
public const XMM12: RegisterId = 29u32
@When[arch == "x86_64"]
public const XMM13: RegisterId = 30u32
@When[arch == "x86_64"]
public const XMM14: RegisterId = 31u32
@When[arch == "x86_64"]
public const XMM15: RegisterId = 32u32
@When[arch == "x86_64"]
public const REGISTERS_COUNT: RegisterId = 33u32

// Common/RegisterAarch64.h:33-99.
@When[arch == "aarch64"]
public const X0: RegisterId = 0u32
@When[arch == "aarch64"]
public const X1: RegisterId = 1u32
@When[arch == "aarch64"]
public const X2: RegisterId = 2u32
@When[arch == "aarch64"]
public const X3: RegisterId = 3u32
@When[arch == "aarch64"]
public const X4: RegisterId = 4u32
@When[arch == "aarch64"]
public const X5: RegisterId = 5u32
@When[arch == "aarch64"]
public const X6: RegisterId = 6u32
@When[arch == "aarch64"]
public const X7: RegisterId = 7u32
@When[arch == "aarch64"]
public const X8: RegisterId = 8u32
@When[arch == "aarch64"]
public const X9: RegisterId = 9u32
@When[arch == "aarch64"]
public const X10: RegisterId = 10u32
@When[arch == "aarch64"]
public const X11: RegisterId = 11u32
@When[arch == "aarch64"]
public const X12: RegisterId = 12u32
@When[arch == "aarch64"]
public const X13: RegisterId = 13u32
@When[arch == "aarch64"]
public const X14: RegisterId = 14u32
@When[arch == "aarch64"]
public const X15: RegisterId = 15u32
@When[arch == "aarch64"]
public const X16: RegisterId = 16u32
@When[arch == "aarch64"]
public const X17: RegisterId = 17u32
@When[arch == "aarch64"]
public const X18: RegisterId = 18u32
@When[arch == "aarch64"]
public const X19: RegisterId = 19u32
@When[arch == "aarch64"]
public const X20: RegisterId = 20u32
@When[arch == "aarch64"]
public const X21: RegisterId = 21u32
@When[arch == "aarch64"]
public const X22: RegisterId = 22u32
@When[arch == "aarch64"]
public const X23: RegisterId = 23u32
@When[arch == "aarch64"]
public const X24: RegisterId = 24u32
@When[arch == "aarch64"]
public const X25: RegisterId = 25u32
@When[arch == "aarch64"]
public const X26: RegisterId = 26u32
@When[arch == "aarch64"]
public const X27: RegisterId = 27u32
@When[arch == "aarch64"]
public const X28: RegisterId = 28u32
@When[arch == "aarch64"]
public const X29: RegisterId = 29u32
@When[arch == "aarch64"]
public const X30: RegisterId = 30u32
@When[arch == "aarch64"]
public const X31: RegisterId = 31u32
@When[arch == "aarch64"]
public const D0: RegisterId = 32u32
@When[arch == "aarch64"]
public const D1: RegisterId = 33u32
@When[arch == "aarch64"]
public const D2: RegisterId = 34u32
@When[arch == "aarch64"]
public const D3: RegisterId = 35u32
@When[arch == "aarch64"]
public const D4: RegisterId = 36u32
@When[arch == "aarch64"]
public const D5: RegisterId = 37u32
@When[arch == "aarch64"]
public const D6: RegisterId = 38u32
@When[arch == "aarch64"]
public const D7: RegisterId = 39u32
@When[arch == "aarch64"]
public const D8: RegisterId = 40u32
@When[arch == "aarch64"]
public const D9: RegisterId = 41u32
@When[arch == "aarch64"]
public const D10: RegisterId = 42u32
@When[arch == "aarch64"]
public const D11: RegisterId = 43u32
@When[arch == "aarch64"]
public const D12: RegisterId = 44u32
@When[arch == "aarch64"]
public const D13: RegisterId = 45u32
@When[arch == "aarch64"]
public const D14: RegisterId = 46u32
@When[arch == "aarch64"]
public const D15: RegisterId = 47u32
@When[arch == "aarch64"]
public const D16: RegisterId = 48u32
@When[arch == "aarch64"]
public const D17: RegisterId = 49u32
@When[arch == "aarch64"]
public const D18: RegisterId = 50u32
@When[arch == "aarch64"]
public const D19: RegisterId = 51u32
@When[arch == "aarch64"]
public const D20: RegisterId = 52u32
@When[arch == "aarch64"]
public const D21: RegisterId = 53u32
@When[arch == "aarch64"]
public const D22: RegisterId = 54u32
@When[arch == "aarch64"]
public const D23: RegisterId = 55u32
@When[arch == "aarch64"]
public const D24: RegisterId = 56u32
@When[arch == "aarch64"]
public const D25: RegisterId = 57u32
@When[arch == "aarch64"]
public const D26: RegisterId = 58u32
@When[arch == "aarch64"]
public const D27: RegisterId = 59u32
@When[arch == "aarch64"]
public const D28: RegisterId = 60u32
@When[arch == "aarch64"]
public const D29: RegisterId = 61u32
@When[arch == "aarch64"]
public const D30: RegisterId = 62u32
@When[arch == "aarch64"]
public const D31: RegisterId = 63u32
@When[arch == "aarch64"]
public const REGISTERS_COUNT: RegisterId = 64u32

// Common/RegisterArm.h:14-64.
@When[arch == "arm"]
public const R0: RegisterId = 0u32
@When[arch == "arm"]
public const R1: RegisterId = 1u32
@When[arch == "arm"]
public const R2: RegisterId = 2u32
@When[arch == "arm"]
public const R3: RegisterId = 3u32
@When[arch == "arm"]
public const R4: RegisterId = 4u32
@When[arch == "arm"]
public const R5: RegisterId = 5u32
@When[arch == "arm"]
public const R6: RegisterId = 6u32
@When[arch == "arm"]
public const R7: RegisterId = 7u32
@When[arch == "arm"]
public const R8: RegisterId = 8u32
@When[arch == "arm"]
public const R9: RegisterId = 9u32
@When[arch == "arm"]
public const R10: RegisterId = 10u32
@When[arch == "arm"]
public const R11: RegisterId = 11u32
@When[arch == "arm"]
public const R12: RegisterId = 12u32
@When[arch == "arm"]
public const R13: RegisterId = 13u32
@When[arch == "arm"]
public const R14: RegisterId = 14u32
@When[arch == "arm"]
public const R15: RegisterId = 15u32
@When[arch == "arm"]
public const D0: RegisterId = 16u32
@When[arch == "arm"]
public const D1: RegisterId = 17u32
@When[arch == "arm"]
public const D2: RegisterId = 18u32
@When[arch == "arm"]
public const D3: RegisterId = 19u32
@When[arch == "arm"]
public const D4: RegisterId = 20u32
@When[arch == "arm"]
public const D5: RegisterId = 21u32
@When[arch == "arm"]
public const D6: RegisterId = 22u32
@When[arch == "arm"]
public const D7: RegisterId = 23u32
@When[arch == "arm"]
public const D8: RegisterId = 24u32
@When[arch == "arm"]
public const D9: RegisterId = 25u32
@When[arch == "arm"]
public const D10: RegisterId = 26u32
@When[arch == "arm"]
public const D11: RegisterId = 27u32
@When[arch == "arm"]
public const D12: RegisterId = 28u32
@When[arch == "arm"]
public const D13: RegisterId = 29u32
@When[arch == "arm"]
public const D14: RegisterId = 30u32
@When[arch == "arm"]
public const D15: RegisterId = 31u32
@When[arch == "arm"]
public const D16: RegisterId = 32u32
@When[arch == "arm"]
public const D17: RegisterId = 33u32
@When[arch == "arm"]
public const D18: RegisterId = 34u32
@When[arch == "arm"]
public const D19: RegisterId = 35u32
@When[arch == "arm"]
public const D20: RegisterId = 36u32
@When[arch == "arm"]
public const D21: RegisterId = 37u32
@When[arch == "arm"]
public const D22: RegisterId = 38u32
@When[arch == "arm"]
public const D23: RegisterId = 39u32
@When[arch == "arm"]
public const D24: RegisterId = 40u32
@When[arch == "arm"]
public const D25: RegisterId = 41u32
@When[arch == "arm"]
public const D26: RegisterId = 42u32
@When[arch == "arm"]
public const D27: RegisterId = 43u32
@When[arch == "arm"]
public const D28: RegisterId = 44u32
@When[arch == "arm"]
public const D29: RegisterId = 45u32
@When[arch == "arm"]
public const D30: RegisterId = 46u32
@When[arch == "arm"]
public const D31: RegisterId = 47u32
@When[arch == "arm"]
public const REGISTERS_COUNT: RegisterId = 48u32

// Common/RegisterX86-64.h:59-69. Six-byte NUL-terminated slots followed by "wrong register".
@When[arch == "x86_64"]
var platformRegister: VArray<UInt8, $213> = [
    114u8, 97u8, 120u8, 0u8, 0u8, 0u8, 114u8, 100u8, 120u8, 0u8, 0u8, 0u8, 114u8, 99u8, 120u8, 0u8,
    0u8, 0u8, 114u8, 98u8, 120u8, 0u8, 0u8, 0u8, 114u8, 115u8, 105u8, 0u8, 0u8, 0u8, 114u8, 100u8,
    105u8, 0u8, 0u8, 0u8, 114u8, 98u8, 112u8, 0u8, 0u8, 0u8, 114u8, 115u8, 112u8, 0u8, 0u8, 0u8,
    114u8, 56u8, 0u8, 0u8, 0u8, 0u8, 114u8, 57u8, 0u8, 0u8, 0u8, 0u8, 114u8, 49u8, 48u8, 0u8,
    0u8, 0u8, 114u8, 49u8, 49u8, 0u8, 0u8, 0u8, 114u8, 49u8, 50u8, 0u8, 0u8, 0u8, 114u8, 49u8,
    51u8, 0u8, 0u8, 0u8, 114u8, 49u8, 52u8, 0u8, 0u8, 0u8, 114u8, 49u8, 53u8, 0u8, 0u8, 0u8,
    114u8, 105u8, 112u8, 0u8, 0u8, 0u8, 120u8, 109u8, 109u8, 48u8, 0u8, 0u8, 120u8, 109u8, 109u8, 49u8,
    0u8, 0u8, 120u8, 109u8, 109u8, 50u8, 0u8, 0u8, 120u8, 109u8, 109u8, 51u8, 0u8, 0u8, 120u8, 109u8,
    109u8, 52u8, 0u8, 0u8, 120u8, 109u8, 109u8, 53u8, 0u8, 0u8, 120u8, 109u8, 109u8, 54u8, 0u8, 0u8,
    120u8, 109u8, 109u8, 55u8, 0u8, 0u8, 120u8, 109u8, 109u8, 56u8, 0u8, 0u8, 120u8, 109u8, 109u8, 57u8,
    0u8, 0u8, 120u8, 109u8, 109u8, 49u8, 48u8, 0u8, 120u8, 109u8, 109u8, 49u8, 49u8, 0u8, 120u8, 109u8,
    109u8, 49u8, 50u8, 0u8, 120u8, 109u8, 109u8, 49u8, 51u8, 0u8, 120u8, 109u8, 109u8, 49u8, 52u8, 0u8,
    120u8, 109u8, 109u8, 49u8, 53u8, 0u8, 119u8, 114u8, 111u8, 110u8, 103u8, 32u8, 114u8, 101u8, 103u8, 105u8,
    115u8, 116u8, 101u8, 114u8, 0u8
]

// Common/RegisterAarch64.h:100-112. Four-byte NUL-terminated slots followed by "wrong register".
@When[arch == "aarch64"]
var platformRegister: VArray<UInt8, $271> = [
    120u8, 48u8, 0u8, 0u8, 120u8, 49u8, 0u8, 0u8, 120u8, 50u8, 0u8, 0u8, 120u8, 51u8, 0u8, 0u8,
    120u8, 52u8, 0u8, 0u8, 120u8, 53u8, 0u8, 0u8, 120u8, 54u8, 0u8, 0u8, 120u8, 55u8, 0u8, 0u8,
    120u8, 56u8, 0u8, 0u8, 120u8, 57u8, 0u8, 0u8, 120u8, 49u8, 48u8, 0u8, 120u8, 49u8, 49u8, 0u8,
    120u8, 49u8, 50u8, 0u8, 120u8, 49u8, 51u8, 0u8, 120u8, 49u8, 52u8, 0u8, 120u8, 49u8, 53u8, 0u8,
    120u8, 49u8, 54u8, 0u8, 120u8, 49u8, 55u8, 0u8, 120u8, 49u8, 56u8, 0u8, 120u8, 49u8, 57u8, 0u8,
    120u8, 50u8, 48u8, 0u8, 120u8, 50u8, 49u8, 0u8, 120u8, 50u8, 50u8, 0u8, 120u8, 50u8, 51u8, 0u8,
    120u8, 50u8, 52u8, 0u8, 120u8, 50u8, 53u8, 0u8, 120u8, 50u8, 54u8, 0u8, 120u8, 50u8, 55u8, 0u8,
    120u8, 50u8, 56u8, 0u8, 120u8, 50u8, 57u8, 0u8, 120u8, 51u8, 48u8, 0u8, 120u8, 51u8, 49u8, 0u8,
    100u8, 48u8, 0u8, 0u8, 100u8, 49u8, 0u8, 0u8, 100u8, 50u8, 0u8, 0u8, 100u8, 51u8, 0u8, 0u8,
    100u8, 52u8, 0u8, 0u8, 100u8, 53u8, 0u8, 0u8, 100u8, 54u8, 0u8, 0u8, 100u8, 55u8, 0u8, 0u8,
    100u8, 56u8, 0u8, 0u8, 100u8, 57u8, 0u8, 0u8, 100u8, 49u8, 48u8, 0u8, 100u8, 49u8, 49u8, 0u8,
    100u8, 49u8, 50u8, 0u8, 100u8, 49u8, 51u8, 0u8, 100u8, 49u8, 52u8, 0u8, 100u8, 49u8, 53u8, 0u8,
    100u8, 49u8, 54u8, 0u8, 100u8, 49u8, 55u8, 0u8, 100u8, 49u8, 56u8, 0u8, 100u8, 49u8, 57u8, 0u8,
    100u8, 50u8, 48u8, 0u8, 100u8, 50u8, 49u8, 0u8, 100u8, 50u8, 50u8, 0u8, 100u8, 50u8, 51u8, 0u8,
    100u8, 50u8, 52u8, 0u8, 100u8, 50u8, 53u8, 0u8, 100u8, 50u8, 54u8, 0u8, 100u8, 50u8, 55u8, 0u8,
    100u8, 50u8, 56u8, 0u8, 100u8, 50u8, 57u8, 0u8, 100u8, 51u8, 48u8, 0u8, 100u8, 51u8, 49u8, 0u8,
    119u8, 114u8, 111u8, 110u8, 103u8, 32u8, 114u8, 101u8, 103u8, 105u8, 115u8, 116u8, 101u8, 114u8, 0u8
]

// Common/RegisterArm.h:65-76. Four-byte NUL-terminated slots followed by "wrong register".
@When[arch == "arm"]
var platformRegister: VArray<UInt8, $207> = [
    114u8, 48u8, 0u8, 0u8, 114u8, 49u8, 0u8, 0u8, 114u8, 50u8, 0u8, 0u8, 114u8, 51u8, 0u8, 0u8,
    114u8, 52u8, 0u8, 0u8, 114u8, 53u8, 0u8, 0u8, 114u8, 54u8, 0u8, 0u8, 114u8, 55u8, 0u8, 0u8,
    114u8, 56u8, 0u8, 0u8, 114u8, 57u8, 0u8, 0u8, 114u8, 49u8, 48u8, 0u8, 114u8, 49u8, 49u8, 0u8,
    114u8, 49u8, 50u8, 0u8, 114u8, 49u8, 51u8, 0u8, 114u8, 49u8, 52u8, 0u8, 114u8, 49u8, 53u8, 0u8,
    100u8, 48u8, 0u8, 0u8, 100u8, 49u8, 0u8, 0u8, 100u8, 50u8, 0u8, 0u8, 100u8, 51u8, 0u8, 0u8,
    100u8, 52u8, 0u8, 0u8, 100u8, 53u8, 0u8, 0u8, 100u8, 54u8, 0u8, 0u8, 100u8, 55u8, 0u8, 0u8,
    100u8, 56u8, 0u8, 0u8, 100u8, 57u8, 0u8, 0u8, 100u8, 49u8, 48u8, 0u8, 100u8, 49u8, 49u8, 0u8,
    100u8, 49u8, 50u8, 0u8, 100u8, 49u8, 51u8, 0u8, 100u8, 49u8, 52u8, 0u8, 100u8, 49u8, 53u8, 0u8,
    100u8, 49u8, 54u8, 0u8, 100u8, 49u8, 55u8, 0u8, 100u8, 49u8, 56u8, 0u8, 100u8, 49u8, 57u8, 0u8,
    100u8, 50u8, 48u8, 0u8, 100u8, 50u8, 49u8, 0u8, 100u8, 50u8, 50u8, 0u8, 100u8, 50u8, 51u8, 0u8,
    100u8, 50u8, 52u8, 0u8, 100u8, 50u8, 53u8, 0u8, 100u8, 50u8, 54u8, 0u8, 100u8, 50u8, 55u8, 0u8,
    100u8, 50u8, 56u8, 0u8, 100u8, 50u8, 57u8, 0u8, 100u8, 51u8, 48u8, 0u8, 100u8, 51u8, 49u8, 0u8,
    119u8, 114u8, 111u8, 110u8, 103u8, 32u8, 114u8, 101u8, 103u8, 105u8, 115u8, 116u8, 101u8, 114u8, 0u8
]

// Common/RegisterX86-64.h:72-79.
@When[arch == "x86_64" && os == "Windows"]
var calleeSaved: VArray<UInt32, $17> = [
    RBX, RSI, RDI, R12, R13, R14, R15, XMM6, XMM7, XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15
]
// Common/RegisterX86-64.h:73-75.
@When[arch == "x86_64" && os == "Windows"]
const calleeSavedNum: UInt32 = 17u32

// Common/RegisterX86-64.h:76-79.
@When[arch == "x86_64" && os != "Windows"]
var calleeSaved: VArray<UInt32, $5> = [RBX, R12, R13, R14, R15]
// Common/RegisterX86-64.h:77-78.
@When[arch == "x86_64" && os != "Windows"]
const calleeSavedNum: UInt32 = 5u32

// Common/RegisterAarch64.h:113-121.
@When[arch == "aarch64"]
var calleeSaved: VArray<UInt32, $20> = [
    X19, X20, X21, X22, X23, X24, X25, X26, X27, X28, X29, X30, D8, D9, D10, D11, D12, D13, D14, D15
]
// Common/RegisterAarch64.h:115-117.
@When[arch == "aarch64"]
const calleeSavedNum: UInt32 = 20u32

// Common/RegisterArm.h:77-85.
@When[arch == "arm"]
var calleeSaved: VArray<UInt32, $17> = [R4, R5, R6, R7, R8, R9, R10, R11, R14, D8, D9, D10, D11, D12, D13, D14, D15]
// Common/RegisterArm.h:79-81.
@When[arch == "arm"]
const calleeSavedNum: UInt32 = 17u32

// Common/RegisterX86-64.h:80, RegisterAarch64.h:118-120, RegisterArm.h:82-84;
// Base/Log.cpp:417-419. RtFatal is the existing rt.base fatal terminator and does not return.
foreign func RtFatal(message: CString): Unit

// Common/RegisterX86-64.h:80, RegisterAarch64.h:119, RegisterArm.h:83.
var calleeSavedError: VArray<UInt8, $41> = [
    114u8, 101u8, 103u8, 105u8, 115u8, 116u8, 101u8, 114u8, 32u8, 105u8, 100u8, 32u8, 105u8, 115u8,
    32u8, 110u8, 111u8, 116u8, 32u8, 99u8, 97u8, 108u8, 108u8, 101u8, 101u8, 32u8, 115u8, 97u8,
    118u8, 101u8, 100u8, 32u8, 114u8, 101u8, 103u8, 105u8, 115u8, 116u8, 101u8, 114u8, 0u8
]

// Common/RegisterX86-64.h:59-69.
@When[arch == "x86_64"]
public func GetRegisterName(idx: UInt32): CString {
    let offset = if (idx >= REGISTERS_COUNT) { 198 } else { Int64(idx) * 6 }
    return unsafe { CString(CPointer<UInt8>(inout platformRegister) + offset) }
}

// Common/RegisterAarch64.h:100-112.
@When[arch == "aarch64"]
public func GetRegisterName(idx: UInt32): CString {
    let offset = if (idx >= REGISTERS_COUNT) { 256 } else { Int64(idx) * 4 }
    return unsafe { CString(CPointer<UInt8>(inout platformRegister) + offset) }
}

// Common/RegisterArm.h:65-76.
@When[arch == "arm"]
public func GetRegisterName(idx: UInt32): CString {
    let offset = if (idx >= REGISTERS_COUNT) { 192 } else { Int64(idx) * 4 }
    return unsafe { CString(CPointer<UInt8>(inout platformRegister) + offset) }
}

// Common/RegisterX86-64.h:70-82, RegisterAarch64.h:113-121, RegisterArm.h:77-85.
public func ResolveCalleeSaved(idx: UInt32): UInt32 {
    if (idx >= calleeSavedNum) {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout calleeSavedError))) }
    }
    return calleeSaved[Int64(idx)]
}
