// Cross-target ABI probe for Common/BaseObject.h:38 and Base/Log.h:388-394.
// It deliberately needs no target SDK headers, so clang can emit both Darwin
// and MinGW names from the exact C++ member signatures.
enum RTLogLevel : int {};

namespace MapleRuntime {
class BaseObject {
public:
    __SIZE_TYPE__ GetSize() const;
};

class Logger {
public:
    static Logger& GetLogger() noexcept;
    void FormatLog(::RTLogLevel level, bool notInSigHandler, const char* format, ...) noexcept;
};

__SIZE_TYPE__ BaseObject::GetSize() const { return 0; }
Logger& Logger::GetLogger() noexcept { __builtin_trap(); }
void Logger::FormatLog(::RTLogLevel, bool, const char*, ...) noexcept {}
} // namespace MapleRuntime
