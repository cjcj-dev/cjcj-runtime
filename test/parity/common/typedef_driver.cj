import rt.common.*

// Test-only ABI identities force the imported live TypeDef aliases into C signatures.
@C
@NoHeapAlloc
func TypeDefProbeMAddress(value: MAddress): MAddress { return value }

@C
@NoHeapAlloc
func TypeDefProbeMSize(value: MSize): MSize { return value }

@C
@NoHeapAlloc
func TypeDefProbeMOffset(value: MOffset): MOffset { return value }

@C
@NoHeapAlloc
func TypeDefProbeMIndex(value: MIndex): MIndex { return value }

@C
@NoHeapAlloc
func TypeDefProbeObjRef(value: ObjRef): ObjRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeArrayRef(value: ArrayRef): ArrayRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeFuncRef(value: FuncRef): FuncRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeFuncDescRef(value: FuncDescRef): FuncDescRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeStringRef(value: StringRef): StringRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeExceptionRef(value: ExceptionRef): ExceptionRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeMethodInfoRef(value: MethodInfoRef): MethodInfoRef { return value }

@C
@NoHeapAlloc
func TypeDefProbePackageInfoRef(value: PackageInfoRef): PackageInfoRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeParameterInfoRef(value: ParameterInfoRef): ParameterInfoRef { return value }

@C
@NoHeapAlloc
func TypeDefProbeFuncPtr(value: FuncPtr): FuncPtr { return value }

@C
@NoHeapAlloc
func TypeDefProbeAllocType(value: AllocType): AllocType { return value }

// Test-only executable root for Common/TypeDef.h:65's callable alias.
@C
@NoHeapAlloc
func TypeDefProbeInvoke(callback: FuncPtr, pointer: CPointer<Unit>): Unit {
    unsafe { callback(pointer) }
}

// Test-only executable roots for all live Common/TypeDef.h:79-80 overloads.
@C
@NoHeapAlloc
func TypeDefAlign16Root(x: UInt16, a: UInt16): UInt16 { return MRT_ALIGN(x, a) }

@C
@NoHeapAlloc
func TypeDefAlign32Root(x: UInt32, a: UInt32): UInt32 { return MRT_ALIGN(x, a) }

@C
@NoHeapAlloc
func TypeDefAlign64Root(x: UInt64, a: UInt64): UInt64 { return MRT_ALIGN(x, a) }

@C
@NoHeapAlloc
func TypeDefAlignNativeRoot(x: UIntNative, a: UIntNative): UIntNative { return MRT_ALIGN(x, a) }

@C
@NoHeapAlloc
func TypeDefCallback(pointer: CPointer<Unit>): Unit {
    unsafe {
        let value = CPointer<UInt64>(pointer).read(0)
        CPointer<UInt64>(pointer).write(0, value + 1u64)
    }
}

func NextAlignValue(value: UInt64): UInt64 {
    var next = value ^ (value << 13u64)
    next = next ^ (next >> 7u64)
    return next ^ (next << 17u64)
}

func PrintLayouts(): Unit {
    println("LAYOUT MAddress ${sizeOf<MAddress>()} ${alignOf<MAddress>()}")
    println("LAYOUT MSize ${sizeOf<MSize>()} ${alignOf<MSize>()}")
    println("LAYOUT MOffset ${sizeOf<MOffset>()} ${alignOf<MOffset>()}")
    println("LAYOUT MIndex ${sizeOf<MIndex>()} ${alignOf<MIndex>()}")
    println("LAYOUT ObjRef ${sizeOf<ObjRef>()} ${alignOf<ObjRef>()}")
    println("LAYOUT ArrayRef ${sizeOf<ArrayRef>()} ${alignOf<ArrayRef>()}")
    println("LAYOUT FuncRef ${sizeOf<FuncRef>()} ${alignOf<FuncRef>()}")
    println("LAYOUT FuncDescRef ${sizeOf<FuncDescRef>()} ${alignOf<FuncDescRef>()}")
    println("LAYOUT StringRef ${sizeOf<StringRef>()} ${alignOf<StringRef>()}")
    println("LAYOUT ExceptionRef ${sizeOf<ExceptionRef>()} ${alignOf<ExceptionRef>()}")
    println("LAYOUT MethodInfoRef ${sizeOf<MethodInfoRef>()} ${alignOf<MethodInfoRef>()}")
    println("LAYOUT PackageInfoRef ${sizeOf<PackageInfoRef>()} ${alignOf<PackageInfoRef>()}")
    println("LAYOUT ParameterInfoRef ${sizeOf<ParameterInfoRef>()} ${alignOf<ParameterInfoRef>()}")
    println("LAYOUT FuncPtr ${sizeOf<FuncPtr>()} ${alignOf<FuncPtr>()}")
    println("LAYOUT AllocType ${sizeOf<AllocType>()} ${alignOf<AllocType>()}")
}

func PrintVocabulary(): Unit {
    let address = unsafe { TypeDefProbeMAddress(NULL_ADDRESS) }
    let size = unsafe { TypeDefProbeMSize(4294967295u32) }
    let offset = unsafe { TypeDefProbeMOffset(4294967295u32) }
    let index = unsafe { TypeDefProbeMIndex(MAX_ARRAY_SIZE) }
    println("CONSTANT NULL_ADDRESS ${address}")
    println("CONSTANT GENERIC_PAYLOAD_SIZE ${GENERIC_PAYLOAD_SIZE}")
    println("CONSTANT MAX_ARRAY_SIZE ${index}")
    println("SCALAR MSize ${size}")
    println("SCALAR MOffset ${offset}")
    println("ALLOC ${unsafe { TypeDefProbeAllocType(MOVEABLE_OBJECT) }} " +
        "${unsafe { TypeDefProbeAllocType(PINNED_OBJECT) }} " +
        "${unsafe { TypeDefProbeAllocType(RAW_POINTER_OBJECT) }}")

    let nullObj = unsafe { TypeDefProbeObjRef(CPointer<Unit>()) }
    let nullArray = unsafe { TypeDefProbeArrayRef(CPointer<Unit>()) }
    let nullFunction = unsafe { TypeDefProbeFuncRef(CPointer<Unit>()) }
    let nullDescriptor = unsafe { TypeDefProbeFuncDescRef(CPointer<Unit>()) }
    let nullString = unsafe { TypeDefProbeStringRef(CPointer<Unit>()) }
    let nullException = unsafe { TypeDefProbeExceptionRef(CPointer<Unit>()) }
    let nullMethod = unsafe { TypeDefProbeMethodInfoRef(CPointer<Unit>()) }
    let nullPackageInfo = unsafe { TypeDefProbePackageInfoRef(CPointer<Unit>()) }
    let nullParameter = unsafe { TypeDefProbeParameterInfoRef(CPointer<Unit>()) }
    let obj = unsafe { TypeDefProbeObjRef(CPointer<Unit>(CPointer<UInt8>() + 4096)) }
    let array = unsafe { TypeDefProbeArrayRef(CPointer<Unit>(CPointer<UInt8>() + 4352)) }
    let function = unsafe { TypeDefProbeFuncRef(CPointer<Unit>(CPointer<UInt8>() + 4608)) }
    let descriptor = unsafe { TypeDefProbeFuncDescRef(CPointer<Unit>(CPointer<UInt8>() + 4864)) }
    let string = unsafe { TypeDefProbeStringRef(CPointer<Unit>(CPointer<UInt8>() + 5120)) }
    let exception = unsafe { TypeDefProbeExceptionRef(CPointer<Unit>(CPointer<UInt8>() + 5376)) }
    let method = unsafe { TypeDefProbeMethodInfoRef(CPointer<Unit>(CPointer<UInt8>() + 5632)) }
    let packageInfo = unsafe { TypeDefProbePackageInfoRef(CPointer<Unit>(CPointer<UInt8>() + 5888)) }
    let parameter = unsafe { TypeDefProbeParameterInfoRef(CPointer<Unit>(CPointer<UInt8>() + 6144)) }
    unsafe {
        println("POINTER ObjRef NULL ${nullObj.toUIntNative()}")
        println("POINTER ArrayRef NULL ${nullArray.toUIntNative()}")
        println("POINTER FuncRef NULL ${nullFunction.toUIntNative()}")
        println("POINTER FuncDescRef NULL ${nullDescriptor.toUIntNative()}")
        println("POINTER StringRef NULL ${nullString.toUIntNative()}")
        println("POINTER ExceptionRef NULL ${nullException.toUIntNative()}")
        println("POINTER MethodInfoRef NULL ${nullMethod.toUIntNative()}")
        println("POINTER PackageInfoRef NULL ${nullPackageInfo.toUIntNative()}")
        println("POINTER ParameterInfoRef NULL ${nullParameter.toUIntNative()}")
        println("POINTER ObjRef NONNULL ${obj.toUIntNative()}")
        println("POINTER ArrayRef NONNULL ${array.toUIntNative()}")
        println("POINTER FuncRef NONNULL ${function.toUIntNative()}")
        println("POINTER FuncDescRef NONNULL ${descriptor.toUIntNative()}")
        println("POINTER StringRef NONNULL ${string.toUIntNative()}")
        println("POINTER ExceptionRef NONNULL ${exception.toUIntNative()}")
        println("POINTER MethodInfoRef NONNULL ${method.toUIntNative()}")
        println("POINTER PackageInfoRef NONNULL ${packageInfo.toUIntNative()}")
        println("POINTER ParameterInfoRef NONNULL ${parameter.toUIntNative()}")
    }
}

func RunCallback(): Unit {
    var storage = 0u64
    let callback: FuncPtr = TypeDefCallback
    let liveCallback = unsafe { TypeDefProbeFuncPtr(callback) }
    var calls = 0
    while (calls < 4096) {
        unsafe { TypeDefProbeInvoke(liveCallback, CPointer<Unit>(CPointer<UInt64>(inout storage))) }
        calls++
    }
    println("FUNCPTR callbacks=${calls} indirect_calls=${calls} value=${storage} null=0 nonnull=1")
}

func RunAlignParity(): Unit {
    var state = 0x6a09e667f3bcc909u64
    var operation = 0
    while (operation < 100000) {
        state = NextAlignValue(state)
        let alignBits = state
        state = NextAlignValue(state)
        let valueBits = state
        let edge = operation % 16
        let width = operation % 4
        if (width == 0) {
            let shift = alignBits % 16u64
            let alignment = 1u16 << shift
            var value = UInt16(valueBits & 65535u64)
            if (edge == 0) { value = 65535u16 }
            else if (edge == 1) { value = 65535u16 - alignment + 2u16 }
            else if (edge == 2) { value = 0u16 }
            else if (edge == 3) { value = alignment - 1u16 }
            else if (edge == 4) { value = 65535u16 - alignment + 1u16 }
            else if (edge == 5) { value = alignment }
            let result = unsafe { TypeDefAlign16Root(value, alignment) }
            println("ALIGN ${operation} 16 ${value} ${alignment} ${result}")
        } else if (width == 1) {
            let shift = alignBits % 32u64
            let alignment = 1u32 << shift
            var value = UInt32(valueBits & 4294967295u64)
            if (edge == 0) { value = 4294967295u32 }
            else if (edge == 1) { value = 4294967295u32 - alignment + 2u32 }
            else if (edge == 2) { value = 0u32 }
            else if (edge == 3) { value = alignment - 1u32 }
            else if (edge == 4) { value = 4294967295u32 - alignment + 1u32 }
            else if (edge == 5) { value = alignment }
            let result = unsafe { TypeDefAlign32Root(value, alignment) }
            println("ALIGN ${operation} 32 ${value} ${alignment} ${result}")
        } else if (width == 2) {
            let shift = alignBits % 64u64
            let alignment = 1u64 << shift
            var value = valueBits
            if (edge == 0) { value = 18446744073709551615u64 }
            else if (edge == 1) { value = 18446744073709551615u64 - alignment + 2u64 }
            else if (edge == 2) { value = 0u64 }
            else if (edge == 3) { value = alignment - 1u64 }
            else if (edge == 4) { value = 18446744073709551615u64 - alignment + 1u64 }
            else if (edge == 5) { value = alignment }
            let result = unsafe { TypeDefAlign64Root(value, alignment) }
            println("ALIGN ${operation} 64 ${value} ${alignment} ${result}")
        } else {
            let shift = alignBits % 64u64
            let alignment = UIntNative(1u64 << shift)
            var value = UIntNative(valueBits)
            if (edge == 0) { value = UIntNative(18446744073709551615u64) }
            else if (edge == 1) { value = UIntNative(18446744073709551615u64) - alignment + UIntNative(2) }
            else if (edge == 2) { value = UIntNative(0) }
            else if (edge == 3) { value = alignment - UIntNative(1) }
            else if (edge == 4) { value = UIntNative(18446744073709551615u64) - alignment + UIntNative(1) }
            else if (edge == 5) { value = alignment }
            let result = unsafe { TypeDefAlignNativeRoot(value, alignment) }
            println("ALIGN ${operation} N ${value} ${alignment} ${result}")
        }
        operation++
    }
}

main(): Int64 {
    PrintLayouts()
    PrintVocabulary()
    RunCallback()
    RunAlignParity()
    return 0
}
