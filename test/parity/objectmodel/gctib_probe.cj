package rt.objectmodel

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
    return 0
}
