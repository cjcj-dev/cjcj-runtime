package rt.gc

main(): Int64 {
    var storage: VArray<UInt8, $2> = [0u8, 0u8]
    var value = MarkStack()
    let stack = unsafe { CPointer<MarkStack>(inout value) }
    MarkStackConstruct(stack)
    MarkStackPushBack(stack, unsafe { CPointer<Unit>(CPointer<UInt8>(inout storage) + 1) })
    MarkStackClear(stack)
    return 0
}
