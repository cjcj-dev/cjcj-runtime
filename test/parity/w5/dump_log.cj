foreign func MRT_DumpLog(message: CPointer<UInt8>): Unit

main(): Int64 {
    var message: VArray<UInt8, $16> = [
        87u8, 53u8, 95u8, 67u8, 70u8, 85u8, 78u8, 67u8,
        95u8, 69u8, 88u8, 80u8, 79u8, 82u8, 84u8, 0u8
    ]
    unsafe { MRT_DumpLog(CPointer<UInt8>(inout message)) }
    return 0
}
