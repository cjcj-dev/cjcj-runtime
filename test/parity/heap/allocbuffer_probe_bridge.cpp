// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

#include <cstdint>
#include <cstring>
#include <functional>
#include <list>
#include <mutex>
#include <new>

namespace MapleRuntime {
class BaseObject;
}

#include "Common/MarkWorkStack.h"

#define private public
#define protected public
#include "Heap/Allocator/AllocBuffer.h"
#undef protected
#undef private

using MapleRuntime::BaseObject;
using MapleRuntime::MarkStack;
using MapleRuntime::AllocBuffer;
using StackRoots = std::list<BaseObject*>;

extern "C" void* CJRT_TestAllocBufferWorkStackNew() { return new MarkStack<BaseObject*>(); }

extern "C" void CJRT_TestAllocBufferWorkStackDelete(void* stack)
{
    delete reinterpret_cast<MarkStack<BaseObject*>*>(stack);
}

extern "C" int32_t CJRT_TestAllocBufferWorkStackEmpty(void* stack)
{
    return reinterpret_cast<MarkStack<BaseObject*>*>(stack)->empty() ? 1 : 0;
}

extern "C" void* CJRT_TestAllocBufferWorkStackBack(void* stack)
{
    return reinterpret_cast<MarkStack<BaseObject*>*>(stack)->back();
}

extern "C" void CJRT_TestAllocBufferWorkStackPop(void* stack)
{
    reinterpret_cast<MarkStack<BaseObject*>*>(stack)->pop_back();
}

extern "C" int32_t CJRT_TestAllocBufferRootsEmpty(void* storage)
{
    return reinterpret_cast<StackRoots*>(storage)->empty() ? 1 : 0;
}

extern "C" void CJRT_TestAllocBufferDestroyRoots(void* storage)
{
    reinterpret_cast<StackRoots*>(storage)->~StackRoots();
}

extern "C" int32_t CJRT_TestAllocBufferNames(AllocBuffer* buffer)
{
    return std::strcmp(buffer->tlRawPointerRegions.listName, "thread-local raw-pointer regions") == 0 &&
            std::strcmp(buffer->tlLargeRawPointerRegions.listName,
                        "thread-local large raw-pointer regions") == 0
        ? 1
        : 0;
}
