#include <cstring>

#include "Common/StateWord.h"
#include "ObjectModel/Flags.h"
#include "ObjectModel/MClass.h"

extern "C" void AllocUtilSlotListInitClass(void* object, void* typeInfoStorage, uint32_t instanceSize)
{
    std::memset(typeInfoStorage, 0, sizeof(MapleRuntime::TypeInfo));
    auto* typeInfo = reinterpret_cast<MapleRuntime::TypeInfo*>(typeInfoStorage);
    typeInfo->SetType(MapleRuntime::TypeKind::TYPE_KIND_CLASS);
    typeInfo->SetInstanceSize(instanceSize);
    reinterpret_cast<MapleRuntime::StateWord*>(object)->SetTypeInfo(typeInfo);
}

extern "C" void AllocUtilSlotListInitArray(
    void* object, void* arrayTypeInfoStorage, void* componentTypeInfoStorage, uint32_t length, uint32_t componentSize)
{
    std::memset(arrayTypeInfoStorage, 0, sizeof(MapleRuntime::TypeInfo));
    std::memset(componentTypeInfoStorage, 0, sizeof(MapleRuntime::TypeInfo));
    auto* arrayTypeInfo = reinterpret_cast<MapleRuntime::TypeInfo*>(arrayTypeInfoStorage);
    auto* componentTypeInfo = reinterpret_cast<MapleRuntime::TypeInfo*>(componentTypeInfoStorage);
    arrayTypeInfo->SetType(MapleRuntime::TypeKind::TYPE_KIND_RAWARRAY);
    arrayTypeInfo->SetComponentTypeInfo(componentTypeInfo);
    componentTypeInfo->SetType(MapleRuntime::TypeKind::TYPE_KIND_UINT64);
    componentTypeInfo->SetInstanceSize(componentSize);
    reinterpret_cast<MapleRuntime::StateWord*>(object)->SetTypeInfo(arrayTypeInfo);
    std::memcpy(static_cast<unsigned char*>(object) + sizeof(MapleRuntime::StateWord), &length, sizeof(length));
}
