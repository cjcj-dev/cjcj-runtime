package rt.gc

@NoHeapAlloc
public func RegionBitmapNoHeapRoot(bitmap: CPointer<RegionBitmap>, info: CPointer<LiveInfo>): UInt64 {
    RegionBitmapConstruct(bitmap, 8192)
    RegionBitmapMarkBits(bitmap, 480, 552, 8192)
    var mask = BitMaskInfo()
    RegionBitmapGetBitMaskInfo(0, 8, unsafe { CPointer<BitMaskInfo>(inout mask) })
    RegionBitmapApplyBitMaskInfo(bitmap, unsafe { CPointer<BitMaskInfo>(inout mask) }, 8, 8192)
    var pre = PreMaskInfo()
    RegionBitmapGetPreMaskInfo(1032, 8192, unsafe { CPointer<PreMaskInfo>(inout pre) })
    let marked = RegionBitmapIsMarked(bitmap, 480)
    return RegionBitmapSize(8192) + RegionBitmapGetPreLiveBytes(bitmap,
        unsafe { CPointer<PreMaskInfo>(inout pre) }) + RegionBitmapGetLiveBytes(bitmap) +
        RegionBitmapRecomputeLiveBytes(bitmap) + LiveInfoGetPreLiveBytes(info, 1032, 8192) +
        LiveInfoGetBitmapLiveBytes(info) + LiveInfoRecomputeBitmapLiveBytes(info) +
        (if (marked || LiveInfoIsSurvivedObject(info, 480)) { 1 } else { 0 })
}
