import rt.cstring.CString

main(): Int64 {
    var bytes: VArray<UInt8, $6> = [97u8, 32u8, 98u8, 32u8, 99u8, 0u8]
    let source = unsafe { CString(CPointer<UInt8>(inout bytes)) }
    if (source.Length() != 5) {
        return 1
    }
    println("CSTRING_CTOR PASS")
    println("CSTRING_LENGTH PASS")

    let sourceStr = source.Str()
    if (sourceStr.isNull() || unsafe { sourceStr.read(0) } != b'a' ||
        unsafe { sourceStr.read(4) } != b'c' || unsafe { sourceStr.read(5) } != 0u8) {
        return 2
    }
    println("CSTRING_STR PASS")

    let compact = source.RemoveBlankSpace()
    let compactStr = compact.Str()
    if (compact.Length() != 3 || unsafe { compactStr.read(0) } != b'a' ||
        unsafe { compactStr.read(1) } != b'b' || unsafe { compactStr.read(2) } != b'c' ||
        unsafe { compactStr.read(3) } != 0u8 || source.Length() != 5) {
        return 3
    }
    println("CSTRING_REMOVE_BLANK_SPACE PASS")

    let nullSource = unsafe { CString(CPointer<UInt8>()) }
    if (!nullSource.Str().isNull() || nullSource.Length() != 0) {
        return 4
    }
    println("CSTRING_NULL_CTOR PASS")
    println("CSTRING_PROBE PASS members=4 branches=nonempty,null,spaces")
    return 0
}
