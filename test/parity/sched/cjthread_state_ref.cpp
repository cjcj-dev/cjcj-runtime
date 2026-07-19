// CJThread schedule/include/schedule.h:415-420 and
// schedule/include/inner/cjthread.h:160-168. Linux x86_64 representation oracle.
#include <cstddef>
#include <cstdint>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <new>
#include <type_traits>

#include "schedule.h"
#include "cjthread.h"

size_t g_pageSize = 0;
void LogWrite(ThreadLogLevel, unsigned int, const char*, unsigned short, const char*, ...) {}

extern "C" void CJThreadStatePrintBytes(const void* value, size_t size)
{
    const auto* bytes = static_cast<const unsigned char*>(value);
    for (size_t index = 0; index < size; ++index) {
        std::printf("%02x", static_cast<unsigned>(bytes[index]));
    }
}

extern "C" void CJThreadStatePrintOwnerBytes(const LuaCJThread* owner)
{
    const auto* bytes = reinterpret_cast<const unsigned char*>(owner);
    std::printf("LUA_CJTHREAD_OWNER_BYTES bytes=");
    for (size_t index = 0; index < sizeof(*owner); ++index) {
        std::printf("%02x", static_cast<unsigned>(bytes[index]));
    }
    std::puts("");
}

extern "C" int32_t CJThreadStateObserve(const LuaCJThread* owner, int32_t init,
    int32_t suspending, int32_t running, int32_t done, size_t aliasSize,
    size_t aliasAlign, int32_t signedMinusOne)
{
    using EnumUnderlying = std::underlying_type<LuaCJThreadState>::type;
    if (owner == nullptr || init != LUA_CJTHREAD_INIT || suspending != LUA_CJTHREAD_SUSPENDING ||
        running != LUA_CJTHREAD_RUNNING || done != LUA_CJTHREAD_DONE || aliasSize != sizeof(int32_t) ||
        aliasAlign != alignof(int32_t) || signedMinusOne != -1 || owner->state != LUA_CJTHREAD_INIT) {
        return 1;
    }
    const unsigned char* ownerBytes = reinterpret_cast<const unsigned char*>(owner);
    for (size_t index = 0; index < sizeof(*owner); ++index) {
        if (ownerBytes[index] != 0) {
            return 2;
        }
    }

    std::printf("LUA_CJTHREAD_STATE_REP enum_size=%zu enum_align=%zu enum_underlying_signed=%d "
        "storage_size=%zu storage_align=%zu storage_signed=%d signed_minus_one=%d "
        "signed_minus_one_bytes=", sizeof(LuaCJThreadState), alignof(LuaCJThreadState),
        std::is_signed<EnumUnderlying>::value ? 1 : 0, aliasSize, aliasAlign,
        std::is_signed<int32_t>::value ? 1 : 0, signedMinusOne);
    CJThreadStatePrintBytes(&signedMinusOne, sizeof(signedMinusOne));
    std::puts("");

    const int32_t values[] = {init, suspending, running, done};
    const char* names[] = {"LUA_CJTHREAD_INIT", "LUA_CJTHREAD_SUSPENDING",
        "LUA_CJTHREAD_RUNNING", "LUA_CJTHREAD_DONE"};
    for (size_t index = 0; index < 4; ++index) {
        std::printf("LUA_CJTHREAD_STATE name=%s value=%d bytes=", names[index], values[index]);
        CJThreadStatePrintBytes(&values[index], sizeof(values[index]));
        std::puts("");
    }
    std::printf("LUA_CJTHREAD_LAYOUT sizeof=%zu align=%zu sem=%zu state=%zu attrUser=%zu\n",
        sizeof(LuaCJThread), alignof(LuaCJThread), offsetof(LuaCJThread, sem),
        offsetof(LuaCJThread, state), offsetof(LuaCJThread, attrUser));
    CJThreadStatePrintOwnerBytes(owner);
    return 0;
}

#ifdef CJTHREAD_STATE_CPP_ORACLE
int main()
{
    alignas(LuaCJThread) unsigned char storage[sizeof(LuaCJThread)] {};
    LuaCJThread* owner = new (storage) LuaCJThread {};
    const int32_t init = LUA_CJTHREAD_INIT;
    const int32_t suspending = LUA_CJTHREAD_SUSPENDING;
    const int32_t running = LUA_CJTHREAD_RUNNING;
    const int32_t done = LUA_CJTHREAD_DONE;
    const int32_t result = CJThreadStateObserve(owner, init, suspending, running, done,
        sizeof(int32_t), alignof(int32_t), -1);
    owner->~LuaCJThread();
    return result;
}
#endif
