package rt.base

// cangjie_runtime/runtime/src/Cangjie.h:175-185
public type RTLogLevel = Int32
public const RTLOG_VERBOSE: RTLogLevel = 0
public const RTLOG_DEBUG: RTLogLevel = 1
public const RTLOG_INFO: RTLogLevel = 2
public const RTLOG_REPORT: RTLogLevel = 3
public const RTLOG_WARNING: RTLogLevel = 4
public const RTLOG_ERROR: RTLogLevel = 5
public const RTLOG_FAIL: RTLogLevel = 6
public const RTLOG_FATAL: RTLogLevel = 7
public const RTLOG_OFF: RTLogLevel = 8

// cangjie_runtime/runtime/src/Base/LogFile.h:19-58
public type LogType = Int32
public const REPORT: LogType = 0
public const DEBUG: LogType = 1
public const ALLOC: LogType = 2
public const REGION: LogType = 3
public const FRAGMENT: LogType = 4
public const BARRIER: LogType = 5
public const EBARRIER: LogType = 6
public const TBARRIER: LogType = 7
public const PBARRIER: LogType = 8
public const FBARRIER: LogType = 9
public const GCPHASE: LogType = 10
public const ENUM: LogType = 11
public const TRACE: LogType = 12
public const PREFORWARD: LogType = 13
public const FORWARD: LogType = 14
public const FIX: LogType = 15
public const FINALIZE: LogType = 16
public const UNWIND: LogType = 17
public const EXCEPTION: LogType = 18
public const SIGNAL: LogType = 19
public const CJTHREAD: LogType = 20
public const LOG_TYPE_NUMBER: LogType = 21

foreign {
    func write(fd: Int32, data: CPointer<UInt8>, size: UIntNative): IntNative

    // TRANSITIONAL: cangjie_runtime/runtime/src/Base/Log.cpp:417-419 terminates RTLOG_FATAL with
    // std::abort(). Provided by the per-target Layer0 bridge: rt0/os/Linux/Panic.cpp (POSIX, also
    // serves Apple) and rt0/os/Windows/Panic.cpp (Windows).
    func RtFatal(message: CString): Unit
}

// Base/Log.h:32; Linux/POSIX slice of Log.cpp:341-419.
public func LOG(level: RTLogLevel, message: String): Unit {
    if (level < RTLOG_ERROR) {
        return
    }
    let levelName = if (level == RTLOG_ERROR) {
        "E"
    } else if (level == RTLOG_FAIL) {
        "F"
    } else {
        "F"
    }
    let line = "${levelName} ${message}"
    let cLine = unsafe { LibC.mallocCString(line) }
    if (level == RTLOG_FATAL) {
        unsafe { RtFatal(cLine) }
    } else {
        unsafe {
            let _ = write(2, cLine.getChars(), UIntNative(cLine.size()))
            let newline = LibC.mallocCString("\n")
            let _ = write(2, newline.getChars(), 1)
            LibC.free(newline)
            LibC.free(cLine)
        }
    }
}

// Base/LogFile.h:192-196. MRT_DEBUG maps to Cangjie's debug condition.
@When[debug]
public func DLOG(tag: LogType, message: String): Unit {
    let _ = tag
    LOG(RTLOG_DEBUG, message)
}

// Base/LogFile.h:192-196.
@When[!debug]
public func DLOG(tag: LogType, message: String): Unit {
    let _ = tag
    let _ = message
}
