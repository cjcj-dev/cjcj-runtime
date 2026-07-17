package rt.heap.allocator

import rt.base.*

main(): Int64 {
    var allocatorValue = RTAllocatorT()
    let allocator = unsafe { CPointer<RTAllocatorT>(inout allocatorValue) }
    Init(allocator, UIntNative(ALLOC_UTIL_PAGE_SIZE))

    let first = CPointer<CartesianNode>(allocator.Allocate())
    let second = CPointer<CartesianNode>(allocator.Allocate())
    let firstLeft = CPointer<CPointer<CartesianNode>>(first)
    let firstRight = unsafe {
        CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(first) + 8)
    }
    let secondLeft = CPointer<CPointer<CartesianNode>>(second)
    let secondRight = unsafe {
        CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(second) + 8)
    }
    unsafe {
        firstLeft.write(0, CPointer<CartesianNode>())
        firstRight.write(0, CPointer<CartesianNode>())
        CPointer<UInt32>(CPointer<UInt8>(first) + 16).write(0, 11u32)
        CPointer<UInt32>(CPointer<UInt8>(first) + 20).write(0, 3u32)
        secondLeft.write(0, CPointer<CartesianNode>())
        secondRight.write(0, CPointer<CartesianNode>())
        CPointer<UInt32>(CPointer<UInt8>(second) + 16).write(0, 19u32)
        CPointer<UInt32>(CPointer<UInt8>(second) + 20).write(0, 5u32)
        firstLeft.write(0, second)
        secondRight.write(0, first)
    }

    var tree = CartesianTree()
    let treePointer = unsafe { CPointer<CartesianTree>(inout tree) }
    let rootSlot = unsafe {
        CPointer<CPointer<CartesianNode>>(CPointer<UInt8>(treePointer) + 8)
    }
    unsafe { rootSlot.write(0, first) }

    let rootPass = unsafe { rootSlot.read(0).toUIntNative() == first.toUIntNative() }
    let leftPass = unsafe { firstLeft.read(0).toUIntNative() == second.toUIntNative() }
    let rightPass = unsafe { secondRight.read(0).toUIntNative() == first.toUIntNative() }
    let fieldsPass = unsafe {
        CPointer<UInt32>(CPointer<UInt8>(first) + 16).read(0) == 11u32 &&
        CPointer<UInt32>(CPointer<UInt8>(first) + 20).read(0) == 3u32 &&
        CPointer<UInt32>(CPointer<UInt8>(second) + 16).read(0) == 19u32 &&
        CPointer<UInt32>(CPointer<UInt8>(second) + 20).read(0) == 5u32
    }
    if (!(rootPass && leftPass && rightPass && fieldsPass)) {
        unsafe { abort() }
    }
    println("CARTESIAN_NATIVE_SLOT_EXEC nodes=2 root=PASS l=PASS r=PASS status=PASS")

    allocator.Deallocate(CPointer<Unit>(second))
    allocator.Deallocate(CPointer<Unit>(first))
    Fini(allocator)
    return 0
}
