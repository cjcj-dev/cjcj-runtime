import rt.common.*

main(): Int64 {
    let values = [1u64, 8u64, 9u64, 128u64, 129u64, 1024u64, 1025u64, 8192u64,
        8193u64, 65536u64, 65537u64, 262144u64, 262145u64]
    for (value in values) {
        println("SIZE ${value} ${SizeManagerRoundUp(UIntNative(value))} ${SizeManagerIndex(UIntNative(value))}")
    }
    for (align in [8u64, 4096u64, 262144u64]) {
        println("BATCH ${align} ${SizeManagerLimitSize(UIntNative(align))} " +
            "${SizeManagerCalculatePageNum(UIntNative(align))}")
    }
    println("MEMCOMMON ${MAX_NPAGES} ${PAGE_SHIFT} ${MAX_BYTES} ${NFREELIST} ${MIN_ALIGN_NUM}")
    return 0
}
