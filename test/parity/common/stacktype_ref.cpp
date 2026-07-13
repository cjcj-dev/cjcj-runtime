// Common/StackType.h:25-73,83-98 and Common/TypeDef.h:36-40 executable ABI oracle.
#include "Common/StackType.h"

#include <cstddef>
#include <cstdint>
#include <iostream>
#include <type_traits>

using namespace MapleRuntime;

// Common/StackType.h:62-73,84-97. Dump every byte of each zero-initialized POD.
template <typename T>
static void DumpBytes(const char* name, const T& value)
{
    const auto* bytes = reinterpret_cast<const unsigned char*>(&value);
    std::cout << "BYTES " << name;
    for (size_t i = 0; i < sizeof(T); ++i) {
        std::cout << ' ' << static_cast<unsigned int>(bytes[i]);
    }
    std::cout << '\n';
}

// Common/StackType.h:25-73,83-98. Compute constants, layout, offsets, and bytes from the real header.
int main()
{
    static_assert(sizeof(FrameType) == 4 && alignof(FrameType) == 4, "FrameType ABI");
    static_assert(sizeof(StackMode) == 4 && alignof(StackMode) == 4, "StackMode ABI");
    static_assert(sizeof(UnwindContextStatus) == 4 && alignof(UnwindContextStatus) == 4,
        "UnwindContextStatus ABI");
    static_assert(sizeof(FrameAddress) == 16 && alignof(FrameAddress) == 8, "FrameAddress ABI");
    static_assert(offsetof(FrameAddress, callerFrameAddress) == 0 &&
        offsetof(FrameAddress, returnAddress) == 8, "FrameAddress offsets");
    static_assert(sizeof(N2CSlotData) == 24 && alignof(N2CSlotData) == 8, "N2CSlotData ABI");
    static_assert(offsetof(N2CSlotData, pc) == 0 && offsetof(N2CSlotData, fa) == 8 &&
        offsetof(N2CSlotData, status) == 16, "N2CSlotData offsets");
    static_assert(sizeof(StackTraceData) == 32 && alignof(StackTraceData) == 8, "StackTraceData ABI");
    static_assert(offsetof(StackTraceData, className) == 0 && offsetof(StackTraceData, methodName) == 8 &&
        offsetof(StackTraceData, fileName) == 16 && offsetof(StackTraceData, lineNumber) == 24,
        "StackTraceData offsets");
    static_assert(sizeof(ThreadSnapshot) == 32 && alignof(ThreadSnapshot) == 8, "ThreadSnapshot ABI");
    static_assert(offsetof(ThreadSnapshot, name) == 0 && offsetof(ThreadSnapshot, id) == 8 &&
        offsetof(ThreadSnapshot, stackTrace) == 16 && offsetof(ThreadSnapshot, state) == 24,
        "ThreadSnapshot offsets");

    std::cout << "CONST STACK_UNWIND_STEP_MAX " << STACK_UNWIND_STEP_MAX << '\n';
    std::cout << "ENUM FrameType UNKNOWN " << static_cast<int32_t>(FrameType::UNKNOWN) << '\n';
    std::cout << "ENUM FrameType MANAGED " << static_cast<int32_t>(FrameType::MANAGED) << '\n';
    std::cout << "ENUM FrameType N2C_STUB " << static_cast<int32_t>(FrameType::N2C_STUB) << '\n';
    std::cout << "ENUM FrameType C2N_STUB " << static_cast<int32_t>(FrameType::C2N_STUB) << '\n';
    std::cout << "ENUM FrameType RUNTIME " << static_cast<int32_t>(FrameType::RUNTIME) << '\n';
    std::cout << "ENUM FrameType SAFEPOINT " << static_cast<int32_t>(FrameType::SAFEPOINT) << '\n';
    std::cout << "ENUM FrameType C2R_STUB " << static_cast<int32_t>(FrameType::C2R_STUB) << '\n';
    std::cout << "ENUM FrameType NATIVE " << static_cast<int32_t>(FrameType::NATIVE) << '\n';
    std::cout << "ENUM FrameType STACKGROW " << static_cast<int32_t>(FrameType::STACKGROW) << '\n';
    std::cout << "ENUM FrameType EXSLUSIVE " << static_cast<int32_t>(FrameType::EXSLUSIVE) << '\n';
    std::cout << "ENUM StackMode EH " << static_cast<int32_t>(StackMode::EH) << '\n';
    std::cout << "ENUM StackMode GC " << static_cast<int32_t>(StackMode::GC) << '\n';
    std::cout << "ENUM StackMode PRINT " << static_cast<int32_t>(StackMode::PRINT) << '\n';
    std::cout << "ENUM UnwindContextStatus UNKNOWN "
              << static_cast<int32_t>(UnwindContextStatus::UNKNOWN) << '\n';
    std::cout << "ENUM UnwindContextStatus RELIABLE "
              << static_cast<int32_t>(UnwindContextStatus::RELIABLE) << '\n';
    std::cout << "ENUM UnwindContextStatus RISKY "
              << static_cast<int32_t>(UnwindContextStatus::RISKY) << '\n';
    std::cout << "ENUM UnwindContextStatus SIGNAL_STATUS "
              << static_cast<int32_t>(UnwindContextStatus::SIGNAL_STATUS) << '\n';

    std::cout << "LAYOUT FrameType " << sizeof(FrameType) << ' ' << alignof(FrameType) << '\n';
    std::cout << "LAYOUT StackMode " << sizeof(StackMode) << ' ' << alignof(StackMode) << '\n';
    std::cout << "LAYOUT UnwindContextStatus " << sizeof(UnwindContextStatus) << ' '
              << alignof(UnwindContextStatus) << '\n';
    std::cout << "LAYOUT FrameAddress " << sizeof(FrameAddress) << ' ' << alignof(FrameAddress) << ' '
              << offsetof(FrameAddress, callerFrameAddress) << ' ' << offsetof(FrameAddress, returnAddress) << '\n';
    std::cout << "LAYOUT N2CSlotData " << sizeof(N2CSlotData) << ' ' << alignof(N2CSlotData) << ' '
              << offsetof(N2CSlotData, pc) << ' ' << offsetof(N2CSlotData, fa) << ' '
              << offsetof(N2CSlotData, status) << '\n';
    std::cout << "LAYOUT StackTraceData " << sizeof(StackTraceData) << ' ' << alignof(StackTraceData) << ' '
              << offsetof(StackTraceData, className) << ' ' << offsetof(StackTraceData, methodName) << ' '
              << offsetof(StackTraceData, fileName) << ' ' << offsetof(StackTraceData, lineNumber) << '\n';
    std::cout << "LAYOUT ThreadSnapshot " << sizeof(ThreadSnapshot) << ' ' << alignof(ThreadSnapshot) << ' '
              << offsetof(ThreadSnapshot, name) << ' ' << offsetof(ThreadSnapshot, id) << ' '
              << offsetof(ThreadSnapshot, stackTrace) << ' ' << offsetof(ThreadSnapshot, state) << '\n';

    FrameAddress frameAddress{};
    frameAddress.callerFrameAddress = reinterpret_cast<FrameAddress*>(UINT64_C(0x1122334455667788));
    frameAddress.returnAddress = reinterpret_cast<const uint32_t*>(UINT64_C(0x2233445566778899));
    DumpBytes("FrameAddress", frameAddress);

    N2CSlotData n2cSlotData{};
    n2cSlotData.pc = reinterpret_cast<const uint32_t*>(UINT64_C(0x33445566778899aa));
    n2cSlotData.fa = reinterpret_cast<FrameAddress*>(UINT64_C(0x445566778899aabb));
    n2cSlotData.status = UnwindContextStatus::RISKY;
    DumpBytes("N2CSlotData", n2cSlotData);

    StackTraceData stackTraceData{};
    stackTraceData.className = reinterpret_cast<ArrayRef>(UINT64_C(0x0102030405060708));
    stackTraceData.methodName = reinterpret_cast<ArrayRef>(UINT64_C(0x1112131415161718));
    stackTraceData.fileName = reinterpret_cast<ArrayRef>(UINT64_C(0x2122232425262728));
    stackTraceData.lineNumber = -INT64_C(0x0102030405060708);
    DumpBytes("StackTraceData", stackTraceData);

    ThreadSnapshot threadSnapshot{};
    threadSnapshot.name = reinterpret_cast<ArrayRef>(UINT64_C(0x3132333435363738));
    threadSnapshot.id = -INT64_C(0x1112131415161718);
    threadSnapshot.stackTrace = reinterpret_cast<ArrayRef>(UINT64_C(0x4142434445464748));
    threadSnapshot.state = INT64_C(0x5152535455565758);
    DumpBytes("ThreadSnapshot", threadSnapshot);
    return 0;
}
