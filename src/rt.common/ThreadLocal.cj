package rt.common

// RuntimeConfig.h:34 and Mutator/Mutator.cpp:28-40. The Layer0 ABI owns the live
// thread-local record and returns its address as uintptr_t. The value is kept
// unchanged because AArch64 may encode the GC phase in its top byte under TBI.
@FastNative
foreign func MRT_GetThreadLocalData(): UIntNative

// Mutator/ThreadLocal.cpp:56-100. This exported alias reaches the native
// static_assert anchor; the Cangjie package only imports it.
foreign func CJ_MCC_CheckThreadLocalDataOffset(): Unit

// Mutator/ThreadLocal.h:18. C++ scoped enums use signed four-byte storage.
public type ThreadType = Int32

// Mutator/ThreadLocal.h:18.
public const CJ_PROCESSOR: ThreadType = 0
public const GC_THREAD: ThreadType = 1
public const FP_THREAD: ThreadType = 2
public const HOT_UPDATE_THREAD: ThreadType = 3

// Mutator/ThreadLocal.h:22-37. This is the native descriptor only; the storage
// remains the C++ runtime-owned thread_local object in ThreadLocal.cpp:16-22.
@C
public struct ThreadLocalData {
    public var buffer: CPointer<Unit>
    public var mutator: CPointer<Unit>
    public var cjthread: CPointer<UInt8>
    public var schedule: CPointer<UInt8>
    public var preemptFlag: CPointer<UInt8>
    public var protectAddr: CPointer<UInt8>
    public var safepointState: UInt64
    public var tid: UInt64
    public var foreignCJThread: CPointer<Unit>
    public var threadType: ThreadType
    public var isCJProcessor: Bool
    public var threadCache: CPointer<Unit>

    // Mutator/ThreadLocal.h:22-37. Aggregate initialisation follows the complete
    // native field order; live TLS access never constructs or copies this value.
    public init(buffer: CPointer<Unit>, mutator: CPointer<Unit>, cjthread: CPointer<UInt8>,
        schedule: CPointer<UInt8>, preemptFlag: CPointer<UInt8>, protectAddr: CPointer<UInt8>,
        safepointState: UInt64, tid: UInt64, foreignCJThread: CPointer<Unit>,
        threadType: ThreadType, isCJProcessor: Bool, threadCache: CPointer<Unit>) {
        unsafe {
            this.buffer = buffer
            this.mutator = mutator
            this.cjthread = cjthread
            this.schedule = schedule
            this.preemptFlag = preemptFlag
            this.protectAddr = protectAddr
        }
        this.safepointState = safepointState
        this.tid = tid
        unsafe { this.foreignCJThread = foreignCJThread }
        this.threadType = threadType
        this.isCJProcessor = isCJProcessor
        unsafe { this.threadCache = threadCache }
    }
}

// Mutator/ThreadLocal.cpp:56-100. Expose the native static-assert alias without
// defining either runtime symbol.
public func MCC_CheckThreadLocalDataOffset(): Unit {
    unsafe { CJ_MCC_CheckThreadLocalDataOffset() }
}

// Mutator/ThreadLocal.h:46 and ThreadLocal.cpp:19-22, via the existing public
// RuntimeConfig.h:34 ABI. The uintptr_t bits are preserved without TBI masking.
public func GetThreadLocalData(): CPointer<ThreadLocalData> {
    var threadLocalDataAddress = unsafe { MRT_GetThreadLocalData() }
    return unsafe { CPointer<CPointer<ThreadLocalData>>(inout threadLocalDataAddress).read(0) }
}

// Mutator/ThreadLocal.h:49. mutator is the pointer-width field at byte 8.
public func SetMutator(newMutator: CPointer<Unit>): Unit {
    unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(GetThreadLocalData()) + 8).write(0, newMutator) }
}

// Mutator/ThreadLocal.h:51. mutator is the pointer-width field at byte 8.
public func GetMutator(): CPointer<Unit> {
    return unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(GetThreadLocalData()) + 8).read(0) }
}

// Mutator/ThreadLocal.h:53. buffer is the pointer-width field at byte 0.
public func GetAllocBuffer(): CPointer<Unit> {
    return unsafe { CPointer<CPointer<Unit>>(GetThreadLocalData()).read(0) }
}

// Mutator/ThreadLocal.h:55. buffer is the pointer-width field at byte 0.
public func SetAllocBuffer(buffer: CPointer<Unit>): Unit {
    unsafe { CPointer<CPointer<Unit>>(GetThreadLocalData()).write(0, buffer) }
}

// Mutator/ThreadLocal.h:57. preemptFlag is the pointer-width field at byte 32.
public func GetPreemptFlag(): CPointer<UInt8> {
    return unsafe { CPointer<CPointer<UInt8>>(CPointer<UInt8>(GetThreadLocalData()) + 32).read(0) }
}

// Mutator/ThreadLocal.h:59. protectAddr is the pointer-width field at byte 40.
public func SetProtectAddr(addr: CPointer<UInt8>): Unit {
    unsafe { CPointer<CPointer<UInt8>>(CPointer<UInt8>(GetThreadLocalData()) + 40).write(0, addr) }
}

// Mutator/ThreadLocal.h:61. threadType is the signed four-byte field at byte 72.
public func SetThreadType(threadType: ThreadType): Unit {
    unsafe { CPointer<ThreadType>(CPointer<UInt8>(GetThreadLocalData()) + 72).write(0, threadType) }
}

// Mutator/ThreadLocal.h:63. threadType is the signed four-byte field at byte 72.
public func GetThreadType(): ThreadType {
    return unsafe { CPointer<ThreadType>(CPointer<UInt8>(GetThreadLocalData()) + 72).read(0) }
}

// Mutator/ThreadLocal.h:65. C++ bool is the one-byte field at byte 76.
public func SetCJProcessorFlag(flag: Bool): Unit {
    unsafe { CPointer<Bool>(CPointer<UInt8>(GetThreadLocalData()) + 76).write(0, flag) }
}

// Mutator/ThreadLocal.h:67. C++ bool is the one-byte field at byte 76.
public func IsCJProcessor(): Bool {
    return unsafe { CPointer<Bool>(CPointer<UInt8>(GetThreadLocalData()) + 76).read(0) }
}

// Mutator/ThreadLocal.h:69-72. foreignCJThread is the pointer-width field at byte 64.
public func SetForeignCJThread(cjthread: CPointer<Unit>): Unit {
    unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(GetThreadLocalData()) + 64).write(0, cjthread) }
}

// Mutator/ThreadLocal.h:74-77. foreignCJThread is the pointer-width field at byte 64.
public func GetForeignCJThread(): CPointer<Unit> {
    return unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(GetThreadLocalData()) + 64).read(0) }
}

// Mutator/ThreadLocal.h:79-82. cjthread is the pointer-width field at byte 16.
public func SetCJThread(cjthread: CPointer<Unit>): Unit {
    unsafe {
        CPointer<CPointer<UInt8>>(CPointer<UInt8>(GetThreadLocalData()) + 16).write(0,
            CPointer<UInt8>(cjthread))
    }
}

// Mutator/ThreadLocal.h:84-87. schedule is the pointer-width field at byte 24.
public func GetSchedule(): CPointer<Unit> {
    let schedule = unsafe {
        CPointer<CPointer<UInt8>>(CPointer<UInt8>(GetThreadLocalData()) + 24).read(0)
    }
    return unsafe { CPointer<Unit>(schedule) }
}

// Mutator/ThreadLocal.h:89-92. schedule is the pointer-width field at byte 24.
public func SetSchedule(schedule: CPointer<Unit>): Unit {
    unsafe {
        CPointer<CPointer<UInt8>>(CPointer<UInt8>(GetThreadLocalData()) + 24).write(0,
            CPointer<UInt8>(schedule))
    }
}

// Mutator/ThreadLocal.h:94-97. threadCache is the pointer-width field at byte 80.
public func GetThreadCache(): CPointer<Unit> {
    return unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(GetThreadLocalData()) + 80).read(0) }
}

// Mutator/ThreadLocal.h:99-102. Assignment returns the stored pointer.
public func SetThreadCache(threadCache: CPointer<Unit>): CPointer<Unit> {
    unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(GetThreadLocalData()) + 80).write(0, threadCache) }
    return threadCache
}
