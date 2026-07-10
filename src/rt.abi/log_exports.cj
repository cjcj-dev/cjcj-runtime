package rt.abi

foreign func CJRT_BaseDumpLog(message: CPointer<UInt8>): Unit

// RuntimeConfig.h: extern "C" void MRT_DumpLog(const char* message)
@C
public func MRT_DumpLog(message: CPointer<UInt8>): Unit {
    unsafe { CJRT_BaseDumpLog(message) }
}
