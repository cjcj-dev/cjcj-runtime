foreign func _ZN12MapleRuntime7LogFile8SetFlagsEv(): Unit
foreign func _ZN12MapleRuntime7LogFile13CloseLogFilesEv(): Unit
foreign func _ZN12MapleRuntime7LogFile14SetFlagWithEnvEPKcNS_7LogTypeE(
    env: CPointer<UInt8>, logType: Int32
): Unit

main(): Int64 {
    var unsetName: VArray<UInt8, $13> = [
        87u8, 53u8, 95u8, 78u8, 79u8, 84u8, 95u8,
        83u8, 69u8, 84u8, 95u8, 88u8, 0u8
    ]
    unsafe {
        _ZN12MapleRuntime7LogFile8SetFlagsEv()
        _ZN12MapleRuntime7LogFile14SetFlagWithEnvEPKcNS_7LogTypeE(
            CPointer<UInt8>(inout unsetName), 0
        )
        _ZN12MapleRuntime7LogFile13CloseLogFilesEv()
    }
    return 0
}
