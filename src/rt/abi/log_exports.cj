package rt.abi

foreign func CJRT_BaseDumpLog(message: CPointer<UInt8>): Unit
foreign func CJRT_BaseCloseLogFiles(): Unit
foreign func CJRT_BaseSetLogFlags(): Unit
foreign func CJRT_BaseSetLogFlagWithEnv(env: CPointer<UInt8>, logType: Int32): Unit

// RuntimeConfig.h: extern "C" void MRT_DumpLog(const char* message)
@C
public func MRT_DumpLog(message: CPointer<UInt8>): Unit {
    unsafe { CJRT_BaseDumpLog(message) }
}

// Base/LogFile.h: static void MapleRuntime::LogFile::CloseLogFiles()
@C
public func _ZN12MapleRuntime7LogFile13CloseLogFilesEv(): Unit {
    unsafe { CJRT_BaseCloseLogFiles() }
}

// Base/LogFile.h: static void MapleRuntime::LogFile::SetFlags()
@C
public func _ZN12MapleRuntime7LogFile8SetFlagsEv(): Unit {
    unsafe { CJRT_BaseSetLogFlags() }
}

// Base/LogFile.h: static void LogFile::SetFlagWithEnv(const char* env, LogType type)
@C
public func _ZN12MapleRuntime7LogFile14SetFlagWithEnvEPKcNS_7LogTypeE(
    env: CPointer<UInt8>, logType: Int32
): Unit {
    unsafe { CJRT_BaseSetLogFlagWithEnv(env, logType) }
}
