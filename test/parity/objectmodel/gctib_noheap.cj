package rt.objectmodel

@NoHeapAlloc
public func GCTibNoHeapRoot(gctib: CPointer<GCTib>, contentAddress: UIntNative,
    visitor: GCTibVisitor, context: CPointer<Unit>): Unit {
    GCTibForEachBitmapWord(gctib, contentAddress, visitor, context)
    GCTibForEachBitmapWordInRange(gctib, contentAddress, visitor, context,
        contentAddress + sizeOf<RefField>(), contentAddress + sizeOf<RefField>() * 8)
}
