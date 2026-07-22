#include <cstddef>
#include <cstdlib>
#include <new>

static size_t g_new_calls;
static size_t g_new_bytes;
static size_t g_delete_calls;
static bool g_track;

void* operator new(std::size_t size)
{
    void* result = std::malloc(size);
    if (result == nullptr) {
        throw std::bad_alloc();
    }
    if (g_track) {
        ++g_new_calls;
        g_new_bytes += size;
    }
    return result;
}

void operator delete(void* address) noexcept
{
    if (g_track && address != nullptr) {
        ++g_delete_calls;
    }
    std::free(address);
}

void operator delete(void* address, std::size_t) noexcept
{
    if (g_track && address != nullptr) {
        ++g_delete_calls;
    }
    std::free(address);
}

extern "C" void MarkWorkStackAllocReset()
{
    g_new_calls = 0;
    g_new_bytes = 0;
    g_delete_calls = 0;
    g_track = true;
}

extern "C" size_t MarkWorkStackNewCalls() { return g_new_calls; }
extern "C" size_t MarkWorkStackNewBytes() { return g_new_bytes; }
extern "C" size_t MarkWorkStackDeleteCalls() { return g_delete_calls; }
