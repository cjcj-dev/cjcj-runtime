package rt.common

foreign func ThreadLocalTLSABIBarrier(): Unit

// Test-only adjacent-byte checksum. It reads individual bytes and never loads
// or copies the ThreadLocalData aggregate.
func ThreadLocalTLSABIHashOutside(record: CPointer<UInt8>, offset: Int64, width: Int64): UInt64 {
    var hash = 1469598103934665603u64
    var index: Int64 = 0
    while (index < 88) {
        if (index < offset || index >= offset + width) {
            hash = (hash ^ UInt64(unsafe { (record + index).read(0) })) * 1099511628211u64
        }
        index += 1
    }
    return hash
}

// Test-only C entry points for the native pthread driver. Every operation calls
// the production surface in ThreadLocal.cj; none owns TLS storage.
@C
public func CJRT_ThreadLocalGetAddress(): UIntNative {
    return unsafe { GetThreadLocalData().toUIntNative() }
}

@C
public func CJRT_ThreadLocalCheckOffset(): Unit {
    MCC_CheckThreadLocalDataOffset()
}

// Test-only single-entry exercise. Runtime-critical TLS fields are restored
// before the function returns across the native-to-Cangjie boundary.
@C
public func CJRT_ThreadLocalExercise(threadIndex: UIntNative): UInt64 {
    let threadLocalData = GetThreadLocalData()
    let record = CPointer<UInt8>(threadLocalData)
    let originalHash = ThreadLocalTLSABIHashOutside(record, 88, 0)
    let originalBuffer = unsafe { CPointer<CPointer<Unit>>(record).read(0) }
    let originalMutator = unsafe { CPointer<CPointer<Unit>>(record + 8).read(0) }
    let originalCJThread = unsafe { CPointer<CPointer<UInt8>>(record + 16).read(0) }
    let originalSchedule = unsafe { CPointer<CPointer<UInt8>>(record + 24).read(0) }
    let originalPreempt = unsafe { CPointer<CPointer<UInt8>>(record + 32).read(0) }
    let originalProtect = unsafe { CPointer<CPointer<UInt8>>(record + 40).read(0) }
    let originalForeign = unsafe { CPointer<CPointer<Unit>>(record + 64).read(0) }
    let originalType = unsafe { CPointer<ThreadType>(record + 72).read(0) }
    let originalProcessor = unsafe { CPointer<Bool>(record + 76).read(0) }
    let originalCache = unsafe { CPointer<CPointer<Unit>>(record + 80).read(0) }
    var helpers = !threadLocalData.isNull() && GetThreadLocalData().toUIntNative() ==
        threadLocalData.toUIntNative()
    var adjacent = true
    var outsideBefore = ThreadLocalTLSABIHashOutside(record, 0, 8)
    var outsideAfter: UInt64

    var pointerBits = 0x10000000u64 + UInt64(threadIndex << 16) + 0x5au64
    var pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    SetAllocBuffer(pointer)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 0, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && GetAllocBuffer().toUIntNative() == UIntNative(pointerBits)
    unsafe { CPointer<CPointer<Unit>>(record).write(0, originalBuffer) }

    pointerBits = 0x10000100u64 + UInt64(threadIndex << 16) + 0x5au64
    pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 8, 8)
    SetMutator(pointer)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 8, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && GetMutator().toUIntNative() == UIntNative(pointerBits)
    unsafe { CPointer<CPointer<Unit>>(record + 8).write(0, originalMutator) }

    pointerBits = 0x20000000u64 + UInt64(threadIndex << 16) + 0x5au64
    pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 32, 8)
    unsafe { CPointer<CPointer<UInt8>>(record + 32).write(0, CPointer<UInt8>(pointer)) }
    helpers = helpers && GetPreemptFlag().toUIntNative() == UIntNative(pointerBits)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 32, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    unsafe { CPointer<CPointer<UInt8>>(record + 32).write(0, originalPreempt) }

    pointerBits = 0x10000200u64 + UInt64(threadIndex << 16) + 0x5au64
    pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 40, 8)
    SetProtectAddr(CPointer<UInt8>(pointer))
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 40, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && unsafe {
        CPointer<CPointer<UInt8>>(record + 40).read(0).toUIntNative() == UIntNative(pointerBits)
    }
    unsafe { CPointer<CPointer<UInt8>>(record + 40).write(0, originalProtect) }

    let typeSentinel = Int32(0x30000000u32 + UInt32(threadIndex))
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 72, 4)
    SetThreadType(typeSentinel)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 72, 4)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && GetThreadType() == typeSentinel
    unsafe { CPointer<ThreadType>(record + 72).write(0, originalType) }

    outsideBefore = ThreadLocalTLSABIHashOutside(record, 76, 1)
    SetCJProcessorFlag(true)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 76, 1)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && IsCJProcessor()
    unsafe { CPointer<Bool>(record + 76).write(0, originalProcessor) }

    pointerBits = 0x10000300u64 + UInt64(threadIndex << 16) + 0x5au64
    pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 64, 8)
    SetForeignCJThread(pointer)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 64, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && GetForeignCJThread().toUIntNative() == UIntNative(pointerBits)
    unsafe { CPointer<CPointer<Unit>>(record + 64).write(0, originalForeign) }

    pointerBits = 0x10000400u64 + UInt64(threadIndex << 16) + 0x5au64
    pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 16, 8)
    SetCJThread(pointer)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 16, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && unsafe {
        CPointer<CPointer<UInt8>>(record + 16).read(0).toUIntNative() == UIntNative(pointerBits)
    }
    unsafe { CPointer<CPointer<UInt8>>(record + 16).write(0, originalCJThread) }

    pointerBits = 0x10000500u64 + UInt64(threadIndex << 16) + 0x5au64
    pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 24, 8)
    SetSchedule(pointer)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 24, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && GetSchedule().toUIntNative() == UIntNative(pointerBits)
    unsafe { CPointer<CPointer<UInt8>>(record + 24).write(0, originalSchedule) }

    pointerBits = 0x40000000u64 + UInt64(threadIndex << 16) + 0x5au64
    pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    outsideBefore = ThreadLocalTLSABIHashOutside(record, 80, 8)
    let storedCache = SetThreadCache(pointer)
    outsideAfter = ThreadLocalTLSABIHashOutside(record, 80, 8)
    adjacent = adjacent && outsideBefore == outsideAfter
    helpers = helpers && storedCache.toUIntNative() == UIntNative(pointerBits) &&
        GetThreadCache().toUIntNative() == UIntNative(pointerBits)
    unsafe { ThreadLocalTLSABIBarrier() }
    let isolated = GetThreadCache().toUIntNative() == UIntNative(pointerBits)
    unsafe { ThreadLocalTLSABIBarrier() }
    unsafe { CPointer<CPointer<Unit>>(record + 80).write(0, originalCache) }

    let restored = ThreadLocalTLSABIHashOutside(record, 88, 0) == originalHash
    var result = if (helpers) { 1u64 } else { 0u64 }
    if (adjacent) { result |= 2u64 }
    if (restored) { result |= 4u64 }
    if (isolated) { result |= 8u64 }
    if (!threadLocalData.isNull()) { result |= 16u64 }
    return result
}

// Mutator/ThreadLocal.h:46-102. This test root reaches all 18 direct helpers
// and the ThreadLocal.cpp:56-100 static-assert alias without managed allocation.
@NoHeapAlloc
public func ThreadLocalDataNoHeapRoot(value: UIntNative): UIntNative {
    var pointerBits = value
    let pointer = unsafe { CPointer<CPointer<Unit>>(inout pointerBits).read(0) }
    MCC_CheckThreadLocalDataOffset()
    let address = unsafe { GetThreadLocalData().toUIntNative() }
    SetAllocBuffer(pointer)
    let buffer = unsafe { GetAllocBuffer().toUIntNative() }
    SetMutator(pointer)
    let mutator = unsafe { GetMutator().toUIntNative() }
    let preemptFlag = unsafe { GetPreemptFlag().toUIntNative() }
    SetProtectAddr(CPointer<UInt8>(pointer))
    SetThreadType(FP_THREAD)
    let threadType = UIntNative(GetThreadType())
    SetCJProcessorFlag(true)
    let processor = if (IsCJProcessor()) { 1u64 } else { 0u64 }
    SetForeignCJThread(pointer)
    let foreignThread = unsafe { GetForeignCJThread().toUIntNative() }
    SetCJThread(pointer)
    SetSchedule(pointer)
    let schedule = unsafe { GetSchedule().toUIntNative() }
    let storedCache = unsafe { SetThreadCache(pointer).toUIntNative() }
    let threadCache = unsafe { GetThreadCache().toUIntNative() }
    return address ^ buffer ^ mutator ^ preemptFlag ^ threadType ^ UIntNative(processor) ^
        foreignThread ^ schedule ^ storedCache ^ threadCache
}
