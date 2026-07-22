package rt.objectmodel

foreign {
    func CJRT_TestInitTraversalClass(object: CPointer<Unit>, typeInfo: CPointer<Unit>, bitmap: UIntNative): Unit
    func CJRT_TestInitTraversalArray(object: CPointer<Unit>, arrayTypeInfo: CPointer<Unit>,
        componentTypeInfo: CPointer<Unit>, componentKind: Int8, bitmap: UIntNative, length: UInt64,
        componentSize: UInt32): Unit
}

@C
struct VisitRecord {
    var base: UIntNative
    var count: UInt32
    var offsets: VArray<UIntNative, $16>

    init(base: UIntNative) {
        this.base = base
        count = 0
        offsets = VArray<UIntNative, $16>(repeat: 0)
    }
}

let RECORD_VISITOR: GCTibVisitor = { field: CPointer<RefField>, context: CPointer<Unit> =>
    let record = CPointer<VisitRecord>(context)
    unsafe {
        let index = record.read().count
        CPointer<UIntNative>(CPointer<UInt8>(record) + 16).write(Int64(index), field.toUIntNative() - record.read().base)
        CPointer<UInt32>(CPointer<UInt8>(record) + 8).write(0, index + 1)
    }
}

func PrintRecord(name: String, record: CPointer<VisitRecord>): Unit {
    var text = "${name} count=${unsafe { record.read().count }} offsets="
    var index = 0u32
    while (index < unsafe { record.read().count }) {
        if (index != 0) { text += "," }
        text += "${unsafe { CPointer<UIntNative>(CPointer<UInt8>(record) + 16).read(Int64(index)) }}"
        index++
    }
    println(text)
}

main(): Int64 {
    var fields = VArray<UIntNative, $24>(repeat: 0)
    let base = unsafe { CPointer<UIntNative>(inout fields).toUIntNative() }

    var short = GCTib(tag: UIntNative(0x8000000000000125u64))
    var record = VisitRecord(base)
    GCTibForEachBitmapWord(unsafe { CPointer<GCTib>(inout short) }, base, RECORD_VISITOR,
        CPointer<Unit>(unsafe { CPointer<VisitRecord>(inout record) }))
    println("LAYOUT short=${sizeOf<ShortGCTib>()}/${alignOf<ShortGCTib>()} " +
        "std=${sizeOf<StdGCTib>()}/${alignOf<StdGCTib>()} gctib=${sizeOf<GCTib>()}/${alignOf<GCTib>()}")
    PrintRecord("SHORT", unsafe { CPointer<VisitRecord>(inout record) })

    record = VisitRecord(base)
    GCTibForEachBitmapWordInRange(unsafe { CPointer<GCTib>(inout short) }, base, RECORD_VISITOR,
        CPointer<Unit>(unsafe { CPointer<VisitRecord>(inout record) }), base + 9, base + 70)
    PrintRecord("SHORT_RANGE", unsafe { CPointer<VisitRecord>(inout record) })

    var standard = VArray<UInt8, $8>(repeat: 0)
    let standardPtr = unsafe { CPointer<StdGCTib>(CPointer<UInt8>(inout standard)) }
    unsafe {
        CPointer<UInt32>(standardPtr).write(0, 3u32)
        (CPointer<UInt8>(standardPtr) + 4).write(0, 0x81u8)
        (CPointer<UInt8>(standardPtr) + 5).write(0, 0x12u8)
        (CPointer<UInt8>(standardPtr) + 6).write(0, 0x40u8)
    }
    var long = GCTib(tag: standardPtr.toUIntNative())
    record = VisitRecord(base)
    GCTibForEachBitmapWord(unsafe { CPointer<GCTib>(inout long) }, base, RECORD_VISITOR,
        CPointer<Unit>(unsafe { CPointer<VisitRecord>(inout record) }))
    PrintRecord("STD", unsafe { CPointer<VisitRecord>(inout record) })

    record = VisitRecord(base)
    GCTibForEachBitmapWordInRange(unsafe { CPointer<GCTib>(inout long) }, base, RECORD_VISITOR,
        CPointer<Unit>(unsafe { CPointer<VisitRecord>(inout record) }), base + 65, base + 180)
    PrintRecord("STD_RANGE", unsafe { CPointer<VisitRecord>(inout record) })

    var objectStorage = VArray<UInt64, $12>(repeat: 0)
    var classTypeInfo = VArray<UInt8, $96>(repeat: 0)
    let object = unsafe { CPointer<BaseObject>(CPointer<UInt64>(inout objectStorage)) }
    unsafe { CJRT_TestInitTraversalClass(CPointer<Unit>(object), CPointer<Unit>(CPointer<UInt8>(inout classTypeInfo)),
        UIntNative(0x8000000000000125u64)) }
    let objectBase = object.toUIntNative()
    record = VisitRecord(objectBase)
    BaseObjectForEachRefField(object, RECORD_VISITOR,
        CPointer<Unit>(unsafe { CPointer<VisitRecord>(inout record) }))
    PrintRecord("OBJECT", unsafe { CPointer<VisitRecord>(inout record) })

    var structArrayStorage = VArray<UInt64, $12>(repeat: 0)
    var structArrayTypeInfo = VArray<UInt8, $96>(repeat: 0)
    var structComponentTypeInfo = VArray<UInt8, $96>(repeat: 0)
    let structArray = unsafe { CPointer<MArray>(CPointer<UInt64>(inout structArrayStorage)) }
    unsafe { CJRT_TestInitTraversalArray(CPointer<Unit>(structArray),
        CPointer<Unit>(CPointer<UInt8>(inout structArrayTypeInfo)),
        CPointer<Unit>(CPointer<UInt8>(inout structComponentTypeInfo)), 22i8,
        UIntNative(0x8000000000000005u64), 2u64, 24u32) }
    let structBase = structArray.toUIntNative()
    record = VisitRecord(structBase)
    BaseObjectForEachRefField(CPointer<BaseObject>(structArray), RECORD_VISITOR,
        CPointer<Unit>(unsafe { CPointer<VisitRecord>(inout record) }))
    PrintRecord("STRUCT_ARRAY", unsafe { CPointer<VisitRecord>(inout record) })

    var refArrayStorage = VArray<UInt64, $8>(repeat: 0)
    var refArrayTypeInfo = VArray<UInt8, $96>(repeat: 0)
    var refComponentTypeInfo = VArray<UInt8, $96>(repeat: 0)
    let refArray = unsafe { CPointer<MArray>(CPointer<UInt64>(inout refArrayStorage)) }
    unsafe { CJRT_TestInitTraversalArray(CPointer<Unit>(refArray),
        CPointer<Unit>(CPointer<UInt8>(inout refArrayTypeInfo)),
        CPointer<Unit>(CPointer<UInt8>(inout refComponentTypeInfo)), -128i8, 0, 3u64, 8u32) }
    let refBase = refArray.toUIntNative()
    record = VisitRecord(refBase)
    MArrayForEachRefFieldInRange(refArray, RECORD_VISITOR,
        CPointer<Unit>(unsafe { CPointer<VisitRecord>(inout record) }), refBase + 16, UInt64(refBase + 40))
    PrintRecord("REF_ARRAY_RANGE", unsafe { CPointer<VisitRecord>(inout record) })
    return 0
}
