package rt.gc

foreign {
    func calloc(count: UIntNative, size: UIntNative): CPointer<Unit>
    func free(address: CPointer<Unit>): Unit
}

private func Make(regionSize: UInt64): CPointer<RegionBitmap> {
    let bitmap = CPointer<RegionBitmap>(unsafe { calloc(1, UIntNative(RegionBitmapSize(regionSize))) })
    RegionBitmapConstruct(bitmap, regionSize)
    return bitmap
}

main(): Int64 {
    let regionSize = 8192u64
    let first = Make(regionSize)
    let second = Make(regionSize)
    println("REGIONBITMAP_LAYOUT bitmap=${sizeOf<RegionBitmap>()}/${alignOf<RegionBitmap>()} " +
        "bits=${sizeOf<BitMaskInfo>()}/${alignOf<BitMaskInfo>()} " +
        "pre=${sizeOf<PreMaskInfo>()}/${alignOf<PreMaskInfo>()} " +
        "liveinfo=${sizeOf<LiveInfo>()}/${alignOf<LiveInfo>()} size=${RegionBitmapSize(regionSize)}")
    let firstMark = RegionBitmapMarkBits(first, 480, 552, regionSize)
    let repeat = RegionBitmapMarkBits(first, 480, 552, regionSize)
    var pre = PreMaskInfo()
    RegionBitmapGetPreMaskInfo(1032, regionSize, unsafe { CPointer<PreMaskInfo>(inout pre) })
    println("MARK first=${if (firstMark) { 1 } else { 0 }} repeat=${if (repeat) { 1 } else { 0 }} " +
        "marked480=${if (RegionBitmapIsMarked(first, 480)) { 1 } else { 0 }} " +
        "marked1024=${if (RegionBitmapIsMarked(first, 1024)) { 1 } else { 0 }} " +
        "live=${RegionBitmapGetLiveBytes(first)} recompute=${RegionBitmapRecomputeLiveBytes(first)} " +
        "pre=${RegionBitmapGetPreLiveBytes(first, unsafe { CPointer<PreMaskInfo>(inout pre) })}")
    RegionBitmapMarkBits(second, 0, 8, regionSize)
    var live = LiveInfo()
    live.markBitmap = first
    live.resurrectBitmap = second
    let info = unsafe { CPointer<LiveInfo>(inout live) }
    println("LIVE survived0=${if (LiveInfoIsSurvivedObject(info, 0)) { 1 } else { 0 }} " +
        "survived480=${if (LiveInfoIsSurvivedObject(info, 480)) { 1 } else { 0 }} " +
        "survived2048=${if (LiveInfoIsSurvivedObject(info, 2048)) { 1 } else { 0 }} " +
        "bytes=${LiveInfoGetBitmapLiveBytes(info)} recompute=${LiveInfoRecomputeBitmapLiveBytes(info)} " +
        "pre=${LiveInfoGetPreLiveBytes(info, 1032, regionSize)}")
    println("REGIONBITMAP_PARITY PASS")
    unsafe { free(CPointer<Unit>(first)); free(CPointer<Unit>(second)) }
    return 0
}
