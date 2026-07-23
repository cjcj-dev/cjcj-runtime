#include "cjcj_rt_barrier_protocol.h"

#include "Heap/Collector/Collector.h"
#include "Heap/Heap.h"
#include "Mutator/Mutator.h"
#include "ObjectModel/RefField.h"

using namespace MapleRuntime;

// Heap/Allocator/RegionManager.cpp:543 uses the same public
// Heap::GetHeap().GetCollector() path to the current C++ Collector.
extern "C" uint8_t CJ_RT_TryUpdateRefField(void* object, uintptr_t* field, void** toVersion)
{
    auto* result = static_cast<BaseObject*>(*toVersion);
    bool updated = Heap::GetHeap().GetCollector().TryUpdateRefField(
        static_cast<BaseObject*>(object), *reinterpret_cast<RefField<>*>(field), result);
    *toVersion = result;
    return updated;
}

extern "C" uint8_t CJ_RT_TryUntagRefField(void* object, uintptr_t* field, void** target)
{
    auto* result = static_cast<BaseObject*>(*target);
    bool untagged = Heap::GetHeap().GetCollector().TryUntagRefField(
        static_cast<BaseObject*>(object), *reinterpret_cast<RefField<>*>(field), result);
    *target = result;
    return untagged;
}

extern "C" uint8_t CJ_RT_IsOldPointer(uintptr_t* field)
{
    return Heap::GetHeap().GetCollector().IsOldPointer(*reinterpret_cast<RefField<>*>(field));
}

extern "C" uint8_t CJ_RT_IsCurrentPointer(uintptr_t* field)
{
    return Heap::GetHeap().GetCollector().IsCurrentPointer(*reinterpret_cast<RefField<>*>(field));
}

extern "C" void* CJ_RT_FindToVersion(void* object)
{
    return Heap::GetHeap().GetCollector().FindToVersion(static_cast<BaseObject*>(object));
}

extern "C" uintptr_t CJ_RT_GetAndTryTagRefField(void* object)
{
    return Heap::GetHeap().GetCollector().GetAndTryTagRefField(
        static_cast<BaseObject*>(object)).GetFieldValue();
}

extern "C" uint8_t CJ_RT_IsUnmovableFromObject(void* object)
{
    return Heap::GetHeap().GetCollector().IsUnmovableFromObject(static_cast<BaseObject*>(object));
}

extern "C" uint8_t CJ_RT_TryForwardRefField(void* object, uintptr_t* field, void** toVersion)
{
    auto* result = static_cast<BaseObject*>(*toVersion);
    bool forwarded = Heap::GetHeap().GetCollector().TryForwardRefField(
        static_cast<BaseObject*>(object), *reinterpret_cast<RefField<>*>(field), result);
    *toVersion = result;
    return forwarded;
}

extern "C" void* CJ_RT_ForwardObject(void* object)
{
    return Heap::GetHeap().GetCollector().ForwardObject(static_cast<BaseObject*>(object));
}

extern "C" void CJ_RT_RememberObjectInSatbBuffer(void* object)
{
    Mutator::GetMutator()->RememberObjectInSatbBuffer(static_cast<BaseObject*>(object));
}

extern "C" uint8_t CJ_RT_IsHeapAddress(const void* address)
{
    return Heap::IsHeapAddress(address);
}
