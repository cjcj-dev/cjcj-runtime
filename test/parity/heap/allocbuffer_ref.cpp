// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <atomic>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <iostream>
#include <list>
#include <mutex>
#include <new>

#define private public
#define protected public
#include "Heap/Allocator/AllocBuffer.h"
#undef protected
#undef private

using namespace MapleRuntime;

int main()
{
    void* storage = std::malloc(sizeof(AllocBuffer));
    auto* buffer = new (storage) AllocBuffer();
    bool init = buffer->GetRegion() == RegionInfo::NullRegion() && buffer->GetPreparedRegion() == nullptr &&
        buffer->stackRoots.empty();
    bool names = std::strcmp(buffer->tlRawPointerRegions.listName, "thread-local raw-pointer regions") == 0 &&
        std::strcmp(buffer->tlLargeRawPointerRegions.listName, "thread-local large raw-pointer regions") == 0;

    auto* root1 = reinterpret_cast<BaseObject*>(0x1110);
    auto* root2 = reinterpret_cast<BaseObject*>(0x2220);
    auto* root3 = reinterpret_cast<BaseObject*>(0x3330);
    buffer->SetRegion(reinterpret_cast<RegionInfo*>(root1));
    bool region = buffer->GetRegion() == reinterpret_cast<RegionInfo*>(root1);
#if defined(MRT_DEBUG) && MRT_DEBUG == 1
    buffer->SetRegion(RegionInfo::NullRegion());
    buffer->ClearRegion();
#else
    buffer->ClearRegion();
    region = region && buffer->GetRegion() == RegionInfo::NullRegion();
    buffer->ClearRegion();
#endif
    region = region && buffer->GetRegion() == RegionInfo::NullRegion();

    bool prepared = buffer->SetPreparedRegion(reinterpret_cast<RegionInfo*>(root2));
    prepared = prepared && buffer->GetPreparedRegion() == reinterpret_cast<RegionInfo*>(root2);
    prepared = prepared && !buffer->SetPreparedRegion(reinterpret_cast<RegionInfo*>(root3));
    prepared = prepared && buffer->GetPreparedRegion() == reinterpret_cast<RegionInfo*>(root2);

    MarkStack<BaseObject*> workStack;
    buffer->PushRoot(root1);
    buffer->PushRoot(root2);
    buffer->PushRoot(root3);
    buffer->MergeRoots(workStack);
    bool roots = buffer->stackRoots.empty() && workStack.back() == root3;
    workStack.pop_back();
    roots = roots && workStack.back() == root2;
    workStack.pop_back();
    roots = roots && workStack.back() == root1;
    workStack.pop_back();
    roots = roots && workStack.empty();
    buffer->MergeRoots(workStack);
    roots = roots && workStack.empty();

    std::cout << "ALLOC_BUFFER_LAYOUT size=" << sizeof(AllocBuffer) << " align=" << alignof(AllocBuffer)
              << " tlRegion=" << offsetof(AllocBuffer, tlRegion)
              << " prepared=" << offsetof(AllocBuffer, preparedRegion)
              << " raw=" << offsetof(AllocBuffer, tlRawPointerRegions)
              << " large=" << offsetof(AllocBuffer, tlLargeRawPointerRegions)
              << " roots=" << offsetof(AllocBuffer, stackRoots) << '\n';
    std::cout << "ALLOC_BUFFER_PARITY init=" << init << " names=" << names << " region=" << region
              << " prepared=" << prepared << " roots=" << roots << '\n';
    return init && names && region && prepared && roots ? 0 : 1;
}
