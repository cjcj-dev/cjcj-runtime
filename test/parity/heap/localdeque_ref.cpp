#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "Base/Panic.h"
#include "Heap/Allocator/MemMap.h"
#define private public
#include "Heap/Allocator/LocalDeque.h"
#undef private

using MapleRuntime::LocalDeque;
using MapleRuntime::RTAllocatorT;
using MapleRuntime::SingleUseDeque;

namespace {
using Value = void*;

uint64_t operations = 0;
uint64_t records = 0;

[[noreturn]] void Fail(const char* message)
{
    std::fprintf(stderr, "LOCALDEQUE_REF FAIL %s\n", message);
    std::exit(1);
}

void Require(bool condition, const char* message)
{
    if (!condition) {
        Fail(message);
    }
}

Value Pointer(uint64_t value)
{
    return reinterpret_cast<Value>(static_cast<uintptr_t>(value));
}

uint64_t Token(Value value)
{
    return static_cast<uint64_t>(reinterpret_cast<uintptr_t>(value));
}

void PrintLayout()
{
    using Deque = LocalDeque<Value>;
    Deque* deque = nullptr;
    std::printf("LOCALDEQUE_LAYOUT sizeof=%zu align=%zu front=%zu top=%zu sud=%zu array=%zu local_length=%d\n",
        sizeof(Deque), alignof(Deque), offsetof(Deque, front), offsetof(Deque, top),
        offsetof(Deque, sud), offsetof(Deque, array), Deque::LOCAL_LENGTH);
    std::printf(
        "LOCALDEQUE_FIELDS front_width=%zu front_align=%zu top_width=%zu top_align=%zu "
        "sud_width=%zu sud_align=%zu array_width=%zu array_align=%zu\n",
        sizeof(deque->front), alignof(decltype(deque->front)), sizeof(deque->top),
        alignof(decltype(deque->top)), sizeof(deque->sud), alignof(decltype(deque->sud)),
        sizeof(deque->array), alignof(decltype(deque->array)));
}

struct Model {
    std::array<uint64_t, 1024> values{};
    size_t head = 0;
    size_t length = 0;

    void Push(uint64_t value)
    {
        Require(length < values.size(), "model overflow");
        values[(head + length) % values.size()] = value;
        ++length;
    }

    uint64_t Front() const { return values[head]; }
    uint64_t Top() const { return values[(head + length - 1) % values.size()]; }
    void Pop() { --length; }
    void PopFront()
    {
        head = (head + 1) % values.size();
        --length;
    }
};
} // namespace

int main()
{
    PrintLayout();

    RTAllocatorT<16, 8> allocator;
    allocator.Init(4096);
    auto* alloc0 = static_cast<uint8_t*>(allocator.Allocate());
    auto* alloc1 = static_cast<uint8_t*>(allocator.Allocate());
    auto* alloc2 = static_cast<uint8_t*>(allocator.Allocate());
    Require(alloc1 - alloc0 == 16 && alloc2 - alloc1 == 16, "RTAllocatorT spacing");
    allocator.Deallocate(alloc1);
    Require(allocator.Allocate() == alloc1, "RTAllocatorT reuse");
    allocator.Fini();
    std::printf("SMOKE RTAllocatorT spacing=16 reuse=1\n");
    ++records;

    SingleUseDeque<Value> singleUse;
    singleUse.Init(16384);
    Require(singleUse.Empty(), "SingleUseDeque initial empty");
    singleUse.Push(Pointer(11));
    singleUse.Push(Pointer(22));
    singleUse.Push(Pointer(33));
    Require(Token(singleUse.Front()) == 11 && Token(singleUse.Top()) == 33,
        "SingleUseDeque ends");
    singleUse.PopFront();
    singleUse.Pop();
    Require(Token(singleUse.Front()) == 22 && Token(singleUse.Top()) == 22,
        "SingleUseDeque pops");
    singleUse.Clear();
    Require(singleUse.Empty(), "SingleUseDeque clear");
    std::printf("SMOKE SingleUseDeque front=22 top=22 clear_empty=1\n");
    ++records;

    {
        LocalDeque<Value> deque(singleUse);
        bool empty = deque.Empty();
        ++operations;
        Require(empty, "initial empty");
        std::printf("CASE empty initial=1\n");
        ++records;
    }

    {
        LocalDeque<Value> deque(singleUse);
        deque.Push(Pointer(11)); ++operations;
        deque.Push(Pointer(22)); ++operations;
        deque.Push(Pointer(33)); ++operations;
        uint64_t top = Token(deque.Top()); ++operations;
        uint64_t front = Token(deque.Front()); ++operations;
        deque.Pop(); ++operations;
        uint64_t afterPop = Token(deque.Top()); ++operations;
        deque.PopFront(); ++operations;
        uint64_t afterPopFront = Token(deque.Front()); ++operations;
        bool empty = deque.Empty(); ++operations;
        Require(top == 33 && front == 11 && afterPop == 22 && afterPopFront == 22 && !empty,
            "inline LIFO/FIFO");
        std::printf("CASE inline top=33 front=11 after_pop=22 after_popfront=22 empty=0\n");
        ++records;
    }

    for (int count : {511, 512, 513}) {
        LocalDeque<Value> deque(singleUse);
        for (int i = 0; i < count; ++i) {
            deque.Push(Pointer(static_cast<uint64_t>(i + 1)));
            ++operations;
        }
        uint64_t front = Token(deque.Front()); ++operations;
        uint64_t top = Token(deque.Top()); ++operations;
        bool empty = deque.Empty(); ++operations;
        Require(front == 1 && top == static_cast<uint64_t>(count) && !empty,
            "exact push count");
        std::printf("CASE exact pushes=%d front=%llu top=%llu empty=0\n", count,
            static_cast<unsigned long long>(front), static_cast<unsigned long long>(top));
        ++records;
    }

    {
        LocalDeque<Value> deque(singleUse);
        for (uint64_t value = 1; value <= 513; ++value) {
            deque.Push(Pointer(value)); ++operations;
        }
        uint64_t spillTop = Token(deque.Top()); ++operations;
        uint64_t inlineFront = Token(deque.Front()); ++operations;
        deque.Pop(); ++operations;
        uint64_t boundaryTop = Token(deque.Top()); ++operations;
        bool empty = deque.Empty(); ++operations;
        Require(spillTop == 513 && inlineFront == 1 && boundaryTop == 512 && !empty,
            "spill pop front-less branch");
        std::printf("CASE spill_front_lt spill_top=513 inline_front=1 boundary_top=512 empty=0\n");
        ++records;
    }

    {
        LocalDeque<Value> deque(singleUse);
        for (uint64_t value = 1; value <= 514; ++value) {
            deque.Push(Pointer(value)); ++operations;
        }
        uint64_t top = Token(deque.Top()); ++operations;
        deque.Pop(); ++operations;
        uint64_t afterOne = Token(deque.Top()); ++operations;
        deque.Pop(); ++operations;
        uint64_t boundaryTop = Token(deque.Top()); ++operations;
        bool empty = deque.Empty(); ++operations;
        Require(top == 514 && afterOne == 513 && boundaryTop == 512 && !empty,
            "multi-spill Pop boundary");
        std::printf("CASE spill_multi_pop top=514 after_one=513 boundary_top=512 empty=0\n");
        ++records;
    }

    {
        LocalDeque<Value> deque(singleUse);
        for (uint64_t value = 1; value <= 513; ++value) {
            deque.Push(Pointer(value)); ++operations;
        }
        for (int i = 0; i < 512; ++i) {
            deque.PopFront(); ++operations;
        }
        uint64_t spillFront = Token(deque.Front()); ++operations;
        deque.Pop(); ++operations;
        bool resetEmpty = deque.Empty(); ++operations;
        deque.Push(Pointer(777)); ++operations;
        uint64_t resetTop = Token(deque.Top()); ++operations;
        uint64_t resetFront = Token(deque.Front()); ++operations;
        Require(spillFront == 513 && resetEmpty && resetTop == 777 && resetFront == 777,
            "spill front equals reset branch");
        std::printf("CASE spill_front_eq spill_front=513 reset_empty=1 reset_top=777 reset_front=777\n");
        ++records;
    }

    {
        LocalDeque<Value> deque(singleUse);
        for (uint64_t value = 1; value <= 513; ++value) {
            deque.Push(Pointer(value)); ++operations;
        }
        for (int i = 0; i < 512; ++i) {
            deque.PopFront(); ++operations;
        }
        uint64_t boundaryFront = Token(deque.Front()); ++operations;
        deque.PopFront(); ++operations;
        bool empty = deque.Empty(); ++operations;
        Require(boundaryFront == 513 && empty, "spill pop-front boundary");
        std::printf("CASE spill_popfront boundary_front=513 empty=1\n");
        ++records;
    }

    {
        LocalDeque<Value> deque(singleUse);
        for (uint64_t value = 1; value <= 514; ++value) {
            deque.Push(Pointer(value)); ++operations;
        }
        for (int i = 0; i < 512; ++i) {
            deque.PopFront(); ++operations;
        }
        uint64_t firstSpill = Token(deque.Front()); ++operations;
        deque.PopFront(); ++operations;
        uint64_t secondSpill = Token(deque.Front()); ++operations;
        deque.PopFront(); ++operations;
        bool empty = deque.Empty(); ++operations;
        Require(firstSpill == 513 && secondSpill == 514 && empty,
            "multi-spill PopFront boundary");
        std::printf("CASE spill_multi_popfront first=513 second=514 empty=1\n");
        ++records;
    }

    constexpr int lifetimeCount = 1100;
    for (int lifetime = 0; lifetime < lifetimeCount; ++lifetime) {
        LocalDeque<Value> deque(singleUse);
        int pushes = lifetime % 4 == 0 ? 513 : 3;
        uint64_t first = 0;
        uint64_t last = 0;
        for (int i = 0; i < pushes; ++i) {
            uint64_t value = (static_cast<uint64_t>(lifetime) * 17 +
                static_cast<uint64_t>(i) * 13) % 4000 + 1;
            if (i == 0) {
                first = value;
            }
            last = value;
            deque.Push(Pointer(value)); ++operations;
        }
        uint64_t top = Token(deque.Top()); ++operations;
        uint64_t front = Token(deque.Front()); ++operations;
        deque.Pop(); ++operations;
        uint64_t afterPop = Token(deque.Top()); ++operations;
        deque.PopFront(); ++operations;
        uint64_t afterPopFront = Token(deque.Front()); ++operations;
        bool empty = deque.Empty(); ++operations;
        Require(top == last && front == first && !empty, "fresh lifetime ends");
        std::printf(
            "LIFETIME id=%d pushes=%d top=%llu front=%llu after_pop=%llu after_popfront=%llu empty=0\n",
            lifetime, pushes, static_cast<unsigned long long>(top),
            static_cast<unsigned long long>(front), static_cast<unsigned long long>(afterPop),
            static_cast<unsigned long long>(afterPopFront));
        ++records;
    }

    LocalDeque<Value> mixed(singleUse);
    Model model;
    uint64_t seed = 0x4c4f43414c444551ULL;
    constexpr int mixedSteps = 1200;
    for (int step = 0; step < mixedSteps; ++step) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        int action = static_cast<int>(seed % 6);
        if (model.length == 0) {
            action = 0;
        } else if (model.length >= 700) {
            action = (seed & 1) == 0 ? 3 : 5;
        }

        const char* name = nullptr;
        uint64_t argument = 0;
        uint64_t result = 0;
        if (action <= 1) {
            name = "PUSH";
            argument = (static_cast<uint64_t>(step) * 37 + (seed >> 17)) % 4000 + 1;
            mixed.Push(Pointer(argument)); ++operations;
            model.Push(argument);
            result = argument;
        } else if (action == 2) {
            name = "TOP";
            result = Token(mixed.Top()); ++operations;
            Require(result == model.Top(), "mixed Top");
        } else if (action == 3) {
            name = "POP";
            result = Token(mixed.Top()); ++operations;
            Require(result == model.Top(), "mixed Pop result");
            mixed.Pop(); ++operations;
            model.Pop();
        } else if (action == 4) {
            name = "FRONT";
            result = Token(mixed.Front()); ++operations;
            Require(result == model.Front(), "mixed Front");
        } else {
            name = "POPFRONT";
            result = Token(mixed.Front()); ++operations;
            Require(result == model.Front(), "mixed PopFront result");
            mixed.PopFront(); ++operations;
            model.PopFront();
        }

        bool empty = mixed.Empty(); ++operations;
        Require(empty == (model.length == 0), "mixed Empty");
        uint64_t stateFront = 0;
        uint64_t stateTop = 0;
        if (model.length != 0) {
            stateFront = Token(mixed.Front()); ++operations;
            stateTop = Token(mixed.Top()); ++operations;
            Require(stateFront == model.Front() && stateTop == model.Top(), "mixed full state");
        }
        std::printf(
            "TRACE step=%d op=%s arg=%llu result=%llu len=%zu front=%llu top=%llu empty=%d\n",
            step, name, static_cast<unsigned long long>(argument),
            static_cast<unsigned long long>(result), model.length,
            static_cast<unsigned long long>(stateFront), static_cast<unsigned long long>(stateTop),
            empty ? 1 : 0);
        ++records;
    }
    std::printf("MIXED PASS seed=%llu steps=%d final_len=%zu\n",
        static_cast<unsigned long long>(seed), mixedSteps, model.length);
    ++records;

    singleUse.Fini();
    std::printf("LOCALDEQUE_PARITY PASS lifetimes=%d operations=%llu records=%llu\n",
        lifetimeCount, static_cast<unsigned long long>(operations),
        static_cast<unsigned long long>(records));
    return 0;
}
