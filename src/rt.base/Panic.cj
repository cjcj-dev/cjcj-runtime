package rt.base

// Base/Log.h:270-275.
public func CHECK(condition: Bool, expression!: String = ""): Unit {
    if (!condition) {
        LOG(RTLOG_FATAL, "Check failed: ${expression}")
    }
}

// Base/Log.h:284-290.
public func CHECK_DETAIL(condition: Bool, message: String, expression!: String = ""): Unit {
    if (!condition) {
        LOG(RTLOG_FAIL, "Check failed: ${expression}")
        LOG(RTLOG_FATAL, message)
    }
}

// Base/Log.h:292-297.
public func CHECK_E(condition: Bool, message: String): Unit {
    if (condition) {
        LOG(RTLOG_ERROR, message)
    }
}

// Base/Panic.h:18-42. Debug-only assert (release is a no-op). C++ prepends __FILE__:__LINE__
// via PRINT_INFO then abort(); Cangjie has no __FILE__/__LINE__, so the descriptive message and
// the abort (through RTLOG_FATAL -> RtFatal) are preserved without the source-location prefix.
@When[debug]
public func MRT_ASSERT(condition: Bool, message: String): Unit {
    if (!condition) {
        LOG(RTLOG_FATAL, message)
    }
}
@When[!debug]
public func MRT_ASSERT(condition: Bool, message: String): Unit {
    let _ = condition
    let _ = message
}
