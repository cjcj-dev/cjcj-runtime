#ifndef CJRT_PARITY_CANGJIE_RUNTIME_STUB_H
#define CJRT_PARITY_CANGJIE_RUNTIME_STUB_H

namespace MapleRuntime {
enum class StackGrowConfig {
    UNDEF = 0,
    STACK_GROW_OFF = 1,
    STACK_GROW_ON = 2,
};

class CangjieRuntime {
public:
    static StackGrowConfig stackGrowConfig;
};
} // namespace MapleRuntime

#endif
