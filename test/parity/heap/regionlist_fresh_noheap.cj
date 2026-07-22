package rt.heap.allocator

@NoHeapAlloc
@C
func FreshNoHeapVisitor(region: CPointer<RegionInfo>, context: CPointer<Unit>): Unit {
    let count = CPointer<UIntNative>(context)
    unsafe { count.write(0, count.read(0) + region.GetUnitCount()) }
}

@NoHeapAlloc
public func FreshRegionListLifecycle(list: CPointer<RegionList>, name: CString): Unit {
    RegionList.Construct(list, name)
    let _ = list.GetHeadRegion()
    let _ = list.GetTailRegion()
    let _ = list.GetRegionCount()
    let _ = GetUnitCount(list)
    let _ = list.GetListMutex()
    list.IncCounts(1, 1)
    list.DecCounts(1, 1)
    list.ClearList()
    RegionList.Destroy(list)
}

@NoHeapAlloc
public func FreshRegionListOperations(list: CPointer<RegionList>, src: CPointer<RegionList>,
    dst: CPointer<RegionList>, region: CPointer<RegionInfo>): UIntNative {
    list.PrependRegion(region, RECENT_FULL_REGION)
    let _ = list.TryDeleteRegion(region, FROM_REGION, TO_REGION)
    list.SetElementType(FROM_REGION)
    list.ClearTraceRegionFlag()
    list.CopyListTo(dst)
    dst.MoveTo(src)
    list.MergeRegionList(src, FROM_REGION)
    let _ = list.GetAllocatedSize()
    let _ = list.GetAllocatedSize(count: true)
    let taken = list.TakeHeadRegion(TO_REGION)
    list.PrependRegion(taken, TO_REGION)
    let plain = list.TakeHeadRegion()
    list.DeleteRegion(plain)
    return list.GetRegionCount()
}

@NoHeapAlloc
public func FreshRegionListVisitors(list: CPointer<RegionList>, context: CPointer<Unit>): Unit {
    list.VisitAllRegions(FreshNoHeapVisitor, context)
    list.VisitAllGhostRegions(FreshNoHeapVisitor, context)
}

@NoHeapAlloc
public func FreshRegionCache(cache: CPointer<RegionCache>, name: CString,
    region: CPointer<RegionInfo>): Unit {
    RegionCache.Construct(cache, name)
    let _ = cache.TryPrependRegion(region, RECENT_FULL_REGION)
    cache.ActivateRegionCache()
    cache.DeactivateRegionCache()
    RegionCache.Destroy(cache)
}

@NoHeapAlloc
public func FreshRegionListRemove(list: CPointer<RegionList>, region: CPointer<RegionInfo>): Unit {
    RemoveRegionLocked(list, region)
}

@When[debug]
@NoHeapAlloc
public func FreshRegionListDebug(list: CPointer<RegionList>, message: CPointer<UInt8>): Unit {
    list.DumpRegionList(message)
}
