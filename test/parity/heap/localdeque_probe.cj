import rt.heap.allocator.*

// Distinct opaque pointer values (never dereferenced; the deques only store them).
func mkptr(base: CPointer<UInt8>, i: Int64): CPointer<Unit> {
    return unsafe { CPointer<Unit>(base + i) }
}

main(): Int64 {
    var buf: VArray<UInt8, $16> = VArray<UInt8, $16>(repeat: 0u8)
    let base = unsafe { CPointer<UInt8>(inout buf) }

    // RTAllocatorT: bump allocation spaced by allocSize, then intrusive free-list reuse.
    let rta = RTAllocatorT()
    rta.Init(16, UIntNative(4096))
    let a0 = rta.Allocate()
    let a1 = rta.Allocate()
    let a2 = rta.Allocate()
    if (a1.toUIntNative() - a0.toUIntNative() != 16 || a2.toUIntNative() - a1.toUIntNative() != 16) {
        println("FAIL rta spacing")
        return 1
    }
    rta.Deallocate(a1)
    let a3 = rta.Allocate()
    if (a3.toUIntNative() != a1.toUIntNative()) {
        println("FAIL rta free-list reuse")
        return 2
    }
    rta.Fini()

    // SingleUseDeque: queue front + stack top over one MemMap.
    let sud = SingleUseDeque()
    sud.Init(UIntNative(4096))
    if (!sud.Empty()) { println("FAIL sud empty0"); return 3 }
    let p1 = mkptr(base, 1)
    let p2 = mkptr(base, 2)
    let p3 = mkptr(base, 3)
    sud.Push(p1)
    sud.Push(p2)
    sud.Push(p3)
    if (sud.Empty()) { println("FAIL sud empty1"); return 4 }
    if (sud.Front().toUIntNative() != p1.toUIntNative()) { println("FAIL sud front"); return 5 }
    if (sud.Top().toUIntNative() != p3.toUIntNative()) { println("FAIL sud top"); return 6 }
    sud.PopFront()
    if (sud.Front().toUIntNative() != p2.toUIntNative()) { println("FAIL sud popfront"); return 7 }
    sud.Pop()
    if (sud.Top().toUIntNative() != p2.toUIntNative()) { println("FAIL sud pop"); return 8 }
    sud.Clear()
    if (!sud.Empty()) { println("FAIL sud clear"); return 9 }
    sud.Fini()

    // LocalDeque: inline array of 512, then spill into a SingleUseDeque.
    let sud2 = SingleUseDeque()
    sud2.Init(UIntNative(8192))
    let ld = LocalDeque(sud2)
    if (!ld.Empty()) { println("FAIL ld empty0"); return 10 }
    var i = 0
    while (i < 515) {
        ld.Push(mkptr(base, i))
        i += 1
    }
    // Top is the last pushed; three items spilled past the 512-slot array.
    if (ld.Top().toUIntNative() != mkptr(base, 514).toUIntNative()) { println("FAIL ld top514"); return 11 }
    ld.Pop()
    if (ld.Top().toUIntNative() != mkptr(base, 513).toUIntNative()) { println("FAIL ld top513"); return 12 }
    ld.Pop()
    if (ld.Top().toUIntNative() != mkptr(base, 512).toUIntNative()) { println("FAIL ld top512"); return 13 }
    ld.Pop()
    // Crossing the spill boundary back into the inline array.
    if (ld.Top().toUIntNative() != mkptr(base, 511).toUIntNative()) { println("FAIL ld top511"); return 14 }
    // Front of the queue is the first pushed.
    if (ld.Front().toUIntNative() != mkptr(base, 0).toUIntNative()) { println("FAIL ld front0"); return 15 }
    var popped = 0
    while (popped < 512) {
        ld.Pop()
        popped += 1
    }
    if (!ld.Empty()) { println("FAIL ld empty-end"); return 16 }
    sud2.Fini()

    println("LOCALDEQUE_PROBE PASS")
    return 0
}
