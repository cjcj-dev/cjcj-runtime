package rt.objectmodel

// ObjectModel/MClass.h:229-382.  GCTib is a one-word tagged union.  A
// non-capturing CFunc plus an explicit context carries the same visitor state
// as the C++ RefFieldVisitor without creating a managed closure.
public type GCTibVisitor = CFunc<(CPointer<RefField>, CPointer<Unit>) -> Unit>

@C
public struct ShortGCTib {
    public var bitmap: UIntNative

    public init(bitmap!: UIntNative = 0) { this.bitmap = bitmap }
}

@C
public struct StdGCTib {
    public var nBitmapWords: UInt32

    public init(nBitmapWords!: UInt32 = 0) { this.nBitmapWords = nBitmapWords }
}

@C
public struct GCTib {
    public var tag: UIntNative

    public init(tag!: UIntNative = 0) { this.tag = tag }
}

@When[arch == "arm"]
private func GCTibSignBit(): UIntNative { return UIntNative(0x80000000u32) }
@When[arch != "arm"]
private func GCTibSignBit(): UIntNative { return UIntNative(0x8000000000000000u64) }

@When[arch == "arm"]
private func GCTibAlignRangeStart(address: UIntNative): UIntNative {
    return address.wrappingAdd(3) & (UIntNative.Max ^ UIntNative(3))
}
@When[arch != "arm"]
private func GCTibAlignRangeStart(address: UIntNative): UIntNative {
    return address.wrappingAdd(7) & (UIntNative.Max ^ UIntNative(7))
}

private func GCTibPointer(address: UIntNative): CPointer<UInt8> {
    return CPointer<UInt8>(RefFieldPointerFromAddress(address))
}

private func GCTibVisit(visitor: GCTibVisitor, fieldAddress: UIntNative, context: CPointer<Unit>): Unit {
    unsafe { visitor(CPointer<RefField>(GCTibPointer(fieldAddress)), context) }
}

public func ShortGCTibForEachBitmapWord(short: CPointer<ShortGCTib>, fieldAddress: UIntNative,
    visitor: GCTibVisitor, context: CPointer<Unit>): Unit {
    var gcInfo = unsafe { short.read().bitmap } & (UIntNative.Max ^ GCTibSignBit())
    var current = fieldAddress
    while (gcInfo != 0) {
        if ((gcInfo & 1) != 0) { GCTibVisit(visitor, current, context) }
        gcInfo >>= 1
        current = current.wrappingAdd(sizeOf<RefField>())
    }
}

public func ShortGCTibForEachBitmapWordInRange(short: CPointer<ShortGCTib>, baseAddress: UIntNative,
    visitor: GCTibVisitor, context: CPointer<Unit>, rangeStart: UIntNative, rangeEnd: UIntNative): Unit {
    var gcInfo = unsafe { short.read().bitmap } & (UIntNative.Max ^ GCTibSignBit())
    let startPosition = (rangeStart - baseAddress) / sizeOf<RefField>()
    gcInfo >>= UInt32(startPosition)
    var current = rangeStart
    while (gcInfo != 0) {
        if (current >= rangeEnd) { return }
        if ((gcInfo & 1) != 0) { GCTibVisit(visitor, current, context) }
        gcInfo >>= 1
        current = current.wrappingAdd(sizeOf<RefField>())
    }
}

private func StdGCTibBitmapWords(standard: CPointer<StdGCTib>): CPointer<UInt8> {
    return unsafe { CPointer<UInt8>(standard) + 4 }
}

public func StdGCTibVisitRefField(bitmapWord: CPointer<UInt8>, fieldAddress: CPointer<UIntNative>,
    visitor: GCTibVisitor, context: CPointer<Unit>): Unit {
    var bits = unsafe { bitmapWord.read() }
    var address = unsafe { fieldAddress.read() }
    if ((bits & 1) != 0) { GCTibVisit(visitor, address, context) }
    bits >>= 1
    address = address.wrappingAdd(sizeOf<RefField>())
    unsafe {
        bitmapWord.write(0, bits)
        fieldAddress.write(0, address)
    }
}

public func StdGCTibVisitAllField(bitmapWord: CPointer<UInt8>, fieldAddress: CPointer<UIntNative>,
    visitor: GCTibVisitor, context: CPointer<Unit>): Unit {
    var bits = unsafe { bitmapWord.read() }
    var address = unsafe { fieldAddress.read() }
    GCTibVisit(visitor, address, context)
    bits >>= 1
    address = address.wrappingAdd(sizeOf<RefField>())
    unsafe {
        bitmapWord.write(0, bits)
        fieldAddress.write(0, address)
    }
}

public func StdGCTibForEachBitmapWord(standard: CPointer<StdGCTib>, contentAddress: UIntNative,
    visitor: GCTibVisitor, context: CPointer<Unit>): Unit {
    let words = StdGCTibBitmapWords(standard)
    let count = unsafe { standard.read().nBitmapWords }
    var index = 0u32
    var baseAddress = contentAddress
    while (index < count) {
        var bitmapWord = unsafe { (words + Int64(index)).read() }
        var fieldAddress = baseAddress
        while (bitmapWord != 0) {
            StdGCTibVisitRefField(CPointer<UInt8>(inout bitmapWord), CPointer<UIntNative>(inout fieldAddress),
                visitor, context)
        }
        baseAddress = baseAddress.wrappingAdd(sizeOf<RefField>() * 8)
        index++
    }
}

public func StdGCTibForEachBitmapWordInRange(standard: CPointer<StdGCTib>, contentAddress: UIntNative,
    visitor: GCTibVisitor, context: CPointer<Unit>, rangeStart: UIntNative, rangeEnd: UIntNative): Unit {
    let words = StdGCTibBitmapWords(standard)
    let count = unsafe { standard.read().nBitmapWords }
    let mapWordSize = sizeOf<RefField>() * 8
    let startIndex = UInt32((rangeStart - contentAddress) / mapWordSize)
    var index = startIndex
    var baseAddress = UIntNative(startIndex) * mapWordSize + contentAddress
    while (index < count) {
        var bitmapWord = unsafe { (words + Int64(index)).read() }
        var fieldAddress = baseAddress
        if (index == startIndex && bitmapWord != 0) {
            bitmapWord >>= UInt32((rangeStart - baseAddress) / sizeOf<RefField>())
            fieldAddress = rangeStart
        }
        while (bitmapWord != 0) {
            if (fieldAddress >= rangeEnd) { return }
            StdGCTibVisitRefField(CPointer<UInt8>(inout bitmapWord), CPointer<UIntNative>(inout fieldAddress),
                visitor, context)
        }
        baseAddress = baseAddress.wrappingAdd(mapWordSize)
        index++
    }
}

@When[arch == "arm"]
public func GCTibIsGCTibWord(gctib: CPointer<GCTib>): Bool { return false }
@When[arch != "arm"]
public func GCTibIsGCTibWord(gctib: CPointer<GCTib>): Bool {
    return (unsafe { gctib.read().tag } & GCTibSignBit()) != 0
}

public func GCTibForEachBitmapWord(gctib: CPointer<GCTib>, contentAddress: UIntNative,
    visitor: GCTibVisitor, context: CPointer<Unit>): Unit {
    if (GCTibIsGCTibWord(gctib)) {
        ShortGCTibForEachBitmapWord(CPointer<ShortGCTib>(gctib), contentAddress, visitor, context)
    } else {
        let standard = CPointer<StdGCTib>(GCTibPointer(unsafe { gctib.read().tag }))
        StdGCTibForEachBitmapWord(standard, contentAddress, visitor, context)
    }
}

public func GCTibForEachBitmapWordInRange(gctib: CPointer<GCTib>, contentAddress: UIntNative,
    visitor: GCTibVisitor, context: CPointer<Unit>, start: UIntNative, rangeEnd: UIntNative): Unit {
    let rangeStart = GCTibAlignRangeStart(start)
    if (rangeStart >= rangeEnd) { return }
    if (GCTibIsGCTibWord(gctib)) {
        ShortGCTibForEachBitmapWordInRange(CPointer<ShortGCTib>(gctib), contentAddress, visitor, context,
            rangeStart, rangeEnd)
    } else {
        let standard = CPointer<StdGCTib>(GCTibPointer(unsafe { gctib.read().tag }))
        StdGCTibForEachBitmapWordInRange(standard, contentAddress, visitor, context, rangeStart, rangeEnd)
    }
}
