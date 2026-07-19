import rt.base.*

foreign { func write(fd: Int32, data: CPointer<UInt8>, size: UIntNative): IntNative }

private var postUnlockWriteMarker: VArray<UInt8, $25> = [
    80u8, 79u8, 83u8, 84u8, 95u8, 85u8, 78u8, 76u8, 79u8, 67u8, 75u8, 95u8,
    87u8, 82u8, 73u8, 84u8, 69u8, 95u8, 82u8, 69u8, 65u8, 67u8, 72u8, 69u8, 68u8
]

main(): Int64 {
    var lock = RwLock()
    lock.UnlockWrite()
    unsafe { let _ = write(1, CPointer<UInt8>(inout postUnlockWriteMarker), 25) }
    return 99
}
