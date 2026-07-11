@C
struct CStringLayout {
    let str: CPointer<UInt8>
    let capacity: UInt64
    let length: UInt64

    init(str: CPointer<UInt8>, length: UInt64) {
        this.str = str
        this.capacity = 16u64
        this.length = length
    }
}

foreign func _ZN12MapleRuntime7CString15ParseNumFromEnvERKS0_(env: CPointer<UInt8>): Int32
foreign func _ZN12MapleRuntime7CString12IsPosDecimalERKS0_(env: CPointer<UInt8>): Bool
foreign func _ZN12MapleRuntime7CString8IsNumberERKS0_(env: CPointer<UInt8>): Bool

main(): Int64 {
    var integerBytes: VArray<UInt8, $4> = [45u8, 52u8, 50u8, 0u8]
    var decimalBytes: VArray<UInt8, $5> = [49u8, 50u8, 46u8, 53u8, 0u8]
    var invalidBytes: VArray<UInt8, $2> = [120u8, 0u8]
    var integer = CStringLayout(CPointer<UInt8>(inout integerBytes), 3u64)
    var decimal = CStringLayout(CPointer<UInt8>(inout decimalBytes), 4u64)
    var invalid = CStringLayout(CPointer<UInt8>(inout invalidBytes), 1u64)
    unsafe {
        let integerPtr = CPointer<UInt8>(inout integer)
        let decimalPtr = CPointer<UInt8>(inout decimal)
        let invalidPtr = CPointer<UInt8>(inout invalid)
        if (_ZN12MapleRuntime7CString15ParseNumFromEnvERKS0_(integerPtr) != -42) { return 1 }
        if (!_ZN12MapleRuntime7CString8IsNumberERKS0_(integerPtr)) { return 2 }
        if (!_ZN12MapleRuntime7CString12IsPosDecimalERKS0_(decimalPtr)) { return 3 }
        if (_ZN12MapleRuntime7CString8IsNumberERKS0_(invalidPtr)) { return 4 }
        if (_ZN12MapleRuntime7CString12IsPosDecimalERKS0_(invalidPtr)) { return 5 }
    }
    return 0
}
