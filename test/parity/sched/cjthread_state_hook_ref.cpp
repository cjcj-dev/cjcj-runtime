// CJThread schedule/include/schedule.h:300-304,344-353,916-927 and
// schedule/include/inner/schedule_impl.h:178-223. Linux x86_64 oracle only.
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <type_traits>

#include "schedule.h"
#include "schedule_impl.h"

size_t g_pageSize = 0;
void LogWrite(ThreadLogLevel, unsigned int, const char*, unsigned short, const char*, ...) {}

extern "C" uintptr_t CJThreadStateHookCallback0(void*) { return 0x10u; }
extern "C" uintptr_t CJThreadStateHookCallback1(void*) { return 0x21u; }
extern "C" uintptr_t CJThreadStateHookCallback2(void*) { return 0x32u; }
extern "C" uintptr_t CJThreadStateHookCallback3(void*) { return 0x43u; }

namespace {
template <class T>
void PrintBytes(const T& value)
{
    const auto* bytes = reinterpret_cast<const unsigned char*>(&value);
    for (size_t index = 0; index < sizeof(value); ++index) {
        std::printf("%02x", static_cast<unsigned>(bytes[index]));
    }
}
} // namespace

extern "C" int32_t CJThreadStateHookObserve(uint32_t beforePark, uint32_t afterPark,
    uint32_t beforeResched, uint32_t afterResched, uint32_t hookButt,
    size_t aliasSize, size_t aliasAlign, uint32_t aliasSigned)
{
    using Underlying = std::underlying_type<CJThreadStateHook>::type;
    const CJThreadStateHook enumValues[] = {CJTHREAD_BEFORE_PARK, CJTHREAD_AFTER_PARK,
        CJTHREAD_BEFORE_RESCHED, CJTHREAD_AFTER_RESCHED, CJTHREAD_STATE_HOOK_BUTT};
    const uint32_t values[] = {beforePark, afterPark, beforeResched, afterResched, hookButt};
    const char* names[] = {"CJTHREAD_BEFORE_PARK", "CJTHREAD_AFTER_PARK",
        "CJTHREAD_BEFORE_RESCHED", "CJTHREAD_AFTER_RESCHED", "CJTHREAD_STATE_HOOK_BUTT"};
    SchdCJThreadStateHookFunc callbacks[] = {CJThreadStateHookCallback0,
        CJThreadStateHookCallback1, CJThreadStateHookCallback2, CJThreadStateHookCallback3};
    if (aliasSize != sizeof(uint32_t) || aliasAlign != alignof(uint32_t) ||
        aliasSigned != 0u || hookButt != 4u) {
        return 1;
    }
    for (size_t index = 0; index < 5; ++index) {
        if (static_cast<uint32_t>(enumValues[index]) != values[index] ||
            std::memcmp(&enumValues[index], &values[index], sizeof(CJThreadStateHook)) != 0) {
            return 2;
        }
    }
    size_t distinctPairs = 0;
    for (size_t left = 0; left < 4; ++left) {
        for (size_t right = left + 1; right < 4; ++right) {
            distinctPairs += callbacks[left] != callbacks[right] ? 1u : 0u;
        }
    }
    if (distinctPairs != 6) {
        return 3;
    }

    ScheduleManager owner {};
    for (size_t index = 0; index < 4; ++index) {
        owner.schdCJThreadStateHook[static_cast<CJThreadStateHook>(values[index])] = callbacks[index];
    }

    std::printf("CJTHREAD_STATE_HOOK_REP enum_size=%zu enum_align=%zu "
        "enum_underlying_signed=%d alias_size=%zu alias_align=%zu alias_signed=%u\n",
        sizeof(CJThreadStateHook), alignof(CJThreadStateHook),
        std::is_signed<Underlying>::value ? 1 : 0, aliasSize, aliasAlign, aliasSigned);
    for (size_t index = 0; index < 5; ++index) {
        std::printf("CJTHREAD_STATE_HOOK name=%s value=%u bytes=", names[index], values[index]);
        PrintBytes(enumValues[index]);
        std::puts("");
    }

    const auto* arrayAddress = reinterpret_cast<const unsigned char*>(&owner.schdCJThreadStateHook);
    const auto* firstSlotAddress = reinterpret_cast<const unsigned char*>(&owner.schdCJThreadStateHook[0]);
    std::printf("CJTHREAD_STATE_HOOK_OWNER sizeof=%zu align=%zu array_offset=%zu "
        "array_size=%zu array_align=%zu element_size=%zu element_align=%zu "
        "element_count=%zu owner_field_address_match=%d distinct_callback_pairs=%zu\n",
        sizeof(ScheduleManager), alignof(ScheduleManager),
        offsetof(ScheduleManager, schdCJThreadStateHook), sizeof(owner.schdCJThreadStateHook),
        alignof(decltype(ScheduleManager::schdCJThreadStateHook)),
        sizeof(owner.schdCJThreadStateHook[0]), alignof(decltype(owner.schdCJThreadStateHook[0])),
        sizeof(owner.schdCJThreadStateHook) / sizeof(owner.schdCJThreadStateHook[0]),
        arrayAddress == firstSlotAddress ? 1 : 0, distinctPairs);
    for (size_t index = 0; index < 4; ++index) {
        const auto* slotAddress = reinterpret_cast<const unsigned char*>(&owner.schdCJThreadStateHook[index]);
        const size_t slotOffset = static_cast<size_t>(slotAddress - arrayAddress);
        const size_t stride = index == 0 ? 0u : static_cast<size_t>(slotAddress -
            reinterpret_cast<const unsigned char*>(&owner.schdCJThreadStateHook[index - 1]));
        const int match = owner.schdCJThreadStateHook[index] == callbacks[index] ? 1 : 0;
        std::printf("CJTHREAD_STATE_HOOK_SLOT name=%s index=%zu slot_offset=%zu "
            "stride_from_previous=%zu callback_identity=%zu callback_match=%d\n",
            names[index], index, slotOffset, stride, index, match);
        if (slotOffset != index * sizeof(SchdCJThreadStateHookFunc) || match != 1) {
            return 4;
        }
    }
    return 0;
}

#ifdef CJTHREAD_STATE_HOOK_CPP_ORACLE
int main()
{
    return CJThreadStateHookObserve(CJTHREAD_BEFORE_PARK, CJTHREAD_AFTER_PARK,
        CJTHREAD_BEFORE_RESCHED, CJTHREAD_AFTER_RESCHED, CJTHREAD_STATE_HOOK_BUTT,
        sizeof(uint32_t), alignof(uint32_t), std::is_signed<uint32_t>::value ? 1u : 0u);
}
#endif
