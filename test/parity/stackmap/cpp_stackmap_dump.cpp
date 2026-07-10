#include "stackmap_api.h"
#include "elf_stackmap.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <vector>

#include "CangjieRuntime.h"
#include "StackMap/CompressedStackMap.h"

namespace MapleRuntime {
StackGrowConfig CangjieRuntime::stackGrowConfig = StackGrowConfig::UNDEF;
}

namespace {
using namespace MapleRuntime;

constexpr uint32_t EVENT_HEADER = 1;
constexpr uint32_t EVENT_PROLOGUE = 2;
constexpr uint32_t EVENT_ROW = 3;
constexpr uint32_t EVENT_REG_ROOT = 4;
constexpr uint32_t EVENT_SLOT_ROOT = 5;
constexpr uint32_t EVENT_DERIVED_REG_ROOT = 6;
constexpr uint32_t EVENT_DERIVED_SLOT_ROOT = 7;
constexpr uint32_t EVENT_STACK_REG_ROOT = 8;
constexpr uint32_t EVENT_STACK_SLOT_ROOT = 9;

struct FakeFrame {
    std::vector<uint8_t> storage;
    uint8_t* base;
    std::array<std::array<ObjectRef, 2>, Register::REGISTERS_COUNT> registers{};

    explicit FakeFrame(uint32_t stackSize)
    {
        const size_t half = std::max<size_t>(1U << 20, static_cast<size_t>(stackSize) * 16 + (1U << 16));
        storage.resize(half * 2 + 32);
        const uintptr_t middle = reinterpret_cast<uintptr_t>(storage.data() + half);
        base = reinterpret_cast<uint8_t*>((middle + 15) & ~uintptr_t{15});
    }

    RegSlotsMap FreshRegisters()
    {
        RegSlotsMap map;
        for (uint32_t reg = 0; reg < Register::REGISTERS_COUNT; ++reg) {
            map.Insert(reg, &registers[reg][0]);
        }
        return map;
    }

    bool IsStackAddress(const uintptr_t address) const
    {
        const uintptr_t begin = reinterpret_cast<uintptr_t>(storage.data());
        return address >= begin && address + sizeof(uintptr_t) <= begin + storage.size();
    }
};

void Add(std::vector<StackMapEvent>& events, uint32_t kind, uint32_t row, int64_t value0, int64_t value1)
{
    events.push_back({kind, row, value0, value1});
}

uint64_t CollectRegisters(const RegRoot& root, FakeFrame& frame, uint32_t kind, uint32_t pc,
                          std::vector<StackMapEvent>& events)
{
    auto map = frame.FreshRegisters();
    std::array<uint32_t, Register::REGISTERS_COUNT> subSlots{};
    uint64_t baseRoots = 0;
    root.VisitGCRoots([](ObjectRef&) {}, [&](RegisterNum reg, const BaseObject*) {
        Add(events, kind, pc, reg, subSlots[reg]++);
        if (reg <= Register::R15) {
            ++baseRoots;
        }
    }, map);
    return baseRoots;
}

uint64_t CollectSlots(const SlotRoot& root, FakeFrame& frame, uint32_t kind, uint32_t pc,
                      std::vector<StackMapEvent>& events)
{
    uint64_t roots = 0;
    root.VisitGCRoots([](ObjectRef&) {}, [&](SlotBias bias, BaseObject*) {
        Add(events, kind, pc, bias, 0);
        ++roots;
    }, reinterpret_cast<uintptr_t>(frame.base));
    return roots;
}

std::vector<StackMapEvent> DecodeWithCpp(const cjrt::parity::FunctionStackMap& function, bool stackGrow)
{
    auto* bytes = const_cast<uint8_t*>(function.bytes.data());
    StacksizeVarInt stackSize(bytes, 0);
    StacksizeVarInt format(stackSize.GetNextTable());
    std::vector<uint32_t> prologueRegisters;
    std::vector<uint32_t> prologueOffsets;
    PrologueVisitor prologueVisitor = [&](PrologueRegisterClosure::Type type, U32 value) {
        if (type == PrologueRegisterClosure::Type::CALLEE_REGISTER) {
            prologueRegisters.push_back(value);
        } else {
            prologueOffsets.push_back(value);
        }
    };
    CompressedStackMapHead head(format.GetNextTable(), prologueVisitor, format.GetStacksize());

    std::vector<StackMapEvent> events;
    Add(events, EVENT_HEADER, 0, stackSize.GetStacksize(), format.GetStacksize());
    if (prologueRegisters.size() != prologueOffsets.size()) {
        throw std::runtime_error("C++ decoder returned an unpaired prologue");
    }
    for (size_t i = 0; i < prologueRegisters.size(); ++i) {
        Add(events, EVENT_PROLOGUE, 0, prologueRegisters[i], prologueOffsets[i]);
    }

    FakeFrame frame(stackSize.GetStacksize());
    for (uint32_t pc = 0; pc <= function.codeSize; ++pc) {
        auto entry = head.GetStackMapEntry(0, pc);
        if (!entry.IsValid()) {
            continue;
        }
        Add(events, EVENT_ROW, pc, pc, entry.BuildLineNum());
        const uint64_t regRoots = CollectRegisters(entry.BuildRegRoot(), frame, EVENT_REG_ROOT, pc, events);
        const uint64_t slotRoots = CollectSlots(entry.BuildSlotRoot(), frame, EVENT_SLOT_ROOT, pc, events);

        auto derived = entry.BuildDerivedPtrRoot();
        for (uint64_t baseOrdinal = 0; baseOrdinal < regRoots + slotRoots; ++baseOrdinal) {
            auto map = frame.FreshRegisters();
            const auto visitor = [&](BasePtrType, DerivedPtrType& value) {
                const uintptr_t address = reinterpret_cast<uintptr_t>(&value);
                if (frame.IsStackAddress(address)) {
                    Add(events, EVENT_DERIVED_SLOT_ROOT, pc, baseOrdinal,
                        static_cast<int64_t>(address) -
                            static_cast<int64_t>(reinterpret_cast<uintptr_t>(frame.base)));
                    return;
                }
                for (uint32_t reg = 0; reg < Register::REGISTERS_COUNT; ++reg) {
                    for (uint32_t subSlot = 0; subSlot < 2; ++subSlot) {
                        if (address == reinterpret_cast<uintptr_t>(&frame.registers[reg][subSlot])) {
                            Add(events, EVENT_DERIVED_REG_ROOT, pc, baseOrdinal, reg * 2 + subSlot);
                            return;
                        }
                    }
                }
                throw std::runtime_error("C++ derived root points outside the fake frame");
            };
            if (!derived.VisitDerivedPtr(visitor, nullptr, map, 1, reinterpret_cast<uintptr_t>(frame.base))) {
                break;
            }
        }
        if (stackGrow) {
            CollectRegisters(entry.BuildStackRegRoot(), frame, EVENT_STACK_REG_ROOT, pc, events);
            CollectSlots(entry.BuildStackSlotRoot(), frame, EVENT_STACK_SLOT_ROOT, pc, events);
        }
    }
    return events;
}
} // namespace

int main(int argc, char** argv)
{
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s OBJECT.o...\n", argv[0]);
        return 2;
    }
    try {
        for (int i = 1; i < argc; ++i) {
            const auto object = cjrt::parity::ReadObjectStackMaps(argv[i]);
            MapleRuntime::CangjieRuntime::stackGrowConfig = object.stackGrow ?
                MapleRuntime::StackGrowConfig::STACK_GROW_ON : MapleRuntime::StackGrowConfig::STACK_GROW_OFF;
            std::printf("OBJECT %s %zu %u\n", cjrt::parity::BaseName(object.path).c_str(),
                        object.functions.size(), object.stackGrow ? 1U : 0U);
            for (const auto& function : object.functions) {
                std::printf("FUNCTION %u %llu %u\n", function.methodIndex,
                            static_cast<unsigned long long>(function.sectionOffset), function.codeSize);
                for (const auto& event : DecodeWithCpp(function, object.stackGrow)) {
                    cjrt::parity::PrintEvent(event);
                }
            }
        }
    } catch (const std::exception& error) {
        std::fprintf(stderr, "stackmap C++ dump failed: %s\n", error.what());
        return 1;
    }
    return 0;
}
