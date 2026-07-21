package rt.abi

foreign func CJRT_BaseParseNumFromEnv(env: CPointer<UInt8>): Int32
foreign func CJRT_BaseIsPosDecimal(env: CPointer<UInt8>): Bool
foreign func CJRT_BaseIsNumber(env: CPointer<UInt8>): Bool

// Base/CString.h: static int CString::ParseNumFromEnv(const CString& env)
@C
public func _ZN12MapleRuntime7CString15ParseNumFromEnvERKS0_(env: CPointer<UInt8>): Int32 {
    unsafe { CJRT_BaseParseNumFromEnv(env) }
}

// Base/CString.h: static bool CString::IsPosDecimal(const CString& env)
@C
public func _ZN12MapleRuntime7CString12IsPosDecimalERKS0_(env: CPointer<UInt8>): Bool {
    unsafe { CJRT_BaseIsPosDecimal(env) }
}

// Base/CString.h: static bool CString::IsNumber(const CString& env)
@C
public func _ZN12MapleRuntime7CString8IsNumberERKS0_(env: CPointer<UInt8>): Bool {
    unsafe { CJRT_BaseIsNumber(env) }
}
