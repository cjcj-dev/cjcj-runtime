package rt.common

// Common/TypeDef.h:21-23 and Base/Types.h:38-42. Managed addresses are native-width bits.
public type MAddress = UIntNative
public const NULL_ADDRESS: MAddress = 0

// Common/TypeDef.h:28-34 and Base/Types.h:27-30. Managed sizes/offsets are 32-bit;
// managed indices are 64-bit, while GENERIC_PAYLOAD_SIZE retains size_t width.
public type MSize = UInt32
public type MOffset = UInt32
public type MIndex = UInt64
public const GENERIC_PAYLOAD_SIZE: UIntNative = 2147483647
public const MAX_ARRAY_SIZE: MIndex = 18446744073709551615u64

// Common/TypeDef.h:36-63. Each incomplete managed/reference category is one borrowed
// native pointer. Forward-declared C++ object storage is intentionally not materialized here.
public type ObjRef = CPointer<Unit>
public type ArrayRef = CPointer<Unit>
public type FuncRef = CPointer<Unit>
public type FuncDescRef = CPointer<Unit>
public type StringRef = CPointer<Unit>
public type ExceptionRef = CPointer<Unit>
public type MethodInfoRef = CPointer<Unit>
public type PackageInfoRef = CPointer<Unit>
public type ParameterInfoRef = CPointer<Unit>

// Common/TypeDef.h:65. This preserves the callable C ABI void (*)(void*).
public type FuncPtr = CFunc<(CPointer<Unit>) -> Unit>

// Common/TypeDef.h:67-74. C++ scoped enums use the default four-byte signed int ABI.
public type AllocType = Int32
public const MOVEABLE_OBJECT: AllocType = 0
public const PINNED_OBJECT: AllocType = 1
public const RAW_POINTER_OBJECT: AllocType = 2

// Common/TypeDef.h:76-83. The header's only conditional is its C++ linkage wrapper;
// the alignment expression itself has no platform branch or validation.
@NoHeapAlloc
public func MRT_ALIGN(x: UInt16, a: UInt16): UInt16 {
    return ((x + a - 1) & !(a - 1))
}

// Common/TypeDef.h:79-80. UInt32 overload of the exact MRT_ALIGN macro expression.
@NoHeapAlloc
public func MRT_ALIGN(x: UInt32, a: UInt32): UInt32 {
    return ((x + a - 1) & !(a - 1))
}

// Common/TypeDef.h:79-80. UInt64 overload of the exact MRT_ALIGN macro expression.
@NoHeapAlloc
public func MRT_ALIGN(x: UInt64, a: UInt64): UInt64 {
    return ((x + a - 1) & !(a - 1))
}

// Common/TypeDef.h:79-80. UIntNative overload of the exact MRT_ALIGN macro expression.
@NoHeapAlloc
public func MRT_ALIGN(x: UIntNative, a: UIntNative): UIntNative {
    return ((x + a - 1) & !(a - 1))
}
