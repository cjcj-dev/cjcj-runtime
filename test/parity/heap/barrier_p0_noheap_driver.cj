package rt.heap.allocator

import rt.gc.*
import rt.objectmodel.*

foreign {
    func CJRT_TestInitSizeClass(object: CPointer<Unit>, typeInfo: CPointer<Unit>, instanceSize: UInt32): Unit
    func CJRT_TestInitSizeArray(object: CPointer<Unit>, arrayTypeInfo: CPointer<Unit>,
        componentTypeInfo: CPointer<Unit>, componentKind: Int8, componentSize: UInt32, length: UInt64): Unit
}

func ExerciseBaseObjectRoots(): Unit {
    var objectStorage = VArray<UInt64, $64>(repeat: 0)
    var typeInfoStorage = VArray<UInt64, $16>(repeat: 0)
    let object = unsafe { CPointer<Unit>(CPointer<UInt64>(inout objectStorage)) }
    unsafe { CJRT_TestInitSizeClass(object, CPointer<Unit>(CPointer<UInt64>(inout typeInfoStorage)), 17u32) }
    if (BarrierP0BaseObjectSizeRoot(CPointer<BaseObject>(object)) != 32) { unsafe { abort() } }

    var componentStorage = VArray<UInt64, $16>(repeat: 0)
    unsafe { CJRT_TestInitSizeArray(object, CPointer<Unit>(CPointer<UInt64>(inout typeInfoStorage)),
        CPointer<Unit>(CPointer<UInt64>(inout componentStorage)), -128i8, 8u32, 3u64) }
    if (BarrierP0BaseObjectSizeRoot(CPointer<BaseObject>(object)) != 40) { unsafe { abort() } }
}

func ExerciseMarkedRoots(large: Bool, state: UInt8, marked: Bool): Unit {
    let unitCount: UIntNative = 10
    let metadataSize = unitCount * sizeOf<UnitInfo>()
    let arenaSize = metadataSize + unitCount * RegionInfo.UNIT_SIZE
    let arena = CPointer<UInt8>(unsafe { malloc(arenaSize) })
    unsafe { let _ = memset(CPointer<Unit>(arena), 0, arenaSize) }
    let heapStart = unsafe { (arena + Int64(metadataSize)).toUIntNative() }
    RegionInfo.Initialize(unitCount, heapStart)
    let region = RegionInfo.InitRegion(4, 1, if (large) { LARGE_SIZED_UNITS } else { SMALL_SIZED_UNITS })
    var liveInfo = LiveInfo()
    var bitmapStorage = VArray<UInt64, $16>(repeat: 0)
    if (large) {
        region.SetMarkedRegionFlag(if (marked) { 1u8 } else { 0u8 })
    } else if (state == 1u8) {
        unsafe { CPointer<UIntNative>(CPointer<UInt8>(region) + 32).write(0, 0x1234) }
    } else if (state != 0u8) {
        if (state == 3u8) {
            liveInfo.markBitmap = unsafe { CPointer<RegionBitmap>(CPointer<UInt8>() + 0x1234) }
        } else if (state >= 4u8) {
            let bitmap = unsafe { CPointer<RegionBitmap>(CPointer<UInt64>(inout bitmapStorage)) }
            RegionBitmapConstruct(bitmap, UInt64(RegionInfo.UNIT_SIZE))
            if (marked) { let _ = RegionBitmapMarkBits(bitmap, 24u64, 8u64, UInt64(RegionInfo.UNIT_SIZE)) }
            liveInfo.markBitmap = bitmap
        }
        liveInfo.bindedRegion = CPointer<Unit>(region)
        unsafe { CPointer<CPointer<LiveInfo>>(CPointer<UInt8>(region) + 32).write(
            0, CPointer<LiveInfo>(inout liveInfo)) }
    }
    let object = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(
        heapStart + 4 * RegionInfo.UNIT_SIZE + 24)) }
    let objectResult = BarrierP0MarkedObjectRoot(region, object)
    let offsetResult = BarrierP0MarkedOffsetRoot(region, 24)
    if (objectResult != marked || offsetResult != marked) { unsafe { abort() } }
    unsafe { free(CPointer<Unit>(arena)) }
}

main(): Int64 {
    ExerciseBaseObjectRoots()
    ExerciseMarkedRoots(true, 0u8, false)
    ExerciseMarkedRoots(true, 0u8, true)
    ExerciseMarkedRoots(false, 0u8, false)
    ExerciseMarkedRoots(false, 1u8, false)
    ExerciseMarkedRoots(false, 2u8, false)
    ExerciseMarkedRoots(false, 3u8, false)
    ExerciseMarkedRoots(false, 4u8, false)
    ExerciseMarkedRoots(false, 4u8, true)
    println("BARRIER_P0_ROOT_EXEC base_class=PASS base_array=PASS object_paths=8 offset_paths=8 status=PASS")
    return 0
}
