// CJThread schedule/include/schedule.h:403-410,624-626,646-648.
// Linux x86_64 representation oracle against the real header only.
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <type_traits>

#include "schedule.h"

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

extern "C" int32_t CJThreadCreateSourceObserve(uint32_t sourceDefault, uint32_t signal,
    uint32_t finalizer, size_t aliasSize, size_t aliasAlign, uint32_t aliasSigned)
{
    using Underlying = std::underlying_type<CJThreadCreateSource>::type;
    const CJThreadCreateSource enumValues[] = {CJTHREAD_CREATE_SOURCE_DEFAULT,
        CJTHREAD_CREATE_SOURCE_SIGNAL, CJTHREAD_CREATE_SOURCE_FINALIZER};
    const uint32_t values[] = {sourceDefault, signal, finalizer};
    const char* names[] = {"CJTHREAD_CREATE_SOURCE_DEFAULT", "CJTHREAD_CREATE_SOURCE_SIGNAL",
        "CJTHREAD_CREATE_SOURCE_FINALIZER"};
    if (aliasSize != sizeof(uint32_t) || aliasAlign != alignof(uint32_t) || aliasSigned != 0u) {
        return 1;
    }
    for (size_t index = 0; index < 3; ++index) {
        if (static_cast<uint32_t>(enumValues[index]) != values[index] ||
            std::memcmp(&enumValues[index], &values[index], sizeof(CJThreadCreateSource)) != 0) {
            return 2;
        }
    }

    std::printf("CJTHREAD_CREATE_SOURCE_REP enum_size=%zu enum_align=%zu "
        "enum_underlying_signed=%d alias_size=%zu alias_align=%zu alias_signed=%u\n",
        sizeof(CJThreadCreateSource), alignof(CJThreadCreateSource),
        std::is_signed<Underlying>::value ? 1 : 0, aliasSize, aliasAlign, aliasSigned);
    for (size_t index = 0; index < 3; ++index) {
        std::printf("CJTHREAD_CREATE_SOURCE name=%s value=%u bytes=", names[index], values[index]);
        PrintBytes(enumValues[index]);
        std::puts("");
    }
    return 0;
}

#ifdef CJTHREAD_CREATE_SOURCE_CPP_ORACLE
int main()
{
    return CJThreadCreateSourceObserve(CJTHREAD_CREATE_SOURCE_DEFAULT,
        CJTHREAD_CREATE_SOURCE_SIGNAL, CJTHREAD_CREATE_SOURCE_FINALIZER, sizeof(uint32_t),
        alignof(uint32_t), std::is_signed<uint32_t>::value ? 1u : 0u);
}
#endif
