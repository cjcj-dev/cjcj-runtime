package rt.gc

import std.overflow.*

foreign {
    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_u16_fetch_add_seq_cst(p: CPointer<UInt16>, value: UInt16): UInt16
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_u16_fetch_add_seq_cst(p: CPointer<UInt16>, value: UInt16): UInt16
    @When[os == "Windows"]
    func cj_atomic_u16_fetch_add_seq_cst(p: CPointer<UInt16>, value: UInt16): UInt16

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_u64_load_seq_cst(p: CPointer<UInt64>): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_u64_load_seq_cst(p: CPointer<UInt64>): UInt64
    @When[os == "Windows"]
    func cj_atomic_u64_load_seq_cst(p: CPointer<UInt64>): UInt64

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_u64_load_acquire(p: CPointer<UInt64>): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_u64_load_acquire(p: CPointer<UInt64>): UInt64
    @When[os == "Windows"]
    func cj_atomic_u64_load_acquire(p: CPointer<UInt64>): UInt64

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_u64_fetch_add_seq_cst(p: CPointer<UInt64>, value: UInt64): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_u64_fetch_add_seq_cst(p: CPointer<UInt64>, value: UInt64): UInt64
    @When[os == "Windows"]
    func cj_atomic_u64_fetch_add_seq_cst(p: CPointer<UInt64>, value: UInt64): UInt64

    @When[os == "Linux" || env == "ohos"]
    func cj_atomic_u64_fetch_or_seq_cst(p: CPointer<UInt64>, value: UInt64): UInt64
    @When[os == "macOS" || os == "iOS"]
    func cj_atomic_u64_fetch_or_seq_cst(p: CPointer<UInt64>, value: UInt64): UInt64
    @When[os == "Windows"]
    func cj_atomic_u64_fetch_or_seq_cst(p: CPointer<UInt64>, value: UInt64): UInt64

}

private const MARKED_BYTES_PER_BIT: UInt64 = 8
private const BITS_PER_WORD: UInt64 = 64
private const BITMAP_HEADER_SIZE: Int64 = 48

@C
public struct RegionBitmap {
    private var partLiveBytes: VArray<UInt16, $16>
    private var liveBytes: UInt64
    private var wordCnt: UInt64

    public init() {
        partLiveBytes = VArray<UInt16, $16>(repeat: 0u16)
        liveBytes = 0
        wordCnt = 0
    }
}

@C
public struct BitMaskInfo {
    public var headWordIdx: UInt64
    public var headMaskBits: UInt64
    public var tailWordCnt: UInt64
    public var lastMaskBits: UInt64

    public init() {
        headWordIdx = 0
        headMaskBits = 0
        tailWordCnt = 0
        lastMaskBits = 0
    }
}

@C
public struct PreMaskInfo {
    public var partIndex: Int8
    public var mask: UInt64
    public var stepSize: IntNative
    public var index: IntNative

    public init() {
        partIndex = 0
        mask = 0
        stepSize = 0
        index = 0
    }
}

@C
public struct LiveInfo {
    public var bindedRegion: CPointer<Unit>
    public var markBitmap: CPointer<RegionBitmap>
    public var resurrectBitmap: CPointer<RegionBitmap>
    public var enqueueBitmap: CPointer<RegionBitmap>

    public init() {
        bindedRegion = CPointer<Unit>()
        markBitmap = CPointer<RegionBitmap>()
        resurrectBitmap = CPointer<RegionBitmap>()
        enqueueBitmap = CPointer<RegionBitmap>()
    }
}

private func PartAddress(bitmap: CPointer<RegionBitmap>, index: UInt64): CPointer<UInt16> {
    return unsafe { CPointer<UInt16>(CPointer<UInt8>(bitmap) + Int64(index * 2)) }
}

private func LiveBytesAddress(bitmap: CPointer<RegionBitmap>): CPointer<UInt64> {
    return unsafe { CPointer<UInt64>(CPointer<UInt8>(bitmap) + 32) }
}

private func WordCountAddress(bitmap: CPointer<RegionBitmap>): CPointer<UInt64> {
    return unsafe { CPointer<UInt64>(CPointer<UInt8>(bitmap) + 40) }
}

private func MarkWordAddress(bitmap: CPointer<RegionBitmap>, index: UInt64): CPointer<UInt64> {
    return unsafe { CPointer<UInt64>(CPointer<UInt8>(bitmap) + BITMAP_HEADER_SIZE + Int64(index * 8)) }
}

private func PopCount(value: UInt64): UInt64 {
    var bits = value
    var count: UInt64 = 0
    while (bits != 0) {
        bits &= bits - 1
        count++
    }
    return count
}

public func RegionBitmapSize(regionSize: UInt64): UInt64 {
    return 48 + regionSize.wrappingDiv(MARKED_BYTES_PER_BIT * BITS_PER_WORD) * 8
}

public func RegionBitmapConstruct(bitmap: CPointer<RegionBitmap>, regionSize: UInt64): Unit {
    unsafe {
        LiveBytesAddress(bitmap).write(0, 0)
        WordCountAddress(bitmap).write(0, regionSize.wrappingDiv(MARKED_BYTES_PER_BIT * BITS_PER_WORD))
    }
}

public func RegionBitmapGetBitMaskInfo(start: UInt64, byteCnt: UInt64, maskInfo: CPointer<BitMaskInfo>): Unit {
    let headWordIdx = start.wrappingDiv(MARKED_BYTES_PER_BIT).wrappingDiv(BITS_PER_WORD)
    let headMaskBitStart = start.wrappingDiv(MARKED_BYTES_PER_BIT).wrappingMod(BITS_PER_WORD)
    var result = BitMaskInfo()
    result.headWordIdx = headWordIdx
    let headBitCnt = BITS_PER_WORD - headMaskBitStart
    let maskBitCnt = byteCnt.wrappingDiv(MARKED_BYTES_PER_BIT)
    if (maskBitCnt >= headBitCnt) {
        let tailBitCnt = maskBitCnt - headBitCnt
        result.headMaskBits = UInt64.Max ^ ((1u64 << headMaskBitStart) - 1)
        result.tailWordCnt = (tailBitCnt + BITS_PER_WORD - 1).wrappingDiv(BITS_PER_WORD)
        result.lastMaskBits = (1u64 << tailBitCnt.wrappingMod(BITS_PER_WORD)) - 1
    } else {
        let headMaskBitEnd = headMaskBitStart + maskBitCnt
        let headMaskBits = (1u64 << headMaskBitEnd) - 1
        result.headMaskBits = (headMaskBits >> headMaskBitStart) << headMaskBitStart
        result.tailWordCnt = 0
        result.lastMaskBits = 0
    }
    unsafe { maskInfo.write(0, result) }
}

@When[debug]
private func CheckZero(value: UInt64): Unit {
    if (value != 0) { unsafe { abort() } }
}

@When[!debug]
private func CheckZero(value: UInt64): Unit { let _ = value }

public func RegionBitmapApplyBitMaskInfo(bitmap: CPointer<RegionBitmap>, maskInfo: CPointer<BitMaskInfo>,
    byteCnt: UInt64, regionSize: UInt64): Bool {
    let info = unsafe { maskInfo.read(0) }
    var old = unsafe { cj_atomic_u64_load_seq_cst(MarkWordAddress(bitmap, info.headWordIdx)) }
    var isMarked = (old & info.headMaskBits) != 0
    if (isMarked) { return true }
    old = unsafe { cj_atomic_u64_fetch_or_seq_cst(MarkWordAddress(bitmap, info.headWordIdx), info.headMaskBits) }
    isMarked = (old & info.headMaskBits) != 0
    if (isMarked) { return true }
    var markWordSize = regionSize.wrappingDiv(MARKED_BYTES_PER_BIT * BITS_PER_WORD)
    let calFactor = if (markWordSize < 16u64) { markWordSize } else { 16u64 }
    if (markWordSize.wrappingMod(calFactor) != 0) {
        markWordSize += calFactor - markWordSize.wrappingMod(calFactor)
    }
    let partDivisor = markWordSize.wrappingDiv(calFactor)
    unsafe {
        cj_atomic_u16_fetch_add_seq_cst(PartAddress(bitmap, info.headWordIdx.wrappingDiv(partDivisor)),
            UInt16(PopCount(info.headMaskBits)))
        cj_atomic_u64_fetch_add_seq_cst(LiveBytesAddress(bitmap), byteCnt)
    }
    if (info.tailWordCnt > 0) {
        let lastWordIdx = info.headWordIdx + info.tailWordCnt
        if (info.lastMaskBits != 0) {
            var idx = info.headWordIdx + 1
            while (idx < lastWordIdx) {
                let zeros = unsafe { cj_atomic_u64_fetch_or_seq_cst(MarkWordAddress(bitmap, idx), UInt64.Max) }
                unsafe { cj_atomic_u16_fetch_add_seq_cst(PartAddress(bitmap, idx.wrappingDiv(partDivisor)), 64u16) }
                CheckZero(zeros)
                idx++
            }
            unsafe {
                cj_atomic_u64_fetch_or_seq_cst(MarkWordAddress(bitmap, lastWordIdx), info.lastMaskBits)
                cj_atomic_u16_fetch_add_seq_cst(PartAddress(bitmap, lastWordIdx.wrappingDiv(partDivisor)),
                    UInt16(PopCount(info.lastMaskBits)))
            }
        } else {
            var idx = info.headWordIdx + 1
            while (idx <= lastWordIdx) {
                let zeros = unsafe { cj_atomic_u64_fetch_or_seq_cst(MarkWordAddress(bitmap, idx), UInt64.Max) }
                unsafe { cj_atomic_u16_fetch_add_seq_cst(PartAddress(bitmap, idx.wrappingDiv(partDivisor)), 64u16) }
                CheckZero(zeros)
                idx++
            }
        }
    }
    return false
}

public func RegionBitmapMarkBits(bitmap: CPointer<RegionBitmap>, start: UInt64, byteCnt: UInt64,
    regionSize: UInt64): Bool {
    var info = BitMaskInfo()
    RegionBitmapGetBitMaskInfo(start, byteCnt, unsafe { CPointer<BitMaskInfo>(inout info) })
    return RegionBitmapApplyBitMaskInfo(bitmap, unsafe { CPointer<BitMaskInfo>(inout info) }, byteCnt, regionSize)
}

public func RegionBitmapIsMarked(bitmap: CPointer<RegionBitmap>, start: UInt64): Bool {
    let index = start.wrappingDiv(MARKED_BYTES_PER_BIT).wrappingDiv(BITS_PER_WORD)
    let bit = start.wrappingDiv(MARKED_BYTES_PER_BIT).wrappingMod(BITS_PER_WORD)
    return (unsafe { cj_atomic_u64_load_seq_cst(MarkWordAddress(bitmap, index)) } & (1u64 << bit)) != 0
}

public func RegionBitmapGetPreMaskInfo(offset: UInt64, regionSize: UInt64,
    maskInfo: CPointer<PreMaskInfo>): Unit {
    let index = IntNative(offset.wrappingDiv(BITS_PER_WORD * MARKED_BYTES_PER_BIT))
    var markWordSize = regionSize.wrappingDiv(MARKED_BYTES_PER_BIT * BITS_PER_WORD)
    let calFactor = if (markWordSize < 16u64) { markWordSize } else { 16u64 }
    if (markWordSize.wrappingMod(calFactor) != 0) {
        markWordSize += calFactor - markWordSize.wrappingMod(calFactor)
    }
    let step = IntNative(markWordSize.wrappingDiv(calFactor))
    var result = PreMaskInfo()
    result.index = index
    result.partIndex = Int8(index.wrappingDiv(step) - 1)
    result.mask = (1u64 << offset.wrappingDiv(MARKED_BYTES_PER_BIT).wrappingMod(BITS_PER_WORD)) - 1
    result.stepSize = step
    unsafe { maskInfo.write(0, result) }
}

public func RegionBitmapGetPreLiveBytes(bitmap: CPointer<RegionBitmap>, maskInfo: CPointer<PreMaskInfo>): UInt64 {
    let info = unsafe { maskInfo.read(0) }
    var preLiveBits: UInt64 = 0
    var partStartIndex: IntNative = 0
    var partIndex = info.partIndex
    while (partIndex >= 0) {
        preLiveBits += UInt64(unsafe { cj_atomic_u16_fetch_add_seq_cst(PartAddress(bitmap, UInt64(partIndex)), 0) })
        partIndex--
        partStartIndex += info.stepSize
    }
    var index = info.index
    var liveBits = PopCount(unsafe { cj_atomic_u64_load_seq_cst(MarkWordAddress(bitmap, UInt64(index))) } & info.mask)
    if (index == partStartIndex) { return (preLiveBits + liveBits) * MARKED_BYTES_PER_BIT }
    index--
    while (index >= partStartIndex) {
        liveBits += PopCount(unsafe { cj_atomic_u64_load_seq_cst(MarkWordAddress(bitmap, UInt64(index))) })
        index--
    }
    return (preLiveBits + liveBits) * MARKED_BYTES_PER_BIT
}

public func RegionBitmapGetLiveBytes(bitmap: CPointer<RegionBitmap>): UInt64 {
    return unsafe { cj_atomic_u64_load_acquire(LiveBytesAddress(bitmap)) }
}

public func RegionBitmapRecomputeLiveBytes(bitmap: CPointer<RegionBitmap>): UInt64 {
    let count = unsafe { cj_atomic_u64_load_acquire(WordCountAddress(bitmap)) }
    var liveBits: UInt64 = 0
    var index: UInt64 = 0
    while (index < count) {
        liveBits += PopCount(unsafe { cj_atomic_u64_load_acquire(MarkWordAddress(bitmap, index)) })
        index++
    }
    return liveBits * MARKED_BYTES_PER_BIT
}

public func LiveInfoGetPreLiveBytes(info: CPointer<LiveInfo>, offset: UInt64, regionSize: UInt64): UInt64 {
    var mask = PreMaskInfo()
    RegionBitmapGetPreMaskInfo(offset, regionSize, unsafe { CPointer<PreMaskInfo>(inout mask) })
    let value = unsafe { info.read(0) }
    var bytes: UInt64 = 0
    if (!value.markBitmap.isNull()) { bytes += RegionBitmapGetPreLiveBytes(value.markBitmap, unsafe { CPointer<PreMaskInfo>(inout mask) }) }
    if (!value.resurrectBitmap.isNull()) { bytes += RegionBitmapGetPreLiveBytes(value.resurrectBitmap, unsafe { CPointer<PreMaskInfo>(inout mask) }) }
    return bytes
}

public func LiveInfoIsSurvivedObject(info: CPointer<LiveInfo>, offset: UInt64): Bool {
    let value = unsafe { info.read(0) }
    return (!value.markBitmap.isNull() && RegionBitmapIsMarked(value.markBitmap, offset)) ||
        (!value.resurrectBitmap.isNull() && RegionBitmapIsMarked(value.resurrectBitmap, offset))
}

public func LiveInfoGetBitmapLiveBytes(info: CPointer<LiveInfo>): UInt64 {
    let value = unsafe { info.read(0) }
    return (if (value.markBitmap.isNull()) { 0 } else { RegionBitmapGetLiveBytes(value.markBitmap) }) +
        (if (value.resurrectBitmap.isNull()) { 0 } else { RegionBitmapGetLiveBytes(value.resurrectBitmap) })
}

public func LiveInfoRecomputeBitmapLiveBytes(info: CPointer<LiveInfo>): UInt64 {
    let value = unsafe { info.read(0) }
    return (if (value.markBitmap.isNull()) { 0 } else { RegionBitmapRecomputeLiveBytes(value.markBitmap) }) +
        (if (value.resurrectBitmap.isNull()) { 0 } else { RegionBitmapRecomputeLiveBytes(value.resurrectBitmap) })
}
