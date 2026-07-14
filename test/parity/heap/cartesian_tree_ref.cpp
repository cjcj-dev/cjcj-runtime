#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <sys/mman.h>

#define private public
#include "/root/cj_build/cangjie_runtime/runtime/src/Heap/Allocator/CartesianTree.h"
#include "/root/cj_build/cangjie_runtime/runtime/src/Heap/Allocator/RegionInfo.h"
#include "/root/cj_build/cangjie_runtime/runtime/src/Heap/Allocator/CartesianTree.cpp"
#undef private

using MapleRuntime::CartesianTree;
using MapleRuntime::RegionInfo;

namespace MapleRuntime {
const size_t RegionInfo::UNIT_SIZE = 4096;
const size_t RegionInfo::LARGE_OBJECT_DEFAULT_THRESHOLD = 8 * RegionInfo::UNIT_SIZE;
size_t RegionInfo::UnitInfo::totalUnitCount = 0;
uintptr_t RegionInfo::UnitInfo::heapStartAddress = 0;
}

namespace {
using Index = CartesianTree::Index;
using Count = CartesianTree::Count;

struct Interval {
    Index index;
    Count count;
};

struct Model {
    std::array<Interval, 2048> intervals{};
    size_t size = 0;

    uint64_t Total() const
    {
        uint64_t total = 0;
        for (size_t i = 0; i < size; ++i) {
            total += intervals[i].count;
        }
        return total;
    }

    bool AnyFit(Count count) const
    {
        for (size_t i = 0; i < size; ++i) {
            if (intervals[i].count >= count) {
                return true;
            }
        }
        return false;
    }

    bool Insert(Index index, Count count)
    {
        if (size == 0) {
            intervals[0] = {index, count};
            size = 1;
            return true;
        }
        if (count == 0) {
            return false;
        }
        const Index end = index + count;
        size_t pos = 0;
        while (pos < size && intervals[pos].index < index) {
            ++pos;
        }
        if (pos > 0 && index < intervals[pos - 1].index + intervals[pos - 1].count) {
            return false;
        }
        if (pos < size && end > intervals[pos].index) {
            return false;
        }
        const bool joinLeft = pos > 0 &&
            intervals[pos - 1].index + intervals[pos - 1].count == index;
        const bool joinRight = pos < size && end == intervals[pos].index;
        if (joinLeft && joinRight) {
            intervals[pos - 1].count += count + intervals[pos].count;
            for (size_t i = pos; i + 1 < size; ++i) {
                intervals[i] = intervals[i + 1];
            }
            --size;
        } else if (joinLeft) {
            intervals[pos - 1].count += count;
        } else if (joinRight) {
            intervals[pos].index = index;
            intervals[pos].count += count;
        } else {
            for (size_t i = size; i > pos; --i) {
                intervals[i] = intervals[i - 1];
            }
            intervals[pos] = {index, count};
            ++size;
        }
        return true;
    }

    bool TakeAt(Index index, Count count)
    {
        for (size_t i = 0; i < size; ++i) {
            if (intervals[i].index == index && intervals[i].count >= count) {
                intervals[i].index += count;
                intervals[i].count -= count;
                if (intervals[i].count == 0) {
                    for (size_t j = i; j + 1 < size; ++j) {
                        intervals[j] = intervals[j + 1];
                    }
                    --size;
                }
                return true;
            }
        }
        return false;
    }

    bool BestFit(Count count, Index& index) const
    {
        bool found = false;
        Count bestCount = 0;
        for (size_t i = 0; i < size; ++i) {
            if (intervals[i].count >= count &&
                (!found || intervals[i].count < bestCount ||
                    (intervals[i].count == bestCount && intervals[i].index < index))) {
                found = true;
                bestCount = intervals[i].count;
                index = intervals[i].index;
            }
        }
        return found;
    }
};

uint64_t operations = 0;
uint64_t records = 0;
uint64_t lifetimes = 0;

[[noreturn]] void Fail(const char* message)
{
    std::fprintf(stderr, "CARTESIAN_REF FAIL %s\n", message);
    std::exit(1);
}

void Require(bool condition, const char* message)
{
    if (!condition) {
        Fail(message);
    }
}

void CheckHeap(const CartesianTree::Node* node, uint64_t low, uint64_t high)
{
    if (node == nullptr) {
        return;
    }
    const uint64_t begin = node->GetIndex();
    const uint64_t end = begin + node->GetCount();
    Require(begin >= low && end <= high, "BST range");
    if (node->l != nullptr) {
        Require(node->l->GetIndex() + node->l->GetCount() < begin, "left ordering");
        Require(node->l->GetCount() <= node->GetCount(), "left max heap");
        CheckHeap(node->l, low, begin);
    }
    if (node->r != nullptr) {
        Require(end < node->r->GetIndex(), "right ordering");
        Require(node->r->GetCount() <= node->GetCount(), "right max heap");
        CheckHeap(node->r, end, high);
    }
}

void Validate(CartesianTree& tree, const Model& model)
{
    std::array<Interval, 2048> actual{};
    size_t actualSize = 0;
    CartesianTree::Iterator iterator(tree);
    ++lifetimes;
    while (auto* node = iterator.Next()) {
        Require(actualSize < actual.size(), "iterator overflow");
        actual[actualSize++] = {node->GetIndex(), node->GetCount()};
    }
    std::sort(actual.begin(), actual.begin() + static_cast<std::ptrdiff_t>(actualSize),
        [](const Interval& left, const Interval& right) { return left.index < right.index; });
    Require(actualSize == model.size, "node count model");
    for (size_t i = 0; i < actualSize; ++i) {
        Require(actual[i].index == model.intervals[i].index &&
            actual[i].count == model.intervals[i].count, "interval model");
    }
    CartesianTree::ForwardIterator forward(tree);
    ++lifetimes;
    size_t slotCount = 0;
    while (auto** slot = forward.Next()) {
        Require(*slot != nullptr, "forward live slot");
        ++slotCount;
    }
    Require(slotCount == model.size, "forward count");
    Require(tree.GetNodeCount() == model.size, "GetNodeCount");
    Require(tree.GetTotalCount() == model.Total(), "total count");
    Require(tree.Empty() == (model.size == 0), "empty state");
    if (!tree.Empty()) {
        Require(tree.RootNode() != nullptr, "root state");
        CheckHeap(tree.RootNode(), 0, UINT64_MAX);
    }
}

void EmitState(uint32_t step, uint32_t action, Index argumentIndex, Count argumentCount,
    bool result, Index resultIndex, const Model& model)
{
    std::printf("T %u %u %u %u %u %u %llu %zu\n", step, action, argumentIndex,
        argumentCount, result ? 1u : 0u, resultIndex,
        static_cast<unsigned long long>(model.Total()), model.size);
    ++records;
    for (size_t i = 0; i < model.size; ++i) {
        std::printf("E %u %zu %u %u\n", step, i, model.intervals[i].index,
            model.intervals[i].count);
        ++records;
    }
}

void RunFixedCases()
{
    CartesianTree tree;
    tree.Init(256);
    Model model;
    Index out = 0xfeedu;
    Require(!tree.TakeUnits(1, out, false), "empty take");
    Require(tree.MergeInsert(10, 0, false) == model.Insert(10, 0), "empty zero insert");
    Validate(tree, model);
    tree.ClearTree();
    model.size = 0;
    Require(tree.MergeInsert(10, 4, false) == model.Insert(10, 4), "first");
    Require(!tree.MergeInsert(20, 0, false), "nonempty zero");
    Require(tree.MergeInsert(30, 5, false) == model.Insert(30, 5), "disjoint");
    Require(tree.MergeInsert(11, 2, false) == model.Insert(11, 2), "clash");
    Require(tree.MergeInsert(14, 3, false) == model.Insert(14, 3), "right merge");
    Require(tree.MergeInsert(27, 3, false) == model.Insert(27, 3), "left merge");
    Require(tree.MergeInsert(17, 10, false) == model.Insert(17, 10), "bridge merge");
    Require(tree.MergeInsert(100, 2, false) == model.Insert(100, 2), "rotation base");
    Require(tree.MergeInsert(50, 8, false) == model.Insert(50, 8), "left rotation");
    Require(tree.MergeInsert(150, 9, false) == model.Insert(150, 9), "right rotation");
    Require(tree.MergeInsert(200, 9, false) == model.Insert(200, 9), "equal tie");
    Validate(tree, model);
    out = 0;
    bool result = tree.TakeUnits(3, out, false);
    Require(result && model.TakeAt(out, 3), "partial take");
    Validate(tree, model);
    out = 0;
    result = tree.TakeUnits(1000, out, false);
    Require(!result && !model.AnyFit(1000), "oversize take");
    Validate(tree, model);
    tree.ClearTree();
    model.size = 0;
    Require(tree.MergeInsert(100, 8, false) == model.Insert(100, 8), "low fit 8");
    Require(tree.MergeInsert(300, 5, false) == model.Insert(300, 5), "low fit 5a");
    Require(tree.MergeInsert(500, 5, false) == model.Insert(500, 5), "low fit 5b");
    Index expected = 0;
    Require(model.BestFit(4, expected), "model low fit");
    out = 0;
    result = tree.TakeUnitsLowAddr(4, out, false);
    Require(result && out == expected && model.TakeAt(out, 4), "low addr tie");
    Validate(tree, model);
    expected = 0;
    Require(model.BestFit(5, expected), "model exact fit");
    out = 0;
    result = tree.TakeUnitsLowAddr(5, out, false);
    Require(result && out == expected && model.TakeAt(out, 5), "exact fit removal");
    Validate(tree, model);
    tree.ClearTree();
    model.size = 0;
    Require(tree.MergeInsert(700, 4, false) == model.Insert(700, 4), "direct node");
    out = 0;
    result = tree.AllocateLowestAddressFromNode(tree.root, 2, out);
    Require(result && model.TakeAt(out, 2), "AllocateLowestAddressFromNode");
    Validate(tree, model);
    tree.ClearTree();
    model.size = 0;
    Validate(tree, model);
    tree.Fini();
    std::printf("F fixed=PASS\n");
    ++records;
}

void RunLargeTrees()
{
    for (uint32_t pass = 0; pass < 2; ++pass) {
        CartesianTree tree;
        tree.Init(1200);
        for (uint32_t i = 0; i < 600; ++i) {
            Require(tree.MergeInsert(i * 2 + pass, 1, false), "large insert");
        }
        Require(tree.GetNodeCount() == 600 && tree.GetTotalCount() == 600,
            "large tree counts");
        CartesianTree::Iterator iterator(tree);
        ++lifetimes;
        size_t count = 0;
        while (iterator.Next() != nullptr) {
            ++count;
        }
        Require(count == 600, "large iterator");
        std::printf("D %u 600 %zu\n", pass, count);
        ++records;
        tree.Fini();
    }
}

void RunIteratorLifetimes()
{
    CartesianTree tree;
    tree.Init(8);
    Require(tree.MergeInsert(10, 2, false), "lifetime root");
    Require(tree.MergeInsert(20, 1, false), "lifetime right");
    for (uint32_t i = 0; i < 1100; ++i) {
        CartesianTree::Iterator iterator(tree);
        ++lifetimes;
        Require(iterator.Next() != nullptr && iterator.Next() != nullptr &&
            iterator.Next() == nullptr, "fresh iterator lifetime");
    }
    tree.Fini();
    std::printf("L 1100 PASS\n");
    ++records;
}

void RunTrace()
{
    CartesianTree tree;
    tree.Init(4096);
    Model model;
    uint64_t seed = 0x4341525445534941ULL;
    for (uint32_t step = 0; step < 1200; ++step) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        uint32_t action = static_cast<uint32_t>((seed >> 32) % 3);
        Index argumentIndex = static_cast<Index>(((seed >> 12) % 1800) * 2);
        Count argumentCount = static_cast<Count>((seed % 9) + 1);
        Index resultIndex = 0xffffffffu;
        bool result = false;
        if (action == 0) {
            const bool expected = model.Insert(argumentIndex, argumentCount);
            result = tree.MergeInsert(argumentIndex, argumentCount, false);
            Require(result == expected, "trace insert result");
        } else if (action == 1) {
            const bool expected = model.AnyFit(argumentCount);
            result = tree.TakeUnits(argumentCount, resultIndex, false);
            Require(result == expected, "trace take result");
            if (result) {
                Require(model.TakeAt(resultIndex, argumentCount), "trace take index");
            }
        } else {
            Index expectedIndex = 0xffffffffu;
            const bool expected = model.BestFit(argumentCount, expectedIndex);
            result = tree.TakeUnitsLowAddr(argumentCount, resultIndex, false);
            Require(result == expected, "trace low result");
            if (result) {
                Require(resultIndex == expectedIndex, "trace low index");
                Require(model.TakeAt(resultIndex, argumentCount), "trace low update");
            }
        }
        ++operations;
        Validate(tree, model);
        EmitState(step, action, argumentIndex, argumentCount, result, resultIndex, model);
    }
    tree.Fini();
    std::printf("R seed=%llu operations=1200\n", static_cast<unsigned long long>(seed));
    ++records;
}

void RunRegionInfo()
{
    constexpr size_t units = 16;
    const size_t mapSize = (units + 1) * RegionInfo::UNIT_SIZE;
    void* mapping = mmap(nullptr, mapSize, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    Require(mapping != MAP_FAILED, "region mmap");
    const uintptr_t heap = reinterpret_cast<uintptr_t>(mapping) + RegionInfo::UNIT_SIZE;
    RegionInfo::UnitInfo::heapStartAddress = heap;
    RegionInfo::UnitInfo::totalUnitCount = units;

    CartesianTree tree;
    tree.Init(16);
    Require(tree.MergeInsert(2, 3, true), "refresh insert");
    auto* region = reinterpret_cast<RegionInfo*>(RegionInfo::UnitInfo::GetUnitInfo(2));
    const auto& metadata = region->metadata;
    std::printf("G refresh %llu %llu %u %u %u %u %u %u %u %u %u %u %d\n",
        static_cast<unsigned long long>((metadata.allocPtr - heap) / RegionInfo::UNIT_SIZE),
        static_cast<unsigned long long>((metadata.regionEnd - heap) / RegionInfo::UNIT_SIZE),
        metadata.nextRegionIdx, metadata.prevRegionIdx, metadata.liveByteCount,
        metadata.liveInfo == nullptr ? 0u : 1u, static_cast<unsigned>(region->GetRegionType()),
        static_cast<unsigned>(region->GetUnitRole()), metadata.isTraceRegion,
        metadata.isMarked, metadata.isEnqueued, metadata.isResurrected,
        metadata.rawPointerObjectCount);
    ++records;
    tree.ClearTree();
    auto* unit = reinterpret_cast<uint8_t*>(heap + RegionInfo::UNIT_SIZE);
    unit[0] = 0xabu;
    Require(tree.MergeInsert(1, 1, false), "release insert");
    tree.ReleaseRootNode();
    Require(unit[0] == 0u && tree.Empty() && tree.GetTotalCount() == 0u,
        "physical release");
    std::printf("G release 1 0\n");
    ++records;
    tree.Fini();
    Require(munmap(mapping, mapSize) == 0, "region munmap");
}
} // namespace

int main()
{
    std::printf("CARTESIAN_NODE_LAYOUT sizeof=%zu align=%zu l=%zu r=%zu index=%zu count=%zu\n",
        sizeof(CartesianTree::Node), alignof(CartesianTree::Node),
        offsetof(CartesianTree::Node, l), offsetof(CartesianTree::Node, r),
        offsetof(CartesianTree::Node, index), offsetof(CartesianTree::Node, count));
    std::printf("CARTESIAN_NODE_FIELDS l_width=%zu r_width=%zu index_width=%zu count_width=%zu\n",
        sizeof(CartesianTree::Node::l), sizeof(CartesianTree::Node::r),
        sizeof(CartesianTree::Node::index), sizeof(CartesianTree::Node::count));
    records += 2;
    RunFixedCases();
    RunLargeTrees();
    RunIteratorLifetimes();
    RunTrace();
    RunRegionInfo();
    std::printf("S operations=%llu lifetimes=%llu records=%llu\n",
        static_cast<unsigned long long>(operations),
        static_cast<unsigned long long>(lifetimes),
        static_cast<unsigned long long>(records));
    return 0;
}
