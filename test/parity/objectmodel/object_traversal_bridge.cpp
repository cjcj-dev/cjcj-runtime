#include <cstring>

#include "Common/BaseObject.h"
#include "Common/StateWord.h"
#include "ObjectModel/Flags.h"
#include "ObjectModel/MClass.h"

using namespace MapleRuntime;

extern "C" void CJRT_TestInitTraversalClass(void* object, void* typeInfoStorage, uintptr_t bitmap)
{
    std::memset(typeInfoStorage, 0, sizeof(TypeInfo));
    auto* typeInfo = static_cast<TypeInfo*>(typeInfoStorage);
    typeInfo->SetType(TypeKind::TYPE_KIND_CLASS);
    typeInfo->SetGCTib(GCTib{bitmap});
    typeInfo->SetFlagHasRefField();
    reinterpret_cast<StateWord*>(object)->SetTypeInfo(typeInfo);
}

extern "C" void CJRT_TestInitTraversalArray(void* object, void* arrayTypeInfoStorage,
    void* componentTypeInfoStorage, int8_t componentKind, uintptr_t bitmap, uint64_t length,
    uint32_t componentSize)
{
    std::memset(arrayTypeInfoStorage, 0, sizeof(TypeInfo));
    std::memset(componentTypeInfoStorage, 0, sizeof(TypeInfo));
    auto* arrayTypeInfo = static_cast<TypeInfo*>(arrayTypeInfoStorage);
    auto* componentTypeInfo = static_cast<TypeInfo*>(componentTypeInfoStorage);
    componentTypeInfo->SetType(componentKind);
    componentTypeInfo->SetInstanceSize(componentSize);
    componentTypeInfo->SetGCTib(GCTib{bitmap});
    if (componentKind == TypeKind::TYPE_KIND_STRUCT) {
        componentTypeInfo->SetFlagHasRefField();
    }
    arrayTypeInfo->SetType(TypeKind::TYPE_KIND_RAWARRAY);
    arrayTypeInfo->SetComponentTypeInfo(componentTypeInfo);
    reinterpret_cast<StateWord*>(object)->SetTypeInfo(arrayTypeInfo);
    std::memcpy(static_cast<unsigned char*>(object) + sizeof(StateWord), &length, sizeof(length));
}
