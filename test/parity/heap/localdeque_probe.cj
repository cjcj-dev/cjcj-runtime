package rt.heap.allocator

foreign { func exit(status: Int32): Unit }

func Require(condition: Bool, message: String): Unit {
    if (!condition) {
        println("LOCALDEQUE_CJ FAIL ${message}")
        unsafe { exit(1) }
    }
}

func Pointer(base: CPointer<UInt8>, value: UInt64): CPointer<Unit> {
    return unsafe { CPointer<Unit>(base + Int64(value)) }
}

func Token(base: CPointer<UInt8>, value: CPointer<Unit>): UInt64 {
    return UInt64(value.toUIntNative() - base.toUIntNative())
}

struct Model {
    var values: VArray<UInt64, $1024>
    var head: Int64 = 0
    var length: Int64 = 0

    init() {
        values = VArray<UInt64, $1024>(repeat: 0u64)
    }

    mut func Push(value: UInt64): Unit {
        Require(length < 1024, "model overflow")
        values[(head + length) % 1024] = value
        length += 1
    }

    func Front(): UInt64 {
        return values[head]
    }

    func Top(): UInt64 {
        return values[(head + length - 1) % 1024]
    }

    mut func Pop(): Unit {
        length -= 1
    }

    mut func PopFront(): Unit {
        head = (head + 1) % 1024
        length -= 1
    }
}

main(): Int64 {
    var storage = VArray<UInt8, $4096>(repeat: 0u8)
    let base = unsafe { CPointer<UInt8>(inout storage) }
    var operations = 0u64
    var records = 0u64

    var allocatorValue = RTAllocatorT()
    let allocator = unsafe { CPointer<RTAllocatorT>(inout allocatorValue) }
    allocator.Init(UIntNative(4096))
    let alloc0 = allocator.Allocate()
    let alloc1 = allocator.Allocate()
    let alloc2 = allocator.Allocate()
    Require(alloc1.toUIntNative() - alloc0.toUIntNative() == 24 &&
        alloc2.toUIntNative() - alloc1.toUIntNative() == 24, "RTAllocatorT spacing")
    allocator.Deallocate(alloc1)
    Require(allocator.Allocate().toUIntNative() == alloc1.toUIntNative(), "RTAllocatorT reuse")
    allocator.Fini()
    println("SMOKE RTAllocatorT spacing=24 reuse=1")
    records += 1

    var singleUseValue = SingleUseDeque()
    let singleUse = unsafe { CPointer<SingleUseDeque>(inout singleUseValue) }
    singleUse.Init(UIntNative(16384))
    Require(singleUse.Empty(), "SingleUseDeque initial empty")
    singleUse.Push(Pointer(base, 11u64))
    singleUse.Push(Pointer(base, 22u64))
    singleUse.Push(Pointer(base, 33u64))
    Require(Token(base, singleUse.Front()) == 11u64 && Token(base, singleUse.Top()) == 33u64,
        "SingleUseDeque ends")
    singleUse.PopFront()
    singleUse.Pop()
    Require(Token(base, singleUse.Front()) == 22u64 && Token(base, singleUse.Top()) == 22u64,
        "SingleUseDeque pops")
    singleUse.Clear()
    Require(singleUse.Empty(), "SingleUseDeque clear")
    println("SMOKE SingleUseDeque front=22 top=22 clear_empty=1")
    records += 1

    var emptyDeque = LocalDeque(singleUse)
    let initialEmpty = emptyDeque.Empty()
    operations += 1
    Require(initialEmpty, "initial empty")
    println("CASE empty initial=1")
    records += 1

    var inlineDeque = LocalDeque(singleUse)
    inlineDeque.Push(Pointer(base, 11u64)); operations += 1
    inlineDeque.Push(Pointer(base, 22u64)); operations += 1
    inlineDeque.Push(Pointer(base, 33u64)); operations += 1
    let inlineTop = Token(base, inlineDeque.Top()); operations += 1
    let inlineFront = Token(base, inlineDeque.Front()); operations += 1
    inlineDeque.Pop(); operations += 1
    let inlineAfterPop = Token(base, inlineDeque.Top()); operations += 1
    inlineDeque.PopFront(); operations += 1
    let inlineAfterPopFront = Token(base, inlineDeque.Front()); operations += 1
    let inlineEmpty = inlineDeque.Empty(); operations += 1
    Require(inlineTop == 33u64 && inlineFront == 11u64 && inlineAfterPop == 22u64 &&
        inlineAfterPopFront == 22u64 && !inlineEmpty, "inline LIFO/FIFO")
    println("CASE inline top=33 front=11 after_pop=22 after_popfront=22 empty=0")
    records += 1

    var exactIndex = 0
    while (exactIndex < 3) {
        let count: Int64 = if (exactIndex == 0) { 511 } else if (exactIndex == 1) { 512 } else { 513 }
        var exactDeque = LocalDeque(singleUse)
        var exactValue: Int64 = 1
        while (exactValue <= count) {
            exactDeque.Push(Pointer(base, UInt64(exactValue)))
            operations += 1
            exactValue += 1
        }
        let exactFront = Token(base, exactDeque.Front()); operations += 1
        let exactTop = Token(base, exactDeque.Top()); operations += 1
        let exactEmpty = exactDeque.Empty(); operations += 1
        Require(exactFront == 1u64 && exactTop == UInt64(count) && !exactEmpty, "exact push count")
        println("CASE exact pushes=${count} front=${exactFront} top=${exactTop} empty=0")
        records += 1
        exactIndex += 1
    }

    var spillFrontLt = LocalDeque(singleUse)
    var spillValue = 1u64
    while (spillValue <= 513u64) {
        spillFrontLt.Push(Pointer(base, spillValue)); operations += 1
        spillValue += 1
    }
    let spillTop = Token(base, spillFrontLt.Top()); operations += 1
    let spillInlineFront = Token(base, spillFrontLt.Front()); operations += 1
    spillFrontLt.Pop(); operations += 1
    let spillBoundaryTop = Token(base, spillFrontLt.Top()); operations += 1
    let spillLtEmpty = spillFrontLt.Empty(); operations += 1
    Require(spillTop == 513u64 && spillInlineFront == 1u64 && spillBoundaryTop == 512u64 &&
        !spillLtEmpty, "spill pop front-less branch")
    println("CASE spill_front_lt spill_top=513 inline_front=1 boundary_top=512 empty=0")
    records += 1

    var spillMultiPop = LocalDeque(singleUse)
    spillValue = 1u64
    while (spillValue <= 514u64) {
        spillMultiPop.Push(Pointer(base, spillValue)); operations += 1
        spillValue += 1
    }
    let multiPopTop = Token(base, spillMultiPop.Top()); operations += 1
    spillMultiPop.Pop(); operations += 1
    let multiPopAfterOne = Token(base, spillMultiPop.Top()); operations += 1
    spillMultiPop.Pop(); operations += 1
    let multiPopBoundaryTop = Token(base, spillMultiPop.Top()); operations += 1
    let multiPopEmpty = spillMultiPop.Empty(); operations += 1
    Require(multiPopTop == 514u64 && multiPopAfterOne == 513u64 &&
        multiPopBoundaryTop == 512u64 && !multiPopEmpty, "multi-spill Pop boundary")
    println("CASE spill_multi_pop top=514 after_one=513 boundary_top=512 empty=0")
    records += 1

    var spillFrontEq = LocalDeque(singleUse)
    spillValue = 1u64
    while (spillValue <= 513u64) {
        spillFrontEq.Push(Pointer(base, spillValue)); operations += 1
        spillValue += 1
    }
    var popFrontCount = 0
    while (popFrontCount < 512) {
        spillFrontEq.PopFront(); operations += 1
        popFrontCount += 1
    }
    let spillEqFront = Token(base, spillFrontEq.Front()); operations += 1
    spillFrontEq.Pop(); operations += 1
    let resetEmpty = spillFrontEq.Empty(); operations += 1
    spillFrontEq.Push(Pointer(base, 777u64)); operations += 1
    let resetTop = Token(base, spillFrontEq.Top()); operations += 1
    let resetFront = Token(base, spillFrontEq.Front()); operations += 1
    Require(spillEqFront == 513u64 && resetEmpty && resetTop == 777u64 && resetFront == 777u64,
        "spill front equals reset branch")
    println("CASE spill_front_eq spill_front=513 reset_empty=1 reset_top=777 reset_front=777")
    records += 1

    var spillPopFront = LocalDeque(singleUse)
    spillValue = 1u64
    while (spillValue <= 513u64) {
        spillPopFront.Push(Pointer(base, spillValue)); operations += 1
        spillValue += 1
    }
    popFrontCount = 0
    while (popFrontCount < 512) {
        spillPopFront.PopFront(); operations += 1
        popFrontCount += 1
    }
    let boundaryFront = Token(base, spillPopFront.Front()); operations += 1
    spillPopFront.PopFront(); operations += 1
    let spillPopFrontEmpty = spillPopFront.Empty(); operations += 1
    Require(boundaryFront == 513u64 && spillPopFrontEmpty, "spill pop-front boundary")
    println("CASE spill_popfront boundary_front=513 empty=1")
    records += 1

    var spillMultiPopFront = LocalDeque(singleUse)
    spillValue = 1u64
    while (spillValue <= 514u64) {
        spillMultiPopFront.Push(Pointer(base, spillValue)); operations += 1
        spillValue += 1
    }
    popFrontCount = 0
    while (popFrontCount < 512) {
        spillMultiPopFront.PopFront(); operations += 1
        popFrontCount += 1
    }
    let firstSpillFront = Token(base, spillMultiPopFront.Front()); operations += 1
    spillMultiPopFront.PopFront(); operations += 1
    let secondSpillFront = Token(base, spillMultiPopFront.Front()); operations += 1
    spillMultiPopFront.PopFront(); operations += 1
    let multiPopFrontEmpty = spillMultiPopFront.Empty(); operations += 1
    Require(firstSpillFront == 513u64 && secondSpillFront == 514u64 && multiPopFrontEmpty,
        "multi-spill PopFront boundary")
    println("CASE spill_multi_popfront first=513 second=514 empty=1")
    records += 1

    let lifetimeCount = 1100
    var lifetime = 0
    while (lifetime < lifetimeCount) {
        var lifetimeDeque = LocalDeque(singleUse)
        let pushes = if (lifetime % 4 == 0) { 513 } else { 3 }
        var lifetimeIndex = 0
        var first = 0u64
        var last = 0u64
        while (lifetimeIndex < pushes) {
            let value = (UInt64(lifetime) * 17u64 + UInt64(lifetimeIndex) * 13u64) % 4000u64 + 1u64
            if (lifetimeIndex == 0) {
                first = value
            }
            last = value
            lifetimeDeque.Push(Pointer(base, value)); operations += 1
            lifetimeIndex += 1
        }
        let lifetimeTop = Token(base, lifetimeDeque.Top()); operations += 1
        let lifetimeFront = Token(base, lifetimeDeque.Front()); operations += 1
        lifetimeDeque.Pop(); operations += 1
        let lifetimeAfterPop = Token(base, lifetimeDeque.Top()); operations += 1
        lifetimeDeque.PopFront(); operations += 1
        let lifetimeAfterPopFront = Token(base, lifetimeDeque.Front()); operations += 1
        let lifetimeEmpty = lifetimeDeque.Empty(); operations += 1
        Require(lifetimeTop == last && lifetimeFront == first && !lifetimeEmpty, "fresh lifetime ends")
        println("LIFETIME id=${lifetime} pushes=${pushes} top=${lifetimeTop} front=${lifetimeFront} " +
            "after_pop=${lifetimeAfterPop} after_popfront=${lifetimeAfterPopFront} empty=0")
        records += 1
        lifetime += 1
    }

    var mixed = LocalDeque(singleUse)
    var model = Model()
    var seed = 0x4c4f43414c444551u64
    let mixedSteps = 1200
    var step = 0
    while (step < mixedSteps) {
        seed = seed * 6364136223846793005u64 + 1442695040888963407u64
        var action = Int64(seed % 6u64)
        if (model.length == 0) {
            action = 0
        } else if (model.length >= 700) {
            action = if ((seed & 1u64) == 0u64) { 3 } else { 5 }
        }

        var name = ""
        var argument = 0u64
        var result = 0u64
        if (action <= 1) {
            name = "PUSH"
            argument = (UInt64(step) * 37u64 + (seed >> 17u64)) % 4000u64 + 1u64
            mixed.Push(Pointer(base, argument)); operations += 1
            model.Push(argument)
            result = argument
        } else if (action == 2) {
            name = "TOP"
            result = Token(base, mixed.Top()); operations += 1
            Require(result == model.Top(), "mixed Top")
        } else if (action == 3) {
            name = "POP"
            result = Token(base, mixed.Top()); operations += 1
            Require(result == model.Top(), "mixed Pop result")
            mixed.Pop(); operations += 1
            model.Pop()
        } else if (action == 4) {
            name = "FRONT"
            result = Token(base, mixed.Front()); operations += 1
            Require(result == model.Front(), "mixed Front")
        } else {
            name = "POPFRONT"
            result = Token(base, mixed.Front()); operations += 1
            Require(result == model.Front(), "mixed PopFront result")
            mixed.PopFront(); operations += 1
            model.PopFront()
        }

        let mixedEmpty = mixed.Empty(); operations += 1
        Require(mixedEmpty == (model.length == 0), "mixed Empty")
        var stateFront = 0u64
        var stateTop = 0u64
        if (model.length != 0) {
            stateFront = Token(base, mixed.Front()); operations += 1
            stateTop = Token(base, mixed.Top()); operations += 1
            Require(stateFront == model.Front() && stateTop == model.Top(), "mixed full state")
        }
        let emptyNumber = if (mixedEmpty) { 1 } else { 0 }
        println("TRACE step=${step} op=${name} arg=${argument} result=${result} len=${model.length} " +
            "front=${stateFront} top=${stateTop} empty=${emptyNumber}")
        records += 1
        step += 1
    }
    println("MIXED PASS seed=${seed} steps=${mixedSteps} final_len=${model.length}")
    records += 1

    singleUse.Fini()
    println("LOCALDEQUE_PARITY PASS lifetimes=${lifetimeCount} operations=${operations} records=${records}")
    return 0
}
