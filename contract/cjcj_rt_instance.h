// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#ifndef CJCJ_RT_INSTANCE_H
#define CJCJ_RT_INSTANCE_H

#include "Cangjie.h"

// Cangjie.h:311-329 ConcurrencyParam. The units remain KB, and a zero field
// requests the corresponding default described by CangjieRuntimeApi.cpp:259-264.
struct CjcjRtInstanceParam {
    size_t thStackSize;
    size_t coStackSize;
    uint32_t processorNum;
};

// Cangjie.h:435 ScheduleHandle is the domain accepted by
// CangjieRuntimeApi.cpp:542-549 RunCJTaskToSchedule. Keep it opaque here.
typedef void* CjcjRtInstanceHandle;

CANGJIE_RT_API_DECLS_BEGIN

MRT_EXPORT CjcjRtInstanceHandle CJCJ_MRT_InstanceNew(const struct CjcjRtInstanceParam* param);
MRT_EXPORT CJThreadHandle CJCJ_MRT_InstanceRunTask(
    CjcjRtInstanceHandle instance, const CJTaskFunc func, void* args);
MRT_EXPORT int CJCJ_MRT_InstanceStop(CjcjRtInstanceHandle instance);

CANGJIE_RT_API_DECLS_END

#endif // CJCJ_RT_INSTANCE_H
