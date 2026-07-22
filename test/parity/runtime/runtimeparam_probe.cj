import rt.runtime.*

foreign {
    func memset(destination: CPointer<Unit>, value: Int32, count: UIntNative): CPointer<Unit>
    func write(fd: Int32, data: CPointer<UInt8>, size: UIntNative): IntNative
}

main(): Int64 {
    var value = RuntimeParam()
    unsafe { let _ = memset(CPointer<Unit>(CPointer<RuntimeParam>(inout value)), 0, sizeOf<RuntimeParam>()) }
    value.heapParam.regionSize = 0x0102030405060708
    value.heapParam.heapSize = 0x1112131415161718
    value.heapParam.exemptionThreshold = 0.25
    value.heapParam.heapUtilization = 0.5
    value.heapParam.heapGrowth = 0.75
    value.heapParam.allocationRate = 10240.0
    value.heapParam.allocationWaitTime = 0x2122232425262728
    value.gcParam.gcThreshold = 0x3132333435363738
    value.gcParam.garbageThreshold = 0.625
    value.gcParam.gcInterval = 0x4142434445464748
    value.gcParam.backupGCInterval = 0x5152535455565758
    value.gcParam.gcThreads = 0x61626364
    value.logParam.logLevel = 5
    value.coParam.thStackSize = 0x7172737475767778
    value.coParam.coStackSize = 0x8182838485868788
    value.coParam.processorNum = 0x91929394
    unsafe {
        let _ = write(1, CPointer<UInt8>(CPointer<RuntimeParam>(inout value)), sizeOf<RuntimeParam>())
    }

    return 0
}
