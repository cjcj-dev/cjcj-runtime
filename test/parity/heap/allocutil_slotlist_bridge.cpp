#include <cstddef>
#include <cstdlib>
#include <cstring>

extern "C" size_t _ZNK12MapleRuntime10BaseObject7GetSizeEv(const void* baseObject)
{
    size_t size = 0;
    std::memcpy(&size, baseObject, sizeof(size));
    return size;
}

extern "C" [[noreturn]] void RtFatal(const char*)
{
    std::abort();
}
