#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

#include "ObjectModel/MClass.h"
#include "Common/StateWord.h"

using namespace MapleRuntime;

static void Print(const char* name, uintptr_t base, const std::vector<uintptr_t>& fields)
{
    std::cout << name << " count=" << fields.size() << " offsets=";
    for (size_t i = 0; i < fields.size(); ++i) {
        if (i != 0) {
            std::cout << ',';
        }
        std::cout << fields[i] - base;
    }
    std::cout << '\n';
}

int main()
{
    std::array<uintptr_t, 24> fields{};
    uintptr_t base = reinterpret_cast<uintptr_t>(fields.data());
    auto visitor = [](std::vector<uintptr_t>& result) {
        return [&result](RefField<>& field) { result.push_back(reinterpret_cast<uintptr_t>(&field)); };
    };

    GCTib shortTib{};
    shortTib.tag = 0x8000000000000125ULL;
    std::vector<uintptr_t> result;
    shortTib.ForEachBitmapWord(base, visitor(result));
    std::cout << "LAYOUT short=" << sizeof(ShortGCTib) << '/' << alignof(ShortGCTib)
              << " std=" << sizeof(StdGCTib) << '/' << alignof(StdGCTib)
              << " gctib=" << sizeof(GCTib) << '/' << alignof(GCTib) << '\n';
    Print("SHORT", base, result);

    result.clear();
    shortTib.ForEachBitmapWordInRange(base, visitor(result), base + 9, base + 70);
    Print("SHORT_RANGE", base, result);

    alignas(StdGCTib) std::array<uint8_t, 8> storage{};
    auto* standard = reinterpret_cast<StdGCTib*>(storage.data());
    standard->nBitmapWords = 3;
    standard->bitmapWords[0] = 0x81;
    standard->bitmapWords[1] = 0x12;
    standard->bitmapWords[2] = 0x40;
    GCTib longTib{};
    longTib.gctib = standard;
    result.clear();
    longTib.ForEachBitmapWord(base, visitor(result));
    Print("STD", base, result);

    result.clear();
    longTib.ForEachBitmapWordInRange(base, visitor(result), base + 65, base + 180);
    Print("STD_RANGE", base, result);

    alignas(BaseObject) std::array<uint64_t, 12> objectStorage{};
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> classTypeInfoStorage{};
    auto* classTypeInfo = reinterpret_cast<TypeInfo*>(classTypeInfoStorage.data());
    classTypeInfo->SetType(TypeKind::TYPE_KIND_CLASS);
    classTypeInfo->SetGCTib(GCTib{0x8000000000000125ULL});
    classTypeInfo->SetFlagHasRefField();
    reinterpret_cast<StateWord*>(objectStorage.data())->SetTypeInfo(classTypeInfo);
    auto* object = reinterpret_cast<BaseObject*>(objectStorage.data());
    result.clear();
    object->ForEachRefField(visitor(result));
    Print("OBJECT", reinterpret_cast<uintptr_t>(object), result);

    alignas(MArray) std::array<uint64_t, 12> structArrayStorage{};
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> structArrayTypeInfoStorage{};
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> structComponentStorage{};
    auto* structArrayTypeInfo = reinterpret_cast<TypeInfo*>(structArrayTypeInfoStorage.data());
    auto* structComponent = reinterpret_cast<TypeInfo*>(structComponentStorage.data());
    structComponent->SetType(TypeKind::TYPE_KIND_STRUCT);
    structComponent->SetInstanceSize(24);
    structComponent->SetGCTib(GCTib{0x8000000000000005ULL});
    structComponent->SetFlagHasRefField();
    structArrayTypeInfo->SetType(TypeKind::TYPE_KIND_RAWARRAY);
    structArrayTypeInfo->SetComponentTypeInfo(structComponent);
    reinterpret_cast<StateWord*>(structArrayStorage.data())->SetTypeInfo(structArrayTypeInfo);
    uint64_t structLength = 2;
    std::memcpy(reinterpret_cast<unsigned char*>(structArrayStorage.data()) + sizeof(StateWord),
        &structLength, sizeof(structLength));
    auto* structArray = reinterpret_cast<BaseObject*>(structArrayStorage.data());
    result.clear();
    structArray->ForEachRefField(visitor(result));
    Print("STRUCT_ARRAY", reinterpret_cast<uintptr_t>(structArray), result);

    alignas(MArray) std::array<uint64_t, 8> refArrayStorage{};
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> refArrayTypeInfoStorage{};
    alignas(TypeInfo) std::array<std::byte, sizeof(TypeInfo)> refComponentStorage{};
    auto* refArrayTypeInfo = reinterpret_cast<TypeInfo*>(refArrayTypeInfoStorage.data());
    auto* refComponent = reinterpret_cast<TypeInfo*>(refComponentStorage.data());
    refComponent->SetType(TypeKind::TYPE_KIND_CLASS);
    refArrayTypeInfo->SetType(TypeKind::TYPE_KIND_RAWARRAY);
    refArrayTypeInfo->SetComponentTypeInfo(refComponent);
    reinterpret_cast<StateWord*>(refArrayStorage.data())->SetTypeInfo(refArrayTypeInfo);
    uint64_t refLength = 3;
    std::memcpy(reinterpret_cast<unsigned char*>(refArrayStorage.data()) + sizeof(StateWord),
        &refLength, sizeof(refLength));
    auto* refArray = reinterpret_cast<MArray*>(refArrayStorage.data());
    uintptr_t refBase = reinterpret_cast<uintptr_t>(refArray);
    result.clear();
    refArray->ForEachRefFieldInRange(visitor(result), refBase + 16, refBase + 40);
    Print("REF_ARRAY_RANGE", refBase, result);
}
