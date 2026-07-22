package rt.runtime

foreign {
    // Common/Runtime.h:36-42,106 and CangjieRuntime.cpp:95. This is the existing
    // C++ singleton data symbol; it is not a new bridge ABI.
    let _ZN12MapleRuntime7Runtime7runtimeE: CPointer<Unit>

    // CangjieRuntime.h:49. The C++ member returns RuntimeParam by value. A
    // foreign function whose first explicit argument is `this` has the same
    // target ABI (including the target-selected aggregate return convention).
    func _ZNK12MapleRuntime14CangjieRuntime15GetRuntimeParamEv(
        runtime: CPointer<Unit>): RuntimeParam
}

// Cangjie.h:194-246. All public configuration records are C ABI values and
// remain allocation-free when copied by the allocator policy.
@C
public struct HeapParam {
    public var regionSize: UIntNative
    public var heapSize: UIntNative
    public var exemptionThreshold: Float64
    public var heapUtilization: Float64
    public var heapGrowth: Float64
    public var allocationRate: Float64
    public var allocationWaitTime: UIntNative

    public init() {
        regionSize = 0
        heapSize = 0
        exemptionThreshold = 0.0
        heapUtilization = 0.0
        heapGrowth = 0.0
        allocationRate = 0.0
        allocationWaitTime = 0
    }
}

// Cangjie.h:256-296.
@C
public struct GCParam {
    public var gcThreshold: UIntNative
    public var garbageThreshold: Float64
    public var gcInterval: UInt64
    public var backupGCInterval: UInt64
    public var gcThreads: Int32

    public init() {
        gcThreshold = 0
        garbageThreshold = 0.0
        gcInterval = 0
        backupGCInterval = 0
        gcThreads = 0
    }
}

// Cangjie.h:303-307. RTLogLevel has the C enum ABI, i.e. one Int32 field on
// every supported target.
@C
public struct LogParam {
    public var logLevel: Int32

    public init() {
        logLevel = 0
    }
}

// Cangjie.h:311-329.
@C
public struct ConcurrencyParam {
    public var thStackSize: UIntNative
    public var coStackSize: UIntNative
    public var processorNum: UInt32

    public init() {
        thStackSize = 0
        coStackSize = 0
        processorNum = 0
    }
}

// Cangjie.h:336-341.
@C
public struct RuntimeParam {
    public var heapParam: HeapParam
    public var gcParam: GCParam
    public var logParam: LogParam
    public var coParam: ConcurrencyParam

    public init() {
        heapParam = HeapParam()
        gcParam = GCParam()
        logParam = LogParam()
        coParam = ConcurrencyParam()
    }
}

// CangjieRuntime.h:36,46-49. These functions deliberately preserve the
// original by-value copies. Callers have the same initialized-runtime
// precondition as Runtime::Current().
@NoHeapAlloc
public func GetRuntimeParam(): RuntimeParam {
    return unsafe {
        _ZNK12MapleRuntime14CangjieRuntime15GetRuntimeParamEv(
            _ZN12MapleRuntime7Runtime7runtimeE)
    }
}

@NoHeapAlloc
public func GetHeapParam(): HeapParam {
    return GetRuntimeParam().heapParam
}

@NoHeapAlloc
public func GetGCParam(): GCParam {
    return GetRuntimeParam().gcParam
}

@NoHeapAlloc
public func GetLogParam(): LogParam {
    return GetRuntimeParam().logParam
}

@NoHeapAlloc
public func GetConcurrencyParam(): ConcurrencyParam {
    return GetRuntimeParam().coParam
}
