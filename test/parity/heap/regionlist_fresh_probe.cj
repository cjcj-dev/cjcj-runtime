package rt.heap.allocator

@C
struct FreshVisitorState {
    var list: CPointer<RegionList>
    var count: UIntNative
    var sum: UIntNative
    init(list: CPointer<RegionList>) {
        this.list = list
        count = 0
        sum = 0
    }
}

@C
func FreshDeleteVisitor(region: CPointer<RegionInfo>, context: CPointer<Unit>): Unit {
    let state = CPointer<FreshVisitorState>(context)
    unsafe {
        let old = state.read(0)
        CPointer<UIntNative>(CPointer<UInt8>(state) + 8).write(0, old.count + 1)
        CPointer<UIntNative>(CPointer<UInt8>(state) + 16).write(
            0, old.sum + region.GetUnitIdx() + 1)
        RemoveRegionLocked(old.list, region)
    }
}

private func FreshIdx(region: CPointer<RegionInfo>): Int64 {
    return if (region.isNull()) { -1 } else { Int64(region.GetUnitIdx()) }
}

private func FreshRegion(idx: UIntNative, allocated: UIntNative): CPointer<RegionInfo> {
    let region = RegionInfo.InitRegion(idx, 1, SMALL_SIZED_UNITS)
    unsafe { CPointer<UIntNative>(region).write(0, region.GetRegionStart() + allocated) }
    return region
}

private func FreshConstruct(name: CPointer<UInt8>, value: CPointer<RegionList>): Unit {
    RegionList.Construct(value, CString(name))
}

main(): Int64 {
    var layout = RegionList(CString(CPointer<UInt8>()))
    let base = unsafe { CPointer<UInt8>(inout layout).toUIntNative() }
    let mutex = unsafe { CPointer<UInt8>(inout layout.listMutex).toUIntNative() } - base
    let countOffset = unsafe { CPointer<UInt8>(inout layout.regionCount).toUIntNative() } - base
    let unitsOffset = unsafe { CPointer<UInt8>(inout layout.unitCount).toUIntNative() } - base
    let headOffset = unsafe { CPointer<UInt8>(inout layout.listHead).toUIntNative() } - base
    let tailOffset = unsafe { CPointer<UInt8>(inout layout.listTail).toUIntNative() } - base
    let nameOffset = sizeOf<RegionList>() - sizeOf<CString>()
    var cacheLayout = RegionCache(CString(CPointer<UInt8>()))
    let cacheBase = unsafe { CPointer<UInt8>(inout cacheLayout).toUIntNative() }
    let activeOffset = unsafe { CPointer<UInt8>(inout cacheLayout.active).toUIntNative() } - cacheBase
    println("REGIONLIST_LAYOUT sizeof=${sizeOf<RegionList>()} align=${alignOf<RegionList>()} " +
        "mutex=${mutex} count=${countOffset} units=${unitsOffset} head=${headOffset} " +
        "tail=${tailOffset} name=${nameOffset} cache=${sizeOf<RegionCache>()} active=${activeOffset}")

    let unitCount: UIntNative = 12
    let metadata = unitCount * sizeOf<UnitInfo>()
    let arenaSize = metadata + unitCount * RegionInfo.UNIT_SIZE
    let arena = CPointer<UInt8>(unsafe { malloc(arenaSize) })
    unsafe { let _ = memset(CPointer<Unit>(arena), 0, arenaSize) }
    RegionInfo.Initialize(unitCount, unsafe { (arena + Int64(metadata)).toUIntNative() })

    var listName: VArray<UInt8, $5> = [108u8, 105u8, 115u8, 116u8, 0u8]
    var listValue = RegionList(CString(CPointer<UInt8>(inout listName)))
    let list = unsafe { CPointer<RegionList>(inout listValue) }
    FreshConstruct(CPointer<UInt8>(inout listName), list)
    list.PrependRegion(CPointer<RegionInfo>(), FROM_REGION)
    let r0 = FreshRegion(0, 10)
    let r1 = FreshRegion(1, 20)
    list.PrependRegion(r0, RECENT_FULL_REGION)
    list.PrependRegion(r1, RECENT_FULL_REGION)
    println("PREPEND regions=${list.GetRegionCount()} units=${GetUnitCount(list)} " +
        "head=${FreshIdx(list.GetHeadRegion())} tail=${FreshIdx(list.GetTailRegion())}")

    let wrong = list.TryDeleteRegion(r1, FROM_REGION, TO_REGION)
    let removed = list.TryDeleteRegion(r1, RECENT_FULL_REGION, TO_REGION)
    let taken = list.TakeHeadRegion(FROM_REGION)
    println("DELETE wrong=${if (wrong) { 1 } else { 0 }} removed=${if (removed) { 1 } else { 0 }} " +
        "taken=${FreshIdx(taken)} type=${taken.GetRegionType()} remaining=${list.GetRegionCount()}")

    var srcName: VArray<UInt8, $4> = [115u8, 114u8, 99u8, 0u8]
    var dstName: VArray<UInt8, $4> = [100u8, 115u8, 116u8, 0u8]
    var srcValue = RegionList(CString(CPointer<UInt8>(inout srcName)))
    var dstValue = RegionList(CString(CPointer<UInt8>(inout dstName)))
    let src = unsafe { CPointer<RegionList>(inout srcValue) }
    let dst = unsafe { CPointer<RegionList>(inout dstValue) }
    FreshConstruct(CPointer<UInt8>(inout srcName), src)
    FreshConstruct(CPointer<UInt8>(inout dstName), dst)
    src.PrependRegion(FreshRegion(2, 30), RECENT_FULL_REGION)
    src.PrependRegion(FreshRegion(3, 40), RECENT_FULL_REGION)
    dst.PrependRegion(FreshRegion(6, 70), LARGE_REGION)
    dst.MergeRegionList(src, FROM_REGION)
    println("MERGE regions=${dst.GetRegionCount()} src=${src.GetRegionCount()} " +
        "head=${FreshIdx(dst.GetHeadRegion())} tail=${FreshIdx(dst.GetTailRegion())} " +
        "bytes=${dst.GetAllocatedSize()} counted=${dst.GetAllocatedSize(count: true)}")

    var visitor = FreshVisitorState(dst)
    dst.VisitAllRegions(FreshDeleteVisitor, CPointer<Unit>(CPointer<FreshVisitorState>(inout visitor)))
    println("VISIT count=${visitor.count} sum=${visitor.sum} remaining=${dst.GetRegionCount()}")

    let r7 = FreshRegion(7, 80)
    var cacheName: VArray<UInt8, $6> = [99u8, 97u8, 99u8, 104u8, 101u8, 0u8]
    var cacheValue = RegionCache(CString(CPointer<UInt8>(inout cacheName)))
    let cache = unsafe { CPointer<RegionCache>(inout cacheValue) }
    RegionCache.Construct(cache, CString(CPointer<UInt8>(inout cacheName)))
    let inactive = cache.TryPrependRegion(r7, RECENT_FULL_REGION)
    cache.ActivateRegionCache()
    let active = cache.TryPrependRegion(r7, RECENT_FULL_REGION)
    r7.SetTraceRegionFlag(1u8)
    cache.DeactivateRegionCache()
    let cacheList = CPointer<RegionList>(cache)
    let cacheTake = cacheList.TakeHeadRegion()
    println("CACHE inactive=${if (inactive) { 1 } else { 0 }} active=${if (active) { 1 } else { 0 }} " +
        "regions=${cacheList.GetRegionCount() + 1} trace=${if (r7.IsTraceRegion()) { 1 } else { 0 }} " +
        "take=${FreshIdx(cacheTake)}")
    println("REGIONLIST_PARITY PASS")

    RegionCache.Destroy(cache)
    RegionList.Destroy(dst)
    RegionList.Destroy(src)
    RegionList.Destroy(list)
    unsafe { free(CPointer<Unit>(arena)) }
    return 0
}
