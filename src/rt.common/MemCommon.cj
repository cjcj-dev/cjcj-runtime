package rt.common

// Common/MemCommon.h:19-40,114-205. Pure size-class mapping below the native
// allocator; no PagePool, ThreadCache, scheduler, or collector state is entered.
public const MAX_NPAGES: UIntNative = 129
public const PAGE_SHIFT: UIntNative = 12
public const MAX_BYTES: UIntNative = 256 * 1024
public const NFREELIST: UIntNative = 208
public const MIN_ALIGN_NUM: Int32 = 8

@NoHeapAlloc
private func SizeRoundUp(bytes: UIntNative, alignNum: UIntNative): UIntNative {
    return (bytes + alignNum - 1) & ~(alignNum - 1)
}

@NoHeapAlloc
private func SizeIndex(bytes: UIntNative, alignShift: UIntNative): UIntNative {
    return ((bytes + (UIntNative(1) << alignShift) - 1) >> alignShift) - 1
}

@NoHeapAlloc
public func SizeManagerRoundUp(bytes: UIntNative): UIntNative {
    if (bytes <= 128) { return SizeRoundUp(bytes, 8) }
    if (bytes <= 1024) { return SizeRoundUp(bytes, 16) }
    if (bytes <= 8 * 1024) { return SizeRoundUp(bytes, 128) }
    if (bytes <= 64 * 1024) { return SizeRoundUp(bytes, 1024) }
    if (bytes <= 256 * 1024) { return SizeRoundUp(bytes, 8 * 1028) }
    return UIntNative.Max
}

@NoHeapAlloc
public func SizeManagerIndex(bytes: UIntNative): UIntNative {
    if (bytes <= 128) { return SizeIndex(bytes, 3) }
    if (bytes <= 1024) { return SizeIndex(bytes - 128, 4) + 16 }
    if (bytes <= 8 * 1024) { return SizeIndex(bytes - 1024, 7) + 72 }
    if (bytes <= 64 * 1024) { return SizeIndex(bytes - 8 * 1024, 10) + 128 }
    if (bytes <= 256 * 1024) { return SizeIndex(bytes - 64 * 1024, 13) + 184 }
    return UIntNative.Max
}

@NoHeapAlloc
public func SizeManagerLimitSize(alignBytes: UIntNative): UIntNative {
    var num = MAX_BYTES / alignBytes
    if (num < 2) { num = 2 }
    if (num > 512) { num = 512 }
    return num
}

@NoHeapAlloc
public func SizeManagerCalculatePageNum(alignBytes: UIntNative): UIntNative {
    var npage = (SizeManagerLimitSize(alignBytes) * alignBytes) >> PAGE_SHIFT
    if (npage == 0) { npage = 1 }
    return npage
}
