#include <cstring>

#include "Common/BaseObject.h"
#include "Common/StateWord.h"
#include "ObjectModel/Flags.h"
#include "ObjectModel/MArray.h"
#include "ObjectModel/MClass.h"

using namespace MapleRuntime;

extern "C" void CJRT_TestInitSizeClass(void* object, void* typeInfoStorage, uint32_t instanceSize)
{
    std::memset(typeInfoStorage, 0, sizeof(TypeInfo));
    auto* typeInfo = static_cast<TypeInfo*>(typeInfoStorage);
    typeInfo->SetType(TypeKind::TYPE_KIND_CLASS);
    typeInfo->SetInstanceSize(instanceSize);
    reinterpret_cast<StateWord*>(object)->SetTypeInfo(typeInfo);
}

extern "C" void CJRT_TestInitSizeArray(void* object, void* arrayTypeInfoStorage,
    void* componentTypeInfoStorage, int8_t componentKind, uint32_t componentSize, uint64_t length)
{
    std::memset(arrayTypeInfoStorage, 0, sizeof(TypeInfo));
    std::memset(componentTypeInfoStorage, 0, sizeof(TypeInfo));
    auto* arrayTypeInfo = static_cast<TypeInfo*>(arrayTypeInfoStorage);
    auto* componentTypeInfo = static_cast<TypeInfo*>(componentTypeInfoStorage);
    componentTypeInfo->SetType(componentKind);
    componentTypeInfo->SetInstanceSize(componentSize);
    arrayTypeInfo->SetType(TypeKind::TYPE_KIND_RAWARRAY);
    arrayTypeInfo->SetComponentTypeInfo(componentTypeInfo);
    reinterpret_cast<StateWord*>(object)->SetTypeInfo(arrayTypeInfo);
    std::memcpy(static_cast<unsigned char*>(object) + sizeof(StateWord), &length, sizeof(length));
}

extern "C" uintptr_t CJRT_TestBaseObjectGetSize(void* object)
{
    return static_cast<BaseObject*>(object)->GetSize();
}
