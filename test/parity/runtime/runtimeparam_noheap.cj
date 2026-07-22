package rt.runtime

// Production-root surrogate for the by-value configuration path. Keeping the
// root in the package lets the pre-opt graph prove all nested value constructors.
@NoHeapAlloc
public func RuntimeParamNoHeapRoot(): UInt64 {
    let value = RuntimeParam()
    return UInt64(value.heapParam.regionSize) + UInt64(value.gcParam.gcThreshold) +
        UInt64(value.logParam.logLevel) + UInt64(value.coParam.processorNum)
}
