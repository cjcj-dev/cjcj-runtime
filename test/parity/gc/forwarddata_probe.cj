package rt.gc.forwarddata

import rt.gc.*
import rt.heap.allocator.*

@When[os != "Windows"]
private func ProbeManagerOffset(): Int64 { return 96 }
@When[os == "Windows"]
private func ProbeManagerOffset(): Int64 { return 144 }

main(): Int64 {
    var managerValue = ForwardDataManager()
    let manager = unsafe { CPointer<ForwardDataManager>(inout managerValue) }
    let raw = ForwardDataGetLiveInfoDataSize(manager, 8192)
    ForwardDataInitializeForCapacity(manager, 8192)
    let start = unsafe {
        CPointer<UIntNative>(CPointer<UInt8>(manager) + ProbeManagerOffset() + 8).read(0)
    }
    let total = unsafe {
        CPointer<UIntNative>(CPointer<UInt8>(manager) + ProbeManagerOffset() + 16).read(0)
    }
    let live = ForwardDataAllocateLiveInfo(manager)
    let bitmap0 = ForwardDataAllocateRegionBitmap(manager, 8192)
    let bitmap1 = ForwardDataAllocateRegionBitmap(manager, 8192)
    let first = RegionBitmapMarkBits(bitmap0, 0, 16, 8192)
    var regionValue = RegionInfo()
    let region = unsafe { CPointer<RegionInfo>(inout regionValue) }
    unsafe {
        CPointer<CPointer<Unit>>(CPointer<UInt8>(region) + 32).write(0, CPointer<Unit>(live))
        CPointer<UInt32>(CPointer<UInt8>(region) + 24).write(0, 77u32)
        CPointer<CPointer<Unit>>(live).write(0, CPointer<Unit>(region))
    }
    ForwardDataSetTagID(manager, 1u16)
    ForwardDataUnbindPrevious(manager)
    println("FORWARDDATA_LAYOUT zone=${sizeOf<ForwardDataZone>()}/${alignOf<ForwardDataZone>()} " +
        "space=${sizeOf<ForwardDataSpace>()}/${alignOf<ForwardDataSpace>()} " +
        "manager=${sizeOf<ForwardDataManager>()}/${alignOf<ForwardDataManager>()}")
    println("CAP heap=8192 units=2 raw=${raw} per_space=${total / 2} total=${total}")
    println("ALLOC live=${live.toUIntNative() - start} bitmap0=${bitmap0.toUIntNative() - start} " +
        "bitmap1=${bitmap1.toUIntNative() - start} bitmap_size=${RegionBitmapSize(8192)}")
    let firstInt = if (first) { 1 } else { 0 }
    println("MARK first=${firstInt} live=${RegionBitmapGetLiveBytes(bitmap0)} " +
        "previous=${ForwardDataGetPreviousTagID(manager)}")
    let liveNull = if (unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(region) + 32).read(0) }.isNull()) {
        1
    } else { 0 }
    let bytes = unsafe { CPointer<UInt32>(CPointer<UInt8>(region) + 24).read(0) }
    println("UNBIND live_null=${liveNull} bytes=${bytes}")
    ForwardDataClearPrevious(manager)
    let livePosition = unsafe { CPointer<UIntNative>(CPointer<UInt8>(manager) + 8).read(0) }
    let bitmapPosition = unsafe { CPointer<UIntNative>(CPointer<UInt8>(manager) + 24).read(0) }
    println("RESET live=${livePosition - start} bitmap=${bitmapPosition - start}")
    ForwardDataDestroy(manager)
    return 0
}
