package rt.common

// Common/StackType.h:25. The C++ uint64_t stores INT_MAX without widening its value.
public const STACK_UNWIND_STEP_MAX: UInt64 = 2147483647u64

// Common/StackType.h:27-38. C++ scoped enums use the default four-byte signed int ABI.
public type FrameType = Int32

// Common/StackType.h:28-37.
public const UNKNOWN: FrameType = 0
public const MANAGED: FrameType = 1
public const N2C_STUB: FrameType = 2
public const C2N_STUB: FrameType = 3
public const RUNTIME: FrameType = 4
public const SAFEPOINT: FrameType = 5
public const C2R_STUB: FrameType = 6
public const NATIVE: FrameType = 7
public const STACKGROW: FrameType = 8
public const EXSLUSIVE: FrameType = 9

// Common/StackType.h:40-44. C++ scoped enums use the default four-byte signed int ABI.
public type StackMode = Int32

// Common/StackType.h:41-43.
public const EH: StackMode = 0
public const GC: StackMode = 1
public const PRINT: StackMode = 2

// Common/StackType.h:46-53. C++ scoped enums use the default four-byte signed int ABI.
public type UnwindContextStatus = Int32

// Common/StackType.h:47-53. FrameType::UNKNOWN already occupies the package-level spelling;
// the minimal consistent mapping is UnwindContextStatus::{X} -> UNWIND_{X}.
public const UNWIND_UNKNOWN: UnwindContextStatus = 0
public const UNWIND_RELIABLE: UnwindContextStatus = 1
public const UNWIND_RISKY: UnwindContextStatus = 2
public const UNWIND_SIGNAL_STATUS: UnwindContextStatus = 3

// Common/StackType.h:55-65. Shared by Linux/OHOS/Apple/Windows; the executable pointer-size
// layout gate is Linux x86_64, but the production descriptor has no platform branch.
@C
public struct FrameAddress {
    // Common/StackType.h:62-65.
    public var callerFrameAddress: CPointer<FrameAddress>
    public var returnAddress: CPointer<UInt32>

    // Common/StackType.h:62-65. Cangjie aggregate initialization preserves C++ field order.
    public init(callerFrameAddress: CPointer<FrameAddress>, returnAddress: CPointer<UInt32>) {
        unsafe {
            this.callerFrameAddress = callerFrameAddress
            this.returnAddress = returnAddress
        }
    }
}

// Common/StackType.h:67-73. The field order matches the r2c_stub slot layout.
@C
public struct N2CSlotData {
    // Common/StackType.h:69-73.
    public var pc: CPointer<UInt32>
    public var fa: CPointer<FrameAddress>
    public var status: UnwindContextStatus

    // Common/StackType.h:69-73. Cangjie aggregate initialization preserves C++ field order.
    public init(pc: CPointer<UInt32>, fa: CPointer<FrameAddress>, status: UnwindContextStatus) {
        unsafe {
            this.pc = pc
            this.fa = fa
        }
        this.status = status
    }
}

// Common/TypeDef.h:36-40. C++ ArrayRef is the opaque MArray* managed-pointer category.
// This leaf preserves one native pointer and pointer identity only; it implements no GC container.
public type ArrayRef = CPointer<Unit>

// Common/StackType.h:83-89. Shared by Linux/OHOS/Apple/Windows; Linux x86_64 gates layout.
@C
public struct StackTraceData {
    // Common/StackType.h:84-89.
    public var className: ArrayRef
    public var methodName: ArrayRef
    public var fileName: ArrayRef
    public var lineNumber: Int64

    // Common/StackType.h:84-89. Cangjie aggregate initialization preserves C++ field order.
    public init(className: ArrayRef, methodName: ArrayRef, fileName: ArrayRef, lineNumber: Int64) {
        unsafe {
            this.className = className
            this.methodName = methodName
            this.fileName = fileName
        }
        this.lineNumber = lineNumber
    }
}

// Common/StackType.h:91-97. Shared by Linux/OHOS/Apple/Windows; Linux x86_64 gates layout.
@C
public struct ThreadSnapshot {
    // Common/StackType.h:92-97.
    public var name: ArrayRef
    public var id: Int64
    public var stackTrace: ArrayRef
    public var state: Int64

    // Common/StackType.h:92-97. Cangjie aggregate initialization preserves C++ field order.
    public init(name: ArrayRef, id: Int64, stackTrace: ArrayRef, state: Int64) {
        unsafe { this.name = name }
        this.id = id
        unsafe { this.stackTrace = stackTrace }
        this.state = state
    }
}
