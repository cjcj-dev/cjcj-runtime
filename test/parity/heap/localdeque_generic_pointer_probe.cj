main(): Int64 {
    var value = 17u32
    let before = unsafe {
        let pointer = CPointer<UInt32>(inout value)
        pointer.write(0, 29u32)
        pointer.read(0)
    }
    if (before != 29u32 || value != 29u32) {
        return 1
    }
    println("GENERIC_CPOINTER_UNSAFE_COMPILE PASS value=${before}")
    return 0
}
