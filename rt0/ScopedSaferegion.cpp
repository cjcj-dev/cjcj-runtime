// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include "Common/ScopedObjectAccess.h"
#include "Base/LogFile.h"

extern "C" void* _ZTVN12MapleRuntime17FreeRegionManagerE[];

extern "C" void* CJRT_FreeRegionManagerVTableAddressPoint()
{
    // Itanium C++ ABI: object vptr skips offset-to-top and typeinfo entries.
    return &_ZTVN12MapleRuntime17FreeRegionManagerE[2];
}

// Common/ScopedObjectAccess.h:18-36. These two leaves carry the exact state of
// ScopedEnterSaferegion(true) across the restricted Cangjie boundary without
// allocating a managed guard or inventing a callback ABI.
extern "C" bool CJRT_ScopedEnterSaferegionOnlyMutatorBegin()
{
    MapleRuntime::Mutator* mutator = MapleRuntime::Mutator::GetMutator();
    MapleRuntime::ThreadType threadType = MapleRuntime::ThreadLocal::GetThreadType();
    if (threadType == MapleRuntime::ThreadType::FP_THREAD ||
        threadType == MapleRuntime::ThreadType::GC_THREAD) {
        return false;
    }
    return mutator != nullptr ? mutator->EnterSaferegion(true) : false;
}

extern "C" void CJRT_ScopedEnterSaferegionEnd(bool stateChanged)
{
    if (stateChanged) {
        MapleRuntime::Mutator* mutator = MapleRuntime::Mutator::GetMutator();
        (void)mutator->LeaveSaferegion();
    }
}

namespace MapleRuntime {
extern "C" void CJRT_FreeRegionReleaseNoneLog(size_t dirtyBytes, size_t targetCachedSize)
{
    VLOG(REPORT, "release heap garbage memory 0 bytes, cache %zu(%zu) bytes",
         dirtyBytes, targetCachedSize);
}

extern "C" void CJRT_FreeRegionReleaseLog(size_t releasedBytes, size_t dirtyBytes, size_t targetCachedSize)
{
    VLOG(REPORT, "release heap garbage memory %zu bytes, cache %zu(%zu) bytes",
         releasedBytes, dirtyBytes, targetCachedSize);
}
} // namespace MapleRuntime
