#ifndef CJCJ_RT_BARRIER_PROTOCOL_H
#define CJCJ_RT_BARRIER_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint8_t CJ_RT_TryUpdateRefField(void* object, uintptr_t* field, void** toVersion);
uint8_t CJ_RT_TryUntagRefField(void* object, uintptr_t* field, void** target);
uint8_t CJ_RT_IsOldPointer(uintptr_t* field);
uint8_t CJ_RT_IsCurrentPointer(uintptr_t* field);
void* CJ_RT_FindToVersion(void* object);
uintptr_t CJ_RT_GetAndTryTagRefField(void* object);
uint8_t CJ_RT_IsUnmovableFromObject(void* object);
uint8_t CJ_RT_TryForwardRefField(void* object, uintptr_t* field, void** toVersion);
void* CJ_RT_ForwardObject(void* object);
void CJ_RT_RememberObjectInSatbBuffer(void* object);
uint8_t CJ_RT_IsHeapAddress(const void* address);

#ifdef __cplusplus
}
#endif

#endif // CJCJ_RT_BARRIER_PROTOCOL_H
