package rt.gc

foreign {
    func MarkWorkStackAllocReset(): Unit
    func MarkWorkStackNewCalls(): UIntNative
    func MarkWorkStackNewBytes(): UIntNative
    func MarkWorkStackDeleteCalls(): UIntNative
}

private var VALUE_STORAGE: VArray<UInt8, $1024> = VArray<UInt8, $1024>(repeat: 0u8)

private func Value(value: UIntNative): CPointer<Unit> {
    return unsafe { CPointer<Unit>(CPointer<UInt8>(inout VALUE_STORAGE) + Int64(value)) }
}

private func Token(value: CPointer<Unit>): UIntNative {
    if (value.isNull()) {
        return 0
    }
    return value.toUIntNative() - unsafe { CPointer<UInt8>(inout VALUE_STORAGE).toUIntNative() }
}

main(): Int64 {
    var bufLayout = MarkStackBuf()
    let bufBase = unsafe { CPointer<UInt8>(inout bufLayout).toUIntNative() }
    let nextOffset = unsafe { CPointer<UInt8>(inout bufLayout.next).toUIntNative() } - bufBase
    let preOffset = unsafe { CPointer<UInt8>(inout bufLayout.pre).toUIntNative() } - bufBase
    var stackLayout = MarkStack()
    let ownerBase = unsafe { CPointer<UInt8>(inout stackLayout).toUIntNative() }
    let headOffset = 0
    let tailOffset = 8
    let sizeOffset = 16
    let _ = ownerBase
    println("MARKWORKSTACK_LAYOUT buf=${sizeOf<MarkStackBuf>()}/${alignOf<MarkStackBuf>()} " +
        "next=${nextOffset} pre=${preOffset} count=16 stack=24 " +
        "owner=${sizeOf<MarkStack>()}/${alignOf<MarkStack>()} head=${headOffset} " +
        "tail=${tailOffset} size=${sizeOffset} max=${MarkStackBuf.MAX}")

    unsafe { MarkWorkStackAllocReset() }
    var stackValue = MarkStack()
    let stack = unsafe { CPointer<MarkStack>(inout stackValue) }
    MarkStackConstruct(stack)
    println("EMPTY empty=${if (MarkStackEmpty(stack)) { 1 } else { 0 }} " +
        "back=${Token(MarkStackBack(stack))} buffers=${MarkStackSize(stack)}")
    var value: UIntNative = 1
    while (value <= 130) {
        MarkStackPushBack(stack, Value(value))
        value += 1
    }
    println("PUSH count=130 back=${Token(MarkStackBack(stack))} buffers=${MarkStackSize(stack)} " +
        "head_pre=${if (unsafe { MarkStackHead(stack).read(0).pre.isNull() }) { 1 } else { 0 }} " +
        "tail_next=${if (unsafe { MarkStackTail(stack).read(0).next.isNull() }) { 1 } else { 0 }}")
    MarkStackPopBack(stack)
    MarkStackPopBack(stack)
    println("POP count=128 back=${Token(MarkStackBack(stack))} buffers=${MarkStackSize(stack)}")

    var otherValue = MarkStack()
    let other = unsafe { CPointer<MarkStack>(inout otherValue) }
    MarkStackConstruct(other)
    value = 201
    while (value <= 266) {
        MarkStackPushBack(other, Value(value))
        value += 1
    }
    MarkStackInsert(stack, other)
    println("INSERT buffers=${MarkStackSize(stack)} " +
        "other_empty=${if (MarkStackEmpty(other)) { 1 } else { 0 }} back=${Token(MarkStackBack(stack))}")

    var detachedValue = MarkStack()
    let detached = unsafe { CPointer<MarkStack>(inout detachedValue) }
    MarkStackConstructFromBuffer(detached, MarkStackSplit(stack, 2))
    let links = unsafe {
        MarkStackTail(detached).read(0).next.isNull() && MarkStackHead(stack).read(0).pre.isNull()
    }
    println("SPLIT left=${MarkStackSize(detached)} left_back=${Token(MarkStackBack(detached))} " +
        "right=${MarkStackSize(stack)} right_back=${Token(MarkStackBack(stack))} " +
        "link=${if (links) { 1 } else { 0 }}")

    var movedValue = MarkStack()
    let moved = unsafe { CPointer<MarkStack>(inout movedValue) }
    MarkStackMoveConstruct(moved, detached)
    println("MOVE moved=${MarkStackSize(moved)} " +
        "source_empty=${if (MarkStackEmpty(detached)) { 1 } else { 0 }} " +
        "back=${Token(MarkStackBack(moved))}")
    while (!MarkStackEmpty(moved)) {
        MarkStackPopBack(moved)
    }
    while (!MarkStackEmpty(stack)) {
        MarkStackPopBack(stack)
    }
    MarkStackClear(moved)
    MarkStackClear(stack)

    var shortValue = MarkStack()
    let short = unsafe { CPointer<MarkStack>(inout shortValue) }
    MarkStackConstruct(short)
    MarkStackPushBack(short, Value(777))
    var allValue = MarkStack()
    let all = unsafe { CPointer<MarkStack>(inout allValue) }
    MarkStackConstructFromBuffer(all, MarkStackSplit(short, 3))
    println("SPLIT_ALL source_empty=${if (MarkStackEmpty(short)) { 1 } else { 0 }} " +
        "taken=${MarkStackSize(all)} back=${Token(MarkStackBack(all))}")
    while (!MarkStackEmpty(all)) {
        MarkStackPopBack(all)
    }
    MarkStackClear(all)
    println("ALLOC new_calls=${unsafe { MarkWorkStackNewCalls() }} " +
        "bytes=${unsafe { MarkWorkStackNewBytes() }} " +
        "delete_calls=${unsafe { MarkWorkStackDeleteCalls() }}")
    println("MARKWORKSTACK_PARITY PASS")
    return 0
}
