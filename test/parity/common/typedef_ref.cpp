#include "Common/TypeDef.h"

#include <cstdint>
#include <iostream>

using namespace MapleRuntime;

static uint64_t NextAlignValue(uint64_t value)
{
    value ^= value << 13;
    value ^= value >> 7;
    return value ^ (value << 17);
}

static void TypeDefCallback(void* pointer)
{
    ++(*static_cast<uint64_t*>(pointer));
}

template<typename T>
static void PrintLayout(const char* name)
{
    std::cout << "LAYOUT " << name << ' ' << sizeof(T) << ' ' << alignof(T) << '\n';
}

template<typename T>
static void PrintPointer(const char* name, uintptr_t bits)
{
    T value = reinterpret_cast<T>(bits);
    std::cout << "POINTER " << name << ' ' << reinterpret_cast<uintptr_t>(value) << '\n';
}

int main()
{
    PrintLayout<MAddress>("MAddress");
    PrintLayout<MSize>("MSize");
    PrintLayout<MOffset>("MOffset");
    PrintLayout<MIndex>("MIndex");
    PrintLayout<ObjRef>("ObjRef");
    PrintLayout<ArrayRef>("ArrayRef");
    PrintLayout<FuncRef>("FuncRef");
    PrintLayout<FuncDescRef>("FuncDescRef");
    PrintLayout<StringRef>("StringRef");
    PrintLayout<ExceptionRef>("ExceptionRef");
    PrintLayout<MethodInfoRef>("MethodInfoRef");
    PrintLayout<PackageInfoRef>("PackageInfoRef");
    PrintLayout<ParameterInfoRef>("ParameterInfoRef");
    PrintLayout<FuncPtr>("FuncPtr");
    PrintLayout<AllocType>("AllocType");

    std::cout << "CONSTANT NULL_ADDRESS " << NULL_ADDRESS << '\n';
    std::cout << "CONSTANT GENERIC_PAYLOAD_SIZE " << GENERIC_PAYLOAD_SIZE << '\n';
    std::cout << "CONSTANT MAX_ARRAY_SIZE " << MAX_ARRAY_SIZE << '\n';
    std::cout << "SCALAR MSize " << static_cast<MSize>(UINT32_MAX) << '\n';
    std::cout << "SCALAR MOffset " << static_cast<MOffset>(UINT32_MAX) << '\n';
    std::cout << "ALLOC " << static_cast<int32_t>(AllocType::MOVEABLE_OBJECT) << ' '
              << static_cast<int32_t>(AllocType::PINNED_OBJECT) << ' '
              << static_cast<int32_t>(AllocType::RAW_POINTER_OBJECT) << '\n';

    PrintPointer<ObjRef>("ObjRef NULL", 0);
    PrintPointer<ArrayRef>("ArrayRef NULL", 0);
    PrintPointer<FuncRef>("FuncRef NULL", 0);
    PrintPointer<FuncDescRef>("FuncDescRef NULL", 0);
    PrintPointer<StringRef>("StringRef NULL", 0);
    PrintPointer<ExceptionRef>("ExceptionRef NULL", 0);
    PrintPointer<MethodInfoRef>("MethodInfoRef NULL", 0);
    PrintPointer<PackageInfoRef>("PackageInfoRef NULL", 0);
    PrintPointer<ParameterInfoRef>("ParameterInfoRef NULL", 0);
    PrintPointer<ObjRef>("ObjRef NONNULL", 4096);
    PrintPointer<ArrayRef>("ArrayRef NONNULL", 4352);
    PrintPointer<FuncRef>("FuncRef NONNULL", 4608);
    PrintPointer<FuncDescRef>("FuncDescRef NONNULL", 4864);
    PrintPointer<StringRef>("StringRef NONNULL", 5120);
    PrintPointer<ExceptionRef>("ExceptionRef NONNULL", 5376);
    PrintPointer<MethodInfoRef>("MethodInfoRef NONNULL", 5632);
    PrintPointer<PackageInfoRef>("PackageInfoRef NONNULL", 5888);
    PrintPointer<ParameterInfoRef>("ParameterInfoRef NONNULL", 6144);

    uint64_t callbackStorage = 0;
    FuncPtr callback = TypeDefCallback;
    for (uint64_t call = 0; call < 4096; ++call) {
        callback(&callbackStorage);
    }
    std::cout << "FUNCPTR callbacks=4096 indirect_calls=4096 value=" << callbackStorage
              << " null=0 nonnull=1\n";

    uint64_t state = 0x6a09e667f3bcc909ULL;
    for (uint64_t operation = 0; operation < 100000; ++operation) {
        state = NextAlignValue(state);
        const uint64_t alignBits = state;
        state = NextAlignValue(state);
        const uint64_t valueBits = state;
        const uint64_t edge = operation % 16;
        const uint64_t width = operation % 4;
        if (width == 0) {
            const uint16_t alignment = static_cast<uint16_t>(uint16_t{1} << (alignBits % 16));
            uint16_t value = static_cast<uint16_t>(valueBits);
            if (edge == 0) { value = UINT16_MAX; }
            else if (edge == 1) { value = static_cast<uint16_t>(UINT16_MAX - alignment + 2); }
            else if (edge == 2) { value = 0; }
            else if (edge == 3) { value = static_cast<uint16_t>(alignment - 1); }
            else if (edge == 4) { value = static_cast<uint16_t>(UINT16_MAX - alignment + 1); }
            else if (edge == 5) { value = alignment; }
            const uint16_t result = static_cast<uint16_t>(MRT_ALIGN(value, alignment));
            std::cout << "ALIGN " << operation << " 16 " << value << ' ' << alignment << ' ' << result << '\n';
        } else if (width == 1) {
            const uint32_t alignment = uint32_t{1} << (alignBits % 32);
            uint32_t value = static_cast<uint32_t>(valueBits);
            if (edge == 0) { value = UINT32_MAX; }
            else if (edge == 1) { value = UINT32_MAX - alignment + 2U; }
            else if (edge == 2) { value = 0; }
            else if (edge == 3) { value = alignment - 1U; }
            else if (edge == 4) { value = UINT32_MAX - alignment + 1U; }
            else if (edge == 5) { value = alignment; }
            const uint32_t result = static_cast<uint32_t>(MRT_ALIGN(value, alignment));
            std::cout << "ALIGN " << operation << " 32 " << value << ' ' << alignment << ' ' << result << '\n';
        } else if (width == 2) {
            const uint64_t alignment = uint64_t{1} << (alignBits % 64);
            uint64_t value = valueBits;
            if (edge == 0) { value = UINT64_MAX; }
            else if (edge == 1) { value = UINT64_MAX - alignment + 2ULL; }
            else if (edge == 2) { value = 0; }
            else if (edge == 3) { value = alignment - 1ULL; }
            else if (edge == 4) { value = UINT64_MAX - alignment + 1ULL; }
            else if (edge == 5) { value = alignment; }
            const uint64_t result = static_cast<uint64_t>(MRT_ALIGN(value, alignment));
            std::cout << "ALIGN " << operation << " 64 " << value << ' ' << alignment << ' ' << result << '\n';
        } else {
            const Uptr alignment = static_cast<Uptr>(uint64_t{1} << (alignBits % 64));
            Uptr value = static_cast<Uptr>(valueBits);
            if (edge == 0) { value = static_cast<Uptr>(UINT64_MAX); }
            else if (edge == 1) { value = static_cast<Uptr>(UINT64_MAX) - alignment + 2; }
            else if (edge == 2) { value = 0; }
            else if (edge == 3) { value = alignment - 1; }
            else if (edge == 4) { value = static_cast<Uptr>(UINT64_MAX) - alignment + 1; }
            else if (edge == 5) { value = alignment; }
            const Uptr result = static_cast<Uptr>(MRT_ALIGN(value, alignment));
            std::cout << "ALIGN " << operation << " N " << value << ' ' << alignment << ' ' << result << '\n';
        }
    }
    return 0;
}
