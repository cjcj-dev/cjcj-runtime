#include <array>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "ObjectModel/MClass.h"

using namespace MapleRuntime;

static void Print(const char* name, uintptr_t base, const std::vector<uintptr_t>& fields)
{
    std::cout << name << " count=" << fields.size() << " offsets=";
    for (size_t i = 0; i < fields.size(); ++i) {
        if (i != 0) {
            std::cout << ',';
        }
        std::cout << fields[i] - base;
    }
    std::cout << '\n';
}

int main()
{
    std::array<uintptr_t, 24> fields{};
    uintptr_t base = reinterpret_cast<uintptr_t>(fields.data());
    auto visitor = [](std::vector<uintptr_t>& result) {
        return [&result](RefField<>& field) { result.push_back(reinterpret_cast<uintptr_t>(&field)); };
    };

    GCTib shortTib{};
    shortTib.tag = 0x8000000000000125ULL;
    std::vector<uintptr_t> result;
    shortTib.ForEachBitmapWord(base, visitor(result));
    std::cout << "LAYOUT short=" << sizeof(ShortGCTib) << '/' << alignof(ShortGCTib)
              << " std=" << sizeof(StdGCTib) << '/' << alignof(StdGCTib)
              << " gctib=" << sizeof(GCTib) << '/' << alignof(GCTib) << '\n';
    Print("SHORT", base, result);

    result.clear();
    shortTib.ForEachBitmapWordInRange(base, visitor(result), base + 9, base + 70);
    Print("SHORT_RANGE", base, result);

    alignas(StdGCTib) std::array<uint8_t, 8> storage{};
    auto* standard = reinterpret_cast<StdGCTib*>(storage.data());
    standard->nBitmapWords = 3;
    standard->bitmapWords[0] = 0x81;
    standard->bitmapWords[1] = 0x12;
    standard->bitmapWords[2] = 0x40;
    GCTib longTib{};
    longTib.gctib = standard;
    result.clear();
    longTib.ForEachBitmapWord(base, visitor(result));
    Print("STD", base, result);

    result.clear();
    longTib.ForEachBitmapWordInRange(base, visitor(result), base + 65, base + 180);
    Print("STD_RANGE", base, result);
}
