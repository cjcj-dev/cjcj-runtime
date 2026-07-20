// CJThread schedule/include/schedule.h:294-298,332-342,903-914 and
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

extern "C" uintptr_t CJThreadSchdHookCallback0() { return 0x10u; }
extern "C" uintptr_t CJThreadSchdHookCallback1() { return 0x21u; }
extern "C" uintptr_t CJThreadSchdHookCallback2() { return 0x32u; }
extern "C" uintptr_t CJThreadSchdHookCallback3() { return 0x43u; }
extern "C" uintptr_t CJThreadSchdHookCallback4() { return 0x54u; }

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

extern "C" int32_t CJThreadSchdHookObserve(uint32_t stop, uint32_t createMutator,
    uint32_t destroyMutator, uint32_t preemptRequest, uint32_t newMutator,
    uint32_t hookButt, size_t aliasSize, size_t aliasAlign, uint32_t aliasSigned)
{
    using Underlying = std::underlying_type<CJThreadSchdHook>::type;
    const CJThreadSchdHook enumValues[] = {SCHD_STOP, SCHD_CREATE_MUTATOR,
        SCHD_DESTROY_MUTATOR, SCHD_PREEMPT_REQ, SCHD_NEW_MUTATOR, SCHD_HOOK_BUTT};
    const uint32_t values[] = {stop, createMutator, destroyMutator,
        preemptRequest, newMutator, hookButt};
    const char* names[] = {"SCHD_STOP", "SCHD_CREATE_MUTATOR",
        "SCHD_DESTROY_MUTATOR", "SCHD_PREEMPT_REQ", "SCHD_NEW_MUTATOR",
        "SCHD_HOOK_BUTT"};
    SchdCJThreadHookFunc callbacks[] = {CJThreadSchdHookCallback0,
        CJThreadSchdHookCallback1, CJThreadSchdHookCallback2,
        CJThreadSchdHookCallback3, CJThreadSchdHookCallback4};
    if (aliasSize != sizeof(uint32_t) || aliasAlign != alignof(uint32_t) ||
        aliasSigned != 0u || hookButt != 5u) {
        return 1;
    }
    for (size_t index = 0; index < 6; ++index) {
        if (static_cast<uint32_t>(enumValues[index]) != values[index] ||
            std::memcmp(&enumValues[index], &values[index], sizeof(CJThreadSchdHook)) != 0) {
            return 2;
        }
    }
    size_t distinctPairs = 0;
    for (size_t left = 0; left < 5; ++left) {
        for (size_t right = left + 1; right < 5; ++right) {
            distinctPairs += callbacks[left] != callbacks[right] ? 1u : 0u;
        }
    }
    if (distinctPairs != 10) {
        return 3;
    }

    ScheduleManager owner {};
    for (size_t index = 0; index < 5; ++index) {
        owner.schdCJThreadHook[static_cast<CJThreadSchdHook>(values[index])] = callbacks[index];
    }

    std::printf("CJTHREAD_SCHD_HOOK_REP enum_size=%zu enum_align=%zu "
        "enum_underlying_signed=%d alias_size=%zu alias_align=%zu alias_signed=%u\n",
        sizeof(CJThreadSchdHook), alignof(CJThreadSchdHook),
        std::is_signed<Underlying>::value ? 1 : 0, aliasSize, aliasAlign, aliasSigned);
    for (size_t index = 0; index < 6; ++index) {
        std::printf("CJTHREAD_SCHD_HOOK name=%s value=%u bytes=", names[index], values[index]);
        PrintBytes(enumValues[index]);
        std::puts("");
    }

    const auto* arrayAddress = reinterpret_cast<const unsigned char*>(&owner.schdCJThreadHook);
    const auto* firstSlotAddress = reinterpret_cast<const unsigned char*>(&owner.schdCJThreadHook[0]);
    std::printf("CJTHREAD_SCHD_HOOK_OWNER sizeof=%zu align=%zu array_offset=%zu "
        "array_size=%zu array_align=%zu element_size=%zu element_align=%zu "
        "element_count=%zu owner_field_address_match=%d distinct_callback_pairs=%zu\n",
        sizeof(ScheduleManager), alignof(ScheduleManager),
        offsetof(ScheduleManager, schdCJThreadHook), sizeof(owner.schdCJThreadHook),
        alignof(decltype(ScheduleManager::schdCJThreadHook)),
        sizeof(owner.schdCJThreadHook[0]), alignof(decltype(owner.schdCJThreadHook[0])),
        sizeof(owner.schdCJThreadHook) / sizeof(owner.schdCJThreadHook[0]),
        arrayAddress == firstSlotAddress ? 1 : 0, distinctPairs);
    for (size_t index = 0; index < 5; ++index) {
        const auto* slotAddress = reinterpret_cast<const unsigned char*>(&owner.schdCJThreadHook[index]);
        const size_t slotOffset = static_cast<size_t>(slotAddress - arrayAddress);
        const size_t stride = index == 0 ? 0u : static_cast<size_t>(slotAddress -
            reinterpret_cast<const unsigned char*>(&owner.schdCJThreadHook[index - 1]));
        const int match = owner.schdCJThreadHook[index] == callbacks[index] ? 1 : 0;
        std::printf("CJTHREAD_SCHD_HOOK_SLOT name=%s index=%zu slot_offset=%zu "
            "stride_from_previous=%zu callback_identity=%zu callback_match=%d\n",
            names[index], index, slotOffset, stride, index, match);
        if (slotOffset != index * sizeof(SchdCJThreadHookFunc) || match != 1) {
            return 4;
        }
    }
    return 0;
}

#ifdef CJTHREAD_SCHD_HOOK_CPP_ORACLE
int main()
{
    return CJThreadSchdHookObserve(SCHD_STOP, SCHD_CREATE_MUTATOR,
        SCHD_DESTROY_MUTATOR, SCHD_PREEMPT_REQ, SCHD_NEW_MUTATOR,
        SCHD_HOOK_BUTT, sizeof(uint32_t), alignof(uint32_t),
        std::is_signed<uint32_t>::value ? 1u : 0u);
}
#endif
