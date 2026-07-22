package rt.exception

import rt.base.*

// Exception/CalleeSavedRegisterContext.h:17-21. Win64 stores each XMM register
// as the exact low/high pair used by CONTEXT restoration.
@When[os == "Windows" && arch == "x86_64"]
@C
public struct XMMReg {
    public var low: UInt64
    public var high: UInt64

    public init() {
        low = 0u64
        high = 0u64
    }
}

// Exception/CalleeSavedRegisterContext.h:23-31. Linux/OHOS and Apple x86_64
// share the seven-word System V record; Win64 is a distinct later branch.
@When[(os == "Linux" || env == "ohos" || os == "macOS" || os == "iOS") && arch == "x86_64"]
@C
public struct CalleeSavedRegisterContext {
    public var rbx: UInt64
    public var r12: UInt64
    public var r13: UInt64
    public var r14: UInt64
    public var r15: UInt64
    public var rbp: UInt64
    public var rsp: UInt64

    public init() {
        rbx = 0u64
        r12 = 0u64
        r13 = 0u64
        r14 = 0u64
        r15 = 0u64
        rbp = 0u64
        rsp = 0u64
    }
}

// Exception/CalleeSavedRegisterContext.h:32-54. AArch64 uses the same record
// on Linux/OHOS and Apple: x19-x30, d8-d15, then sp.
@When[arch == "aarch64"]
@C
public struct CalleeSavedRegisterContext {
    public var x19: UInt64
    public var x20: UInt64
    public var x21: UInt64
    public var x22: UInt64
    public var x23: UInt64
    public var x24: UInt64
    public var x25: UInt64
    public var x26: UInt64
    public var x27: UInt64
    public var x28: UInt64
    public var x29: UInt64
    public var x30: UInt64
    public var d8: UInt64
    public var d9: UInt64
    public var d10: UInt64
    public var d11: UInt64
    public var d12: UInt64
    public var d13: UInt64
    public var d14: UInt64
    public var d15: UInt64
    public var sp: UInt64

    public init() {
        x19 = 0u64
        x20 = 0u64
        x21 = 0u64
        x22 = 0u64
        x23 = 0u64
        x24 = 0u64
        x25 = 0u64
        x26 = 0u64
        x27 = 0u64
        x28 = 0u64
        x29 = 0u64
        x30 = 0u64
        d8 = 0u64
        d9 = 0u64
        d10 = 0u64
        d11 = 0u64
        d12 = 0u64
        d13 = 0u64
        d14 = 0u64
        d15 = 0u64
        sp = 0u64
    }
}

// Exception/CalleeSavedRegisterContext.h:55-75. ARM32 preserves the header's
// mixed-width order; @C supplies the native four-byte pad before d8 and tail pad.
@When[arch == "arm"]
@C
public struct CalleeSavedRegisterContext {
    public var r4: UInt32
    public var r5: UInt32
    public var r6: UInt32
    public var r7: UInt32
    public var r8: UInt32
    public var r9: UInt32
    public var r10: UInt32
    public var r11: UInt32
    public var lr: UInt32
    public var d8: UInt64
    public var d9: UInt64
    public var d10: UInt64
    public var d11: UInt64
    public var d12: UInt64
    public var d13: UInt64
    public var d14: UInt64
    public var d15: UInt64
    public var sp: UInt32

    public init() {
        r4 = 0u32
        r5 = 0u32
        r6 = 0u32
        r7 = 0u32
        r8 = 0u32
        r9 = 0u32
        r10 = 0u32
        r11 = 0u32
        lr = 0u32
        d8 = 0u64
        d9 = 0u64
        d10 = 0u64
        d11 = 0u64
        d12 = 0u64
        d13 = 0u64
        d14 = 0u64
        d15 = 0u64
        sp = 0u32
    }
}

// Exception/CalleeSavedRegisterContext.h:76-94. Win64's padding word is an
// explicit ABI field, followed by ten 16-byte XMM records and rbp/rsp.
@When[os == "Windows" && arch == "x86_64"]
@C
public struct CalleeSavedRegisterContext {
    public var rbx: UInt64
    public var rsi: UInt64
    public var rdi: UInt64
    public var r12: UInt64
    public var r13: UInt64
    public var r14: UInt64
    public var r15: UInt64
    public var padding: UInt64
    public var xmm6: XMMReg
    public var xmm7: XMMReg
    public var xmm8: XMMReg
    public var xmm9: XMMReg
    public var xmm10: XMMReg
    public var xmm11: XMMReg
    public var xmm12: XMMReg
    public var xmm13: XMMReg
    public var xmm14: XMMReg
    public var xmm15: XMMReg
    public var rbp: UInt64
    public var rsp: UInt64

    public init() {
        rbx = 0u64
        rsi = 0u64
        rdi = 0u64
        r12 = 0u64
        r13 = 0u64
        r14 = 0u64
        r15 = 0u64
        padding = 0u64
        xmm6 = XMMReg()
        xmm7 = XMMReg()
        xmm8 = XMMReg()
        xmm9 = XMMReg()
        xmm10 = XMMReg()
        xmm11 = XMMReg()
        xmm12 = XMMReg()
        xmm13 = XMMReg()
        xmm14 = XMMReg()
        xmm15 = XMMReg()
        rbp = 0u64
        rsp = 0u64
    }

    // Exception/CalleeSavedRegisterContext.h:96-104. Eight UInt64 slots skip
    // the seven integer registers plus padding; each XMM consumes two slots.
    @NoHeapAlloc
    public mut func SetXMMValueByIdx(xmmIdx: UInt32, value: CPointer<XMMReg>): Unit {
        let slot = unsafe { CPointer<UInt64>(inout this) + 8 + Int64(2u32 * xmmIdx) }
        unsafe {
            slot.write(0, value.read().low)
            slot.write(1, value.read().high)
        }
    }
}

extend CalleeSavedRegisterContext {
    // Exception/CalleeSavedRegisterContext.h:107-112. ArchUInt preserves the
    // C++ target-width slot walk, including 32-bit ARM's four-byte indexing.
    @NoHeapAlloc
    public mut func SetValueByIdx(idx: UInt32, value: ArchUInt): Unit {
        unsafe { CPointer<ArchUInt>(inout this).write(Int64(idx), value) }
    }
}
