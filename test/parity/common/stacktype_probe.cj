import rt.common.*
import rt.common.ThreadSnapshot as RuntimeThreadSnapshot

// Common/StackType.h:25-73,83-98 and Common/TypeDef.h:36-40 executable ABI parity entry.
main(): Int64 {
    println("CONST STACK_UNWIND_STEP_MAX ${STACK_UNWIND_STEP_MAX}")
    println("ENUM FrameType UNKNOWN ${UNKNOWN}")
    println("ENUM FrameType MANAGED ${MANAGED}")
    println("ENUM FrameType N2C_STUB ${N2C_STUB}")
    println("ENUM FrameType C2N_STUB ${C2N_STUB}")
    println("ENUM FrameType RUNTIME ${RUNTIME}")
    println("ENUM FrameType SAFEPOINT ${SAFEPOINT}")
    println("ENUM FrameType C2R_STUB ${C2R_STUB}")
    println("ENUM FrameType NATIVE ${NATIVE}")
    println("ENUM FrameType STACKGROW ${STACKGROW}")
    println("ENUM FrameType EXSLUSIVE ${EXSLUSIVE}")
    println("ENUM StackMode EH ${EH}")
    println("ENUM StackMode GC ${GC}")
    println("ENUM StackMode PRINT ${PRINT}")
    println("ENUM UnwindContextStatus UNKNOWN ${UNWIND_UNKNOWN}")
    println("ENUM UnwindContextStatus RELIABLE ${UNWIND_RELIABLE}")
    println("ENUM UnwindContextStatus RISKY ${UNWIND_RISKY}")
    println("ENUM UnwindContextStatus SIGNAL_STATUS ${UNWIND_SIGNAL_STATUS}")

    // Common/StackType.h:27-53. C++ scoped-enum storage is signed int.
    println("LAYOUT FrameType ${sizeOf<FrameType>()} ${alignOf<FrameType>()}")
    println("LAYOUT StackMode ${sizeOf<StackMode>()} ${alignOf<StackMode>()}")
    println("LAYOUT UnwindContextStatus ${sizeOf<UnwindContextStatus>()} ${alignOf<UnwindContextStatus>()}")
    if (sizeOf<FrameType>() != 4 || alignOf<FrameType>() != 4 ||
        sizeOf<StackMode>() != 4 || alignOf<StackMode>() != 4 ||
        sizeOf<UnwindContextStatus>() != 4 || alignOf<UnwindContextStatus>() != 4) {
        return 1
    }

    // Common/StackType.h:62-65. Zero the complete object before assigning sentinel pointers.
    var frameAddress = unsafe { FrameAddress(CPointer<FrameAddress>(), CPointer<UInt32>()) }
    unsafe {
        let frameBytes = CPointer<UInt8>(inout frameAddress)
        var frameZeroIndex: Int64 = 0
        while (frameZeroIndex < Int64(sizeOf<FrameAddress>())) {
            (frameBytes + frameZeroIndex).write(0u8)
            frameZeroIndex += 1
        }
        var frameCallerBits: UIntNative = UIntNative(0x1122334455667788u64)
        var frameReturnBits: UIntNative = UIntNative(0x2233445566778899u64)
        frameAddress.callerFrameAddress = CPointer<CPointer<FrameAddress>>(inout frameCallerBits).read()
        frameAddress.returnAddress = CPointer<CPointer<UInt32>>(inout frameReturnBits).read()
    }
    let frameBase = unsafe { CPointer<UInt8>(inout frameAddress).toUIntNative() }
    let frameCallerOffset = unsafe {
        CPointer<UInt8>(inout frameAddress.callerFrameAddress).toUIntNative() - frameBase
    }
    let frameReturnOffset = unsafe {
        CPointer<UInt8>(inout frameAddress.returnAddress).toUIntNative() - frameBase
    }
    println("LAYOUT FrameAddress ${sizeOf<FrameAddress>()} ${alignOf<FrameAddress>()} " +
        "${frameCallerOffset} ${frameReturnOffset}")
    if (sizeOf<FrameAddress>() != 16 || alignOf<FrameAddress>() != 8 ||
        frameCallerOffset != 0 || frameReturnOffset != 8) {
        return 2
    }

    // Common/StackType.h:69-73. Zero the complete object before assigning pointer and enum fields.
    var n2cSlotData = unsafe {
        N2CSlotData(CPointer<UInt32>(), CPointer<FrameAddress>(), UNWIND_UNKNOWN)
    }
    unsafe {
        let n2cBytes = CPointer<UInt8>(inout n2cSlotData)
        var n2cZeroIndex: Int64 = 0
        while (n2cZeroIndex < Int64(sizeOf<N2CSlotData>())) {
            (n2cBytes + n2cZeroIndex).write(0u8)
            n2cZeroIndex += 1
        }
        var n2cPcBits: UIntNative = UIntNative(0x33445566778899aau64)
        var n2cFaBits: UIntNative = UIntNative(0x445566778899aabbu64)
        n2cSlotData.pc = CPointer<CPointer<UInt32>>(inout n2cPcBits).read()
        n2cSlotData.fa = CPointer<CPointer<FrameAddress>>(inout n2cFaBits).read()
        n2cSlotData.status = UNWIND_RISKY
    }
    let n2cBase = unsafe { CPointer<UInt8>(inout n2cSlotData).toUIntNative() }
    let n2cPcOffset = unsafe { CPointer<UInt8>(inout n2cSlotData.pc).toUIntNative() - n2cBase }
    let n2cFaOffset = unsafe { CPointer<UInt8>(inout n2cSlotData.fa).toUIntNative() - n2cBase }
    let n2cStatusOffset = unsafe { CPointer<UInt8>(inout n2cSlotData.status).toUIntNative() - n2cBase }
    println("LAYOUT N2CSlotData ${sizeOf<N2CSlotData>()} ${alignOf<N2CSlotData>()} " +
        "${n2cPcOffset} ${n2cFaOffset} ${n2cStatusOffset}")
    if (sizeOf<N2CSlotData>() != 24 || alignOf<N2CSlotData>() != 8 ||
        n2cPcOffset != 0 || n2cFaOffset != 8 || n2cStatusOffset != 16) {
        return 3
    }

    // Common/StackType.h:84-89. Zero the complete object before assigning ArrayRef bit patterns.
    var stackTraceData = unsafe {
        StackTraceData(CPointer<Unit>(), CPointer<Unit>(), CPointer<Unit>(), 0)
    }
    unsafe {
        let stackTraceBytes = CPointer<UInt8>(inout stackTraceData)
        var stackTraceZeroIndex: Int64 = 0
        while (stackTraceZeroIndex < Int64(sizeOf<StackTraceData>())) {
            (stackTraceBytes + stackTraceZeroIndex).write(0u8)
            stackTraceZeroIndex += 1
        }
        var classNameBits: UIntNative = UIntNative(0x0102030405060708u64)
        var methodNameBits: UIntNative = UIntNative(0x1112131415161718u64)
        var fileNameBits: UIntNative = UIntNative(0x2122232425262728u64)
        stackTraceData.className = CPointer<CPointer<Unit>>(inout classNameBits).read()
        stackTraceData.methodName = CPointer<CPointer<Unit>>(inout methodNameBits).read()
        stackTraceData.fileName = CPointer<CPointer<Unit>>(inout fileNameBits).read()
        stackTraceData.lineNumber = -0x0102030405060708
    }
    let stackTraceBase = unsafe { CPointer<UInt8>(inout stackTraceData).toUIntNative() }
    let classNameOffset = unsafe {
        CPointer<UInt8>(inout stackTraceData.className).toUIntNative() - stackTraceBase
    }
    let methodNameOffset = unsafe {
        CPointer<UInt8>(inout stackTraceData.methodName).toUIntNative() - stackTraceBase
    }
    let fileNameOffset = unsafe {
        CPointer<UInt8>(inout stackTraceData.fileName).toUIntNative() - stackTraceBase
    }
    let lineNumberOffset = unsafe {
        CPointer<UInt8>(inout stackTraceData.lineNumber).toUIntNative() - stackTraceBase
    }
    println("LAYOUT StackTraceData ${sizeOf<StackTraceData>()} ${alignOf<StackTraceData>()} " +
        "${classNameOffset} ${methodNameOffset} ${fileNameOffset} ${lineNumberOffset}")
    if (sizeOf<StackTraceData>() != 32 || alignOf<StackTraceData>() != 8 || classNameOffset != 0 ||
        methodNameOffset != 8 || fileNameOffset != 16 || lineNumberOffset != 24) {
        return 4
    }

    // Common/StackType.h:92-97. Zero the complete object before assigning pointer and signed fields.
    var threadSnapshot = unsafe { RuntimeThreadSnapshot(CPointer<Unit>(), 0, CPointer<Unit>(), 0) }
    unsafe {
        let threadBytes = CPointer<UInt8>(inout threadSnapshot)
        var threadZeroIndex: Int64 = 0
        while (threadZeroIndex < Int64(sizeOf<RuntimeThreadSnapshot>())) {
            (threadBytes + threadZeroIndex).write(0u8)
            threadZeroIndex += 1
        }
        var threadNameBits: UIntNative = UIntNative(0x3132333435363738u64)
        var threadStackBits: UIntNative = UIntNative(0x4142434445464748u64)
        threadSnapshot.name = CPointer<CPointer<Unit>>(inout threadNameBits).read()
        threadSnapshot.id = -0x1112131415161718
        threadSnapshot.stackTrace = CPointer<CPointer<Unit>>(inout threadStackBits).read()
        threadSnapshot.state = 0x5152535455565758
    }
    let threadBase = unsafe { CPointer<UInt8>(inout threadSnapshot).toUIntNative() }
    let threadNameOffset = unsafe {
        CPointer<UInt8>(inout threadSnapshot.name).toUIntNative() - threadBase
    }
    let threadIdOffset = unsafe { CPointer<UInt8>(inout threadSnapshot.id).toUIntNative() - threadBase }
    let threadStackOffset = unsafe {
        CPointer<UInt8>(inout threadSnapshot.stackTrace).toUIntNative() - threadBase
    }
    let threadStateOffset = unsafe {
        CPointer<UInt8>(inout threadSnapshot.state).toUIntNative() - threadBase
    }
    println("LAYOUT ThreadSnapshot ${sizeOf<RuntimeThreadSnapshot>()} ${alignOf<RuntimeThreadSnapshot>()} " +
        "${threadNameOffset} ${threadIdOffset} ${threadStackOffset} ${threadStateOffset}")
    if (sizeOf<RuntimeThreadSnapshot>() != 32 || alignOf<RuntimeThreadSnapshot>() != 8 || threadNameOffset != 0 ||
        threadIdOffset != 8 || threadStackOffset != 16 || threadStateOffset != 24) {
        return 5
    }

    // Common/StackType.h:62-65. Raw bytes expose pointer order and full object padding.
    print("BYTES FrameAddress")
    unsafe {
        let frameDump = CPointer<UInt8>(inout frameAddress)
        var frameDumpIndex: Int64 = 0
        while (frameDumpIndex < Int64(sizeOf<FrameAddress>())) {
            print(" ${(frameDump + frameDumpIndex).read()}")
            frameDumpIndex += 1
        }
    }
    println()

    // Common/StackType.h:69-73. Raw bytes expose pointer order, enum width, and tail padding.
    print("BYTES N2CSlotData")
    unsafe {
        let n2cDump = CPointer<UInt8>(inout n2cSlotData)
        var n2cDumpIndex: Int64 = 0
        while (n2cDumpIndex < Int64(sizeOf<N2CSlotData>())) {
            print(" ${(n2cDump + n2cDumpIndex).read()}")
            n2cDumpIndex += 1
        }
    }
    println()

    // Common/StackType.h:84-89. Raw bytes expose three ArrayRef fields and signed lineNumber.
    print("BYTES StackTraceData")
    unsafe {
        let stackTraceDump = CPointer<UInt8>(inout stackTraceData)
        var stackTraceDumpIndex: Int64 = 0
        while (stackTraceDumpIndex < Int64(sizeOf<StackTraceData>())) {
            print(" ${(stackTraceDump + stackTraceDumpIndex).read()}")
            stackTraceDumpIndex += 1
        }
    }
    println()

    // Common/StackType.h:92-97. Raw bytes expose ArrayRef order and both signed Int64 fields.
    print("BYTES ThreadSnapshot")
    unsafe {
        let threadDump = CPointer<UInt8>(inout threadSnapshot)
        var threadDumpIndex: Int64 = 0
        while (threadDumpIndex < Int64(sizeOf<RuntimeThreadSnapshot>())) {
            print(" ${(threadDump + threadDumpIndex).read()}")
            threadDumpIndex += 1
        }
    }
    println()
    return 0
}
