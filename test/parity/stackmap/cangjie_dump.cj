package rt.stackmap

@C
private struct CangjieDumpWork {
    let data: CPointer<UInt8>
    let size: UInt64
    let stackGrow: UInt32
    let reserved: UInt32
    let events: CPointer<StackMapEvent>
    let capacity: UInt64
    let count: CPointer<UInt64>
    let opaque: CPointer<Unit>

    init() {
        data = CPointer<UInt8>()
        size = 0u64
        stackGrow = 0u32
        reserved = 0u32
        events = CPointer<StackMapEvent>()
        capacity = 0u64
        count = CPointer<UInt64>()
        opaque = CPointer<Unit>()
    }
}

foreign func CJRT_CangjieDumpFirst(): CPointer<CangjieDumpWork>
foreign func CJRT_CangjieDumpPrepare(work: CPointer<CangjieDumpWork>): Unit
foreign func CJRT_CangjieDumpAllocate(work: CPointer<CangjieDumpWork>): Unit
foreign func CJRT_CangjieDumpFinish(work: CPointer<CangjieDumpWork>, status: Int32): CPointer<CangjieDumpWork>
foreign func CJRT_CangjieDumpStatus(): Int32

main(): Int64 {
    var work = unsafe { CJRT_CangjieDumpFirst() }
    while (!work.isNull()) {
        unsafe { CJRT_CangjieDumpPrepare(work) }
        var current = unsafe { work.read() }
        var status = CJRT_StackMapDecode(current.data, current.size, current.stackGrow,
            CPointer<StackMapEvent>(), 0u64, current.count)
        if (status == STACKMAP_OK) {
            unsafe { CJRT_CangjieDumpAllocate(work) }
            current = unsafe { work.read() }
            status = CJRT_StackMapDecode(current.data, current.size, current.stackGrow,
                current.events, current.capacity, current.count)
        }
        work = unsafe { CJRT_CangjieDumpFinish(work, status) }
    }
    return Int64(unsafe { CJRT_CangjieDumpStatus() })
}
