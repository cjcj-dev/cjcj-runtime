package rt.objectmodel

foreign {
    func CJRT_TestInitSizeClass(object: CPointer<Unit>, typeInfo: CPointer<Unit>, instanceSize: UInt32): Unit
    func CJRT_TestInitSizeArray(object: CPointer<Unit>, arrayTypeInfo: CPointer<Unit>,
        componentTypeInfo: CPointer<Unit>, componentKind: Int8, componentSize: UInt32, length: UInt64): Unit
    func CJRT_TestBaseObjectGetSize(object: CPointer<Unit>): UIntNative
}

func CheckClass(instanceSize: UInt32): Unit {
    var objectStorage = VArray<UInt64, $32>(repeat: 0)
    var typeInfoStorage = VArray<UInt64, $16>(repeat: 0)
    let object = unsafe { CPointer<Unit>(CPointer<UInt64>(inout objectStorage)) }
    unsafe { CJRT_TestInitSizeClass(object, CPointer<Unit>(CPointer<UInt64>(inout typeInfoStorage)), instanceSize) }
    let expected = unsafe { CJRT_TestBaseObjectGetSize(object) }
    let actual = BaseObjectGetSize(CPointer<BaseObject>(object))
    println("BASEOBJECT_SIZE kind=class instance=${instanceSize} cpp=${expected} cj=${actual}")
    if (actual != expected) { unsafe { abort() } }
}

func CheckArray(kind: Int8, componentSize: UInt32, length: UInt64): Unit {
    var objectStorage = VArray<UInt64, $64>(repeat: 0)
    var arrayTypeInfoStorage = VArray<UInt64, $16>(repeat: 0)
    var componentTypeInfoStorage = VArray<UInt64, $16>(repeat: 0)
    let object = unsafe { CPointer<Unit>(CPointer<UInt64>(inout objectStorage)) }
    unsafe { CJRT_TestInitSizeArray(object,
        CPointer<Unit>(CPointer<UInt64>(inout arrayTypeInfoStorage)),
        CPointer<Unit>(CPointer<UInt64>(inout componentTypeInfoStorage)), kind, componentSize, length) }
    let expected = unsafe { CJRT_TestBaseObjectGetSize(object) }
    let actual = BaseObjectGetSize(CPointer<BaseObject>(object))
    println("BASEOBJECT_SIZE kind=array component=${kind}/${componentSize} length=${length} cpp=${expected} cj=${actual}")
    if (actual != expected) { unsafe { abort() } }
}

main(): Int64 {
    CheckClass(0u32)
    CheckClass(1u32)
    CheckClass(16u32)
    CheckClass(17u32)
    CheckArray(-128i8, 8u32, 0u64)
    CheckArray(-128i8, 8u32, 3u64)
    CheckArray(22i8, 3u32, 3u64)
    CheckArray(22i8, 24u32, 2u64)
    return 0
}
