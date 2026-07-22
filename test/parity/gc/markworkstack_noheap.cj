package rt.gc

@NoHeapAlloc
public func MarkWorkStackBufferNoHeap(buf: CPointer<MarkStackBuf>, value: CPointer<Unit>): Unit {
    let _ = MarkStackBufEmpty(buf)
    let _ = MarkStackBufFull(buf)
    MarkStackBufPushBack(buf, value)
    let _ = MarkStackBufBack(buf)
    MarkStackBufPopBack(buf)
}

@NoHeapAlloc
public func MarkWorkStackLifecycleNoHeap(stack: CPointer<MarkStack>,
    source: CPointer<MarkStack>, detached: CPointer<MarkStack>): Unit {
    MarkStackConstruct(stack)
    MarkStackConstruct(source)
    MarkStackMoveConstruct(detached, source)
    MarkStackDestroy(detached)
    MarkStackClear(stack)
    MarkStackClean(source)
}

@NoHeapAlloc
public func MarkWorkStackOperationsNoHeap(stack: CPointer<MarkStack>,
    other: CPointer<MarkStack>, detached: CPointer<MarkStack>, value: CPointer<Unit>,
    splitNum: UIntNative): Unit {
    let _ = MarkStackHead(stack)
    let _ = MarkStackTail(stack)
    let _ = MarkStackSize(stack)
    let _ = MarkStackEmpty(stack)
    MarkStackPushBack(stack, value)
    let _ = MarkStackBack(stack)
    MarkStackPopBack(stack)
    MarkStackInsert(stack, other)
    MarkStackConstructFromBuffer(detached, MarkStackSplit(stack, splitNum))
}
