// CJThread schedule/include/schedule.h:423-430,839 and
// schedule/include/inner/schedule_impl.h:245-258. Linux x86_64 oracle only.
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <type_traits>

#include "schedule.h"
#include "schedule_impl.h"

size_t g_pageSize = 0;
void LogWrite(ThreadLogLevel, unsigned int, const char*, unsigned short, const char*, ...) {}

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

extern "C" int32_t ScheduleTypeObserve(uint32_t scheduleDefault, uint32_t uiThread,
    uint32_t foreignThread, uint32_t exclusive, size_t aliasSize, size_t aliasAlign,
    uint32_t aliasSigned)
{
    using Underlying = std::underlying_type<ScheduleType>::type;
    const ScheduleType enumValues[] = {SCHEDULE_DEFAULT, SCHEDULE_UI_THREAD,
        SCHEDULE_FOREIGN_THREAD, SCHEDULE_EXCLUSIVE};
    const uint32_t values[] = {scheduleDefault, uiThread, foreignThread, exclusive};
    const char* names[] = {"SCHEDULE_DEFAULT", "SCHEDULE_UI_THREAD",
        "SCHEDULE_FOREIGN_THREAD", "SCHEDULE_EXCLUSIVE"};
    if (aliasSize != sizeof(uint32_t) || aliasAlign != alignof(uint32_t) || aliasSigned != 0u) {
        return 1;
    }
    for (size_t index = 0; index < 4; ++index) {
        if (static_cast<uint32_t>(enumValues[index]) != values[index] ||
            std::memcmp(&enumValues[index], &values[index], sizeof(ScheduleType)) != 0) {
            return 2;
        }
    }

    std::printf("SCHEDULE_TYPE_REP enum_size=%zu enum_align=%zu enum_underlying_signed=%d "
        "alias_size=%zu alias_align=%zu alias_signed=%u\n", sizeof(ScheduleType),
        alignof(ScheduleType), std::is_signed<Underlying>::value ? 1 : 0,
        aliasSize, aliasAlign, aliasSigned);
    for (size_t index = 0; index < 4; ++index) {
        std::printf("SCHEDULE_TYPE name=%s value=%u bytes=", names[index], values[index]);
        PrintBytes(enumValues[index]);
        std::puts("");
    }

    std::printf("SCHEDULE_OWNER sizeof=%zu align=%zu field_offset=%zu field_size=%zu "
        "field_align=%zu field_signed=%d\n", sizeof(Schedule), alignof(Schedule),
        offsetof(Schedule, scheduleType), sizeof(Schedule::scheduleType),
        alignof(decltype(Schedule::scheduleType)), std::is_signed<Underlying>::value ? 1 : 0);
    for (size_t index = 0; index < 4; ++index) {
        Schedule owner {};
        owner.scheduleType = static_cast<ScheduleType>(values[index]);
        std::printf("SCHEDULE_OWNER_FIELD name=%s value=%u bytes=", names[index], values[index]);
        PrintBytes(owner.scheduleType);
        std::puts("");
    }
    return 0;
}

#ifdef SCHEDULE_TYPE_CPP_ORACLE
int main()
{
    return ScheduleTypeObserve(SCHEDULE_DEFAULT, SCHEDULE_UI_THREAD,
        SCHEDULE_FOREIGN_THREAD, SCHEDULE_EXCLUSIVE, sizeof(uint32_t),
        alignof(uint32_t), std::is_signed<uint32_t>::value ? 1u : 0u);
}
#endif
