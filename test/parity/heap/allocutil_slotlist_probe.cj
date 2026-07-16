package allocutil.slotlist.probe

import rt.base.*
import rt.heap.allocator.*

private func TailIsZero(words: CPointer<UInt64>, first: UIntNative, count: UIntNative): Bool {
    for (i in first..count) {
        if (unsafe { words.read(Int64(i)) } != 0u64) {
            return false
        }
    }
    return true
}

main(): Int64 {
    println("ALLOCUTIL page=${ALLOC_UTIL_PAGE_SIZE} page_up_0=${ALLOCUTIL_PAGE_RND_UP(0)} " +
        "page_up_1=${ALLOCUTIL_PAGE_RND_UP(1)} page_up_4096=${ALLOCUTIL_PAGE_RND_UP(4096)} " +
        "rnd_down_4097=${AllocUtilRndDown(4097, 4096)} rnd_up_4097=${AllocUtilRndUp(4097, 4096)}")
    println("LAYOUT object_size=${sizeOf<ObjectSlot>()} object_align=${alignOf<ObjectSlot>()} " +
        "list_size=${sizeOf<SlotList>()} list_align=${alignOf<SlotList>()}")

    var slotA: VArray<UInt64, $4> = [
        32u64, 0xa5a5a5a5a5a5a5a5u64, 0xa5a5a5a5a5a5a5a5u64, 0xa5a5a5a5a5a5a5a5u64
    ]
    var slotB: VArray<UInt64, $6> = [
        48u64, 0xa5a5a5a5a5a5a5a5u64, 0xa5a5a5a5a5a5a5a5u64, 0xa5a5a5a5a5a5a5a5u64,
        0xa5a5a5a5a5a5a5a5u64, 0xa5a5a5a5a5a5a5a5u64
    ]
    let objectA = unsafe { CPointer<Unit>(CPointer<UInt64>(inout slotA)) }
    let objectB = unsafe { CPointer<Unit>(CPointer<UInt64>(inout slotB)) }
    let overlayA = unsafe { CPointer<ObjectSlot>(objectA) }
    let overlayB = unsafe { CPointer<ObjectSlot>(objectB) }

    var list = SlotList()
    list.PushFront(objectA)
    println("PUSH_A next_null=${unsafe { overlayA.read().next.isNull() }} " +
        "tail_zero=${TailIsZero(CPointer<UInt64>(inout slotA), 2, 4)}")
    list.PushFront(objectB)
    println("PUSH_B next_a=${unsafe { overlayB.read().next.toUIntNative() == overlayA.toUIntNative() }} " +
        "tail_zero=${TailIsZero(CPointer<UInt64>(inout slotB), 2, 6)}")
    println("POP_WRONG zero=${list.PopFront(32) == 0}")
    println("POP_B match=${list.PopFront(48) == unsafe { overlayB.toUIntNative() }} " +
        "next_null=${unsafe { overlayB.read().next.isNull() }}")
    println("POP_A match=${list.PopFront(32) == unsafe { overlayA.toUIntNative() }} " +
        "next_null=${unsafe { overlayA.read().next.isNull() }}")
    println("POP_EMPTY zero=${list.PopFront(32) == 0}")
    list.PushFront(objectA)
    list.Clear()
    println("CLEAR empty=${list.PopFront(32) == 0}")
    return 0
}
