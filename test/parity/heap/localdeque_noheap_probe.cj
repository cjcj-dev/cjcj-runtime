import rt.heap.allocator.*

@NoHeapAlloc
public func LocalDequeNoHeapRoot(singleUseDeque: SingleUseDeque, first: CPointer<Unit>,
    second: CPointer<Unit>): UIntNative {
    var stack = LocalDeque(singleUseDeque)
    var queue = LocalDeque(singleUseDeque)
    var spill = LocalDeque(singleUseDeque)
    var result: UIntNative = 0

    if (stack.Empty()) {
        result += 1
    }
    stack.Push(first)
    result ^= stack.Top().toUIntNative()
    stack.Pop()

    queue.Push(second)
    result ^= queue.Front().toUIntNative()
    queue.PopFront()

    var index = 0
    while (index < 513) {
        spill.Push(first)
        index += 1
    }
    result ^= spill.Top().toUIntNative()
    result ^= spill.Front().toUIntNative()
    spill.Pop()
    spill.PopFront()
    return result
}
