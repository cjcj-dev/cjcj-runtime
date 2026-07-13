// Common/Dataref.h:16-50. Include and execute the actual C++ runtime templates as the oracle.
#include "Common/Dataref.h"

#include <cstddef>
#include <cstdint>
#include <iostream>
#include <new>

using MapleRuntime::DataRefOffset32;
using MapleRuntime::DataRefOffset64;

template<typename T>
static void Emit32(std::uint8_t* base, std::size_t wrapperPosition, const char* typeName,
                   std::int32_t positiveOffset, std::int32_t negativeOffset)
{
    // Common/Dataref.h:20-33. Construct the actual template at the selected inline-object address.
    auto* wrapper = new (base + wrapperPosition) DataRefOffset32<T>{0};
    auto* zero = wrapper->GetDataRef();
    std::cout << "DATAREF_CASE type=d32_" << typeName << " kind=zero null=" << (zero == nullptr) << '\n';

    // Common/Dataref.h:28-30. Compare the positive result and the result-minus-wrapper delta.
    wrapper->refOffset = positiveOffset;
    auto* positive = wrapper->GetDataRef();
    auto* positiveTarget = reinterpret_cast<T*>(base + wrapperPosition + positiveOffset);
    auto positiveAddress = reinterpret_cast<std::uintptr_t>(positive);
    auto wrapperAddress = reinterpret_cast<std::uintptr_t>(wrapper);
    auto positiveDelta = static_cast<std::intptr_t>(positiveAddress - wrapperAddress);
    std::cout << "DATAREF_CASE type=d32_" << typeName << " kind=positive exact="
              << (positive == positiveTarget) << " delta=" << positiveDelta << '\n';

    // Common/Dataref.h:28-30. Preserve a negative self-relative displacement and its signed delta.
    wrapper->refOffset = negativeOffset;
    auto* negative = wrapper->GetDataRef();
    auto* negativeTarget = reinterpret_cast<T*>(base + wrapperPosition + negativeOffset);
    auto negativeAddress = reinterpret_cast<std::uintptr_t>(negative);
    auto negativeDelta = -static_cast<std::intptr_t>(wrapperAddress - negativeAddress);
    std::cout << "DATAREF_CASE type=d32_" << typeName << " kind=negative exact="
              << (negative == negativeTarget) << " delta=" << negativeDelta << '\n';
}

template<typename T>
static void Emit64(std::uint8_t* base, std::size_t wrapperPosition, const char* typeName,
                   std::int64_t positiveOffset, std::int64_t negativeOffset)
{
    // Common/Dataref.h:36-49. Construct the actual template at the selected inline-object address.
    auto* wrapper = new (base + wrapperPosition) DataRefOffset64<T>{0};
    auto* zero = wrapper->GetDataRef();
    std::cout << "DATAREF_CASE type=d64_" << typeName << " kind=zero null=" << (zero == nullptr) << '\n';

    // Common/Dataref.h:44-46. Compare the positive result and the result-minus-wrapper delta.
    wrapper->refOffset = positiveOffset;
    auto* positive = wrapper->GetDataRef();
    auto* positiveTarget = reinterpret_cast<T*>(base + wrapperPosition + positiveOffset);
    auto positiveAddress = reinterpret_cast<std::uintptr_t>(positive);
    auto wrapperAddress = reinterpret_cast<std::uintptr_t>(wrapper);
    auto positiveDelta = static_cast<std::intptr_t>(positiveAddress - wrapperAddress);
    std::cout << "DATAREF_CASE type=d64_" << typeName << " kind=positive exact="
              << (positive == positiveTarget) << " delta=" << positiveDelta << '\n';

    // Common/Dataref.h:44-46. Preserve a negative self-relative displacement and its signed delta.
    wrapper->refOffset = negativeOffset;
    auto* negative = wrapper->GetDataRef();
    auto* negativeTarget = reinterpret_cast<T*>(base + wrapperPosition + negativeOffset);
    auto negativeAddress = reinterpret_cast<std::uintptr_t>(negative);
    auto negativeDelta = -static_cast<std::intptr_t>(wrapperAddress - negativeAddress);
    std::cout << "DATAREF_CASE type=d64_" << typeName << " kind=negative exact="
              << (negative == negativeTarget) << " delta=" << negativeDelta << '\n';
}

int main()
{
    using D32U8 = DataRefOffset32<std::uint8_t>;
    using D64U8 = DataRefOffset64<std::uint8_t>;
    using D32U64 = DataRefOffset32<std::uint64_t>;
    using D64U64 = DataRefOffset64<std::uint64_t>;

    // Common/Dataref.h:20-21,36-37. Compute every layout value from the actual template types.
    std::cout << "DATAREF_LAYOUT d32_size=" << sizeof(D32U8) << " d32_align=" << alignof(D32U8)
              << " d32_refOffset=" << offsetof(D32U8, refOffset) << " d64_size=" << sizeof(D64U8)
              << " d64_align=" << alignof(D64U8) << " d64_refOffset=" << offsetof(D64U8, refOffset) << '\n';
    std::cout << "DATAREF_LAYOUT_T d32_u64_size=" << sizeof(D32U64)
              << " d32_u64_align=" << alignof(D32U64) << " d32_u64_refOffset=" << offsetof(D32U64, refOffset)
              << " d64_u64_size=" << sizeof(D64U64) << " d64_u64_align=" << alignof(D64U64)
              << " d64_u64_refOffset=" << offsetof(D64U64, refOffset) << '\n';

    // Common/Dataref.h:20-50. All wrapper and target addresses remain within this aligned buffer.
    alignas(8) std::uint8_t storage[272]{};
    Emit32<std::uint8_t>(storage, 20, "u8", 13, -9);
    Emit32<std::uint64_t>(storage, 52, "u64", 36, -28);
    Emit64<std::uint8_t>(storage, 40, "u8", 17, -11);
    Emit64<std::uint64_t>(storage, 72, "u64", 32, -40);
    return 0;
}
