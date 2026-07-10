package w2_varray_struct_store

@C
struct NativeSlice {
    let data: CPointer<UInt8>
    let size: Int64

    init(data: CPointer<UInt8>, size: Int64) {
        this.data = data
        this.size = size
    }
}

func Probe(): Unit {
    var slots = VArray<NativeSlice, $2>({ _: Int64 => NativeSlice(CPointer<UInt8>(), 0) })
    slots[0] = NativeSlice(CPointer<UInt8>(), 1)
}

main() {
    Probe()
}
