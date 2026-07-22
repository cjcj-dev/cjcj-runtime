// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <list>
#include <mutex>
#include <new>

// Expose AllocBuffer's data members so this bridge can repeat the production
// offsetof contract from RegionSpace.cpp:143-144 for every field. Standard
// headers must be included first so the macro cannot affect libstdc++.
#define private public
#include "Heap/Allocator/AllocBuffer.h"
#undef private

namespace {
using MapleRuntime::AllocBuffer;
using MapleRuntime::BaseObject;
using MapleRuntime::MarkStack;
using MapleRuntime::RegionInfo;
using StackRoots = std::list<BaseObject*>;
using PreparedRegion = std::atomic<RegionInfo*>;

static_assert(sizeof(PreparedRegion) == sizeof(void*), "AllocBuffer preparedRegion ABI changed");
static_assert(alignof(PreparedRegion) == alignof(void*), "AllocBuffer preparedRegion alignment changed");
static_assert(sizeof(StackRoots) == 3 * sizeof(void*), "AllocBuffer stackRoots ABI changed");
static_assert(alignof(AllocBuffer) == alignof(void*), "AllocBuffer alignment ABI changed");
static_assert(offsetof(AllocBuffer, tlRegion) == 0, "AllocBuffer tlRegion offset changed");
static_assert(offsetof(AllocBuffer, preparedRegion) == sizeof(void*),
              "AllocBuffer preparedRegion offset changed");
static_assert(offsetof(AllocBuffer, tlRawPointerRegions) == 2 * sizeof(void*),
              "AllocBuffer tlRawPointerRegions offset changed");
static_assert(offsetof(AllocBuffer, tlLargeRawPointerRegions) ==
                  2 * sizeof(void*) + sizeof(MapleRuntime::RegionList),
              "AllocBuffer tlLargeRawPointerRegions offset changed");
static_assert(offsetof(AllocBuffer, stackRoots) ==
                  2 * sizeof(void*) + 2 * sizeof(MapleRuntime::RegionList),
              "AllocBuffer stackRoots offset changed");
static_assert(sizeof(AllocBuffer) ==
                  2 * sizeof(void*) + 2 * sizeof(MapleRuntime::RegionList) + sizeof(StackRoots),
              "AllocBuffer size ABI changed");
} // namespace

extern "C" RegionInfo* CJRT_AllocBufferNullRegion() { return RegionInfo::NullRegion(); }

extern "C" void CJRT_AllocBufferPreparedConstruct(void* storage)
{
    new (storage) PreparedRegion(nullptr);
}

extern "C" RegionInfo* CJRT_AllocBufferPreparedLoadRelaxed(void* storage)
{
    return reinterpret_cast<PreparedRegion*>(storage)->load(std::memory_order_relaxed);
}

extern "C" int32_t CJRT_AllocBufferPreparedCompareExchangeRelease(void* storage, RegionInfo* desired)
{
    RegionInfo* expected = nullptr;
    return reinterpret_cast<PreparedRegion*>(storage)->compare_exchange_strong(
               expected, desired, std::memory_order_release)
        ? 1
        : 0;
}

extern "C" void CJRT_AllocBufferStackRootsConstruct(void* storage) { new (storage) StackRoots(); }

extern "C" void CJRT_AllocBufferStackRootsDestroy(void* storage)
{
    reinterpret_cast<StackRoots*>(storage)->~StackRoots();
}

extern "C" void CJRT_AllocBufferPushRoot(void* storage, BaseObject* root)
{
    reinterpret_cast<StackRoots*>(storage)->emplace_back(root);
}

extern "C" void CJRT_AllocBufferMergeRoots(void* storage, void* opaqueWorkStack)
{
    auto& roots = *reinterpret_cast<StackRoots*>(storage);
    if (roots.empty()) {
        return;
    }
    auto& workStack = *reinterpret_cast<MarkStack<BaseObject*>*>(opaqueWorkStack);
    for (BaseObject* object : roots) {
        workStack.push_back(object);
    }
    roots.clear();
}
