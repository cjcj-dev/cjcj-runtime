#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>

#include "Heap/Allocator/AllocUtil.h"
#include "Heap/Allocator/SlotList.h"
#include "ObjectModel/Flags.h"
#include "ObjectModel/MArray.h"
#include "ObjectModel/MClass.h"

namespace {
template<size_t N>
void InitSlot(std::array<uint64_t, N>& storage, MapleRuntime::TypeInfo& typeInfo)
{
    storage.fill(0xa5a5a5a5a5a5a5a5ULL);
    std::memset(&typeInfo, 0, sizeof(typeInfo));
    typeInfo.SetType(MapleRuntime::TypeKind::TYPE_KIND_CLASS);
    typeInfo.SetInstanceSize(static_cast<uint32_t>(sizeof(storage) - MapleRuntime::TYPEINFO_PTR_SIZE));
    reinterpret_cast<MapleRuntime::StateWord*>(storage.data())->SetTypeInfo(&typeInfo);
}

template<size_t N>
bool TailIsZero(const std::array<uint64_t, N>& storage)
{
    for (size_t i = sizeof(MapleRuntime::ObjectSlot) / sizeof(uint64_t); i < N; ++i) {
        if (storage[i] != 0) {
            return false;
        }
    }
    return true;
}
} // namespace

int main()
{
    using namespace MapleRuntime;
    std::cout << std::boolalpha;
    std::cout << "ALLOCUTIL page=" << ALLOC_UTIL_PAGE_SIZE
              << " page_up_0=" << ALLOCUTIL_PAGE_RND_UP(0)
              << " page_up_1=" << ALLOCUTIL_PAGE_RND_UP(1)
              << " page_up_4096=" << ALLOCUTIL_PAGE_RND_UP(4096)
              << " rnd_down_4097=" << AllocUtilRndDown<size_t>(4097, 4096)
              << " rnd_up_4097=" << AllocUtilRndUp<size_t>(4097, 4096) << '\n';
    std::cout << "LAYOUT object_size=" << sizeof(ObjectSlot)
              << " object_align=" << alignof(ObjectSlot)
              << " list_size=" << sizeof(SlotList)
              << " list_align=" << alignof(SlotList) << '\n';

    alignas(ObjectSlot) std::array<uint64_t, 4> slotA;
    alignas(ObjectSlot) std::array<uint64_t, 6> slotB;
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> typeInfoAStorage{};
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> typeInfoBStorage{};
    auto& typeInfoA = *reinterpret_cast<TypeInfo*>(typeInfoAStorage.data());
    auto& typeInfoB = *reinterpret_cast<TypeInfo*>(typeInfoBStorage.data());
    InitSlot(slotA, typeInfoA);
    InitSlot(slotB, typeInfoB);
    auto* objectA = reinterpret_cast<BaseObject*>(slotA.data());
    auto* objectB = reinterpret_cast<BaseObject*>(slotB.data());
    auto* overlayA = reinterpret_cast<ObjectSlot*>(slotA.data());
    auto* overlayB = reinterpret_cast<ObjectSlot*>(slotB.data());

    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> arrayTypeInfoStorage{};
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> componentTypeInfoStorage{};
    auto& arrayTypeInfo = *reinterpret_cast<TypeInfo*>(arrayTypeInfoStorage.data());
    auto& componentTypeInfo = *reinterpret_cast<TypeInfo*>(componentTypeInfoStorage.data());
    arrayTypeInfo.SetType(TypeKind::TYPE_KIND_RAWARRAY);
    arrayTypeInfo.SetComponentTypeInfo(&componentTypeInfo);
    componentTypeInfo.SetType(TypeKind::TYPE_KIND_UINT64);
    componentTypeInfo.SetInstanceSize(sizeof(uint64_t));
    alignas(MArray) std::array<uint64_t, 6> arrayObject{};
    reinterpret_cast<StateWord*>(arrayObject.data())->SetTypeInfo(&arrayTypeInfo);
    uint32_t arrayLength = 4;
    std::memcpy(reinterpret_cast<unsigned char*>(arrayObject.data()) + sizeof(StateWord),
                &arrayLength, sizeof(arrayLength));
    std::cout << "GETSIZE class=" << objectA->GetSize()
              << " array=" << reinterpret_cast<BaseObject*>(arrayObject.data())->GetSize() << '\n';

    SlotList list;
    list.PushFront(objectA);
    std::cout << "PUSH_A next_null=" << (overlayA->next == nullptr)
              << " tail_zero=" << TailIsZero(slotA) << '\n';
    list.PushFront(objectB);
    std::cout << "PUSH_B next_a=" << (overlayB->next == overlayA)
              << " tail_zero=" << TailIsZero(slotB) << '\n';
    std::cout << "POP_WRONG zero=" << (list.PopFront(sizeof(slotA)) == 0) << '\n';
    std::cout << "POP_B match=" << (list.PopFront(sizeof(slotB)) == reinterpret_cast<uintptr_t>(overlayB))
              << " next_null=" << (overlayB->next == nullptr) << '\n';
    std::cout << "POP_A match=" << (list.PopFront(sizeof(slotA)) == reinterpret_cast<uintptr_t>(overlayA))
              << " next_null=" << (overlayA->next == nullptr) << '\n';
    std::cout << "POP_EMPTY zero=" << (list.PopFront(sizeof(slotA)) == 0) << '\n';
    list.PushFront(objectA);
    list.Clear();
    std::cout << "CLEAR empty=" << (list.PopFront(sizeof(slotA)) == 0) << '\n';
    return 0;
}
