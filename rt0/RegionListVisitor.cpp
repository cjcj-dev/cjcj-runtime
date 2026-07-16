// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <functional>

namespace MapleRuntime {
class RegionInfo;
}

// Heap/Allocator/RegionList.h:115-132. The mixed-runtime boundary retains the
// original native std::function object. Cangjie traverses the native RegionInfo
// chain and calls through this leaf without creating a managed function object.
extern "C" void CJRT_RegionListInvokeVisitor(void* visitor, MapleRuntime::RegionInfo* region)
{
    auto* callback = static_cast<std::function<void(MapleRuntime::RegionInfo*)>*>(visitor);
    (*callback)(region);
}
