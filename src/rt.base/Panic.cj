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
