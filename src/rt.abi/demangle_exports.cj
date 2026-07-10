package rt.abi

foreign func CJRT_Demangle(functionName: CPointer<UInt8>): CPointer<UInt8>

// Cangjie.h: MRT_EXPORT char* CJ_MRT_DemangleHandle(const char* functionName).
@C
public func CJ_MRT_DemangleHandle(functionName: CPointer<UInt8>): CPointer<UInt8> {
    return unsafe { CJRT_Demangle(functionName) }
}

// Compatibility entry points used by OHOS and older runtime consumers.
@C
public func CJ_MRT_Demangle(functionName: CPointer<UInt8>): CPointer<UInt8> {
    return unsafe { CJRT_Demangle(functionName) }
}

@C
public func MRT_DemangleHandle(functionName: CPointer<UInt8>): CPointer<UInt8> {
    return unsafe { CJRT_Demangle(functionName) }
}
