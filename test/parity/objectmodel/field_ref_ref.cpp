#include <cstdint>
#include <cstring>
#include <iostream>

#include "ObjectModel/Field.inline.h"
#include "ObjectModel/RefField.inline.h"

using namespace MapleRuntime;

int main()
{
    alignas(Field<int32_t>) uint8_t plainBytes[sizeof(Field<int32_t>)]{};
    auto* plain = reinterpret_cast<Field<int32_t>*>(plainBytes);
    int32_t initial = -17;
    std::memcpy(plainBytes, &initial, sizeof(initial));
    std::cout << "LAYOUT field_i32=" << sizeof(Field<int32_t>) << '/' << alignof(Field<int32_t>)
              << " ref=" << sizeof(RefField<>) << '/' << alignof(RefField<>) << '\n';
    std::cout << "PLAIN get=" << plain->GetFieldValue() << '\n';

    alignas(Field<uint32_t, true>) uint8_t atomicBytes[sizeof(Field<uint32_t, true>)]{};
    auto* atomic = reinterpret_cast<Field<uint32_t, true>*>(atomicBytes);
    atomic->SetFieldValue(nullptr, 10, std::memory_order_release);
    uint32_t load = atomic->GetFieldValue(std::memory_order_acquire);
    bool casOk = atomic->CompareExchange(10, 20, std::memory_order_acq_rel, std::memory_order_acquire);
    bool casFail = atomic->CompareExchange(10, 30, std::memory_order_seq_cst, std::memory_order_seq_cst);
    uint32_t exchanged = atomic->Exchange(40, std::memory_order_seq_cst);
    uint32_t added = atomic->FetchAdd(2, std::memory_order_relaxed);
    uint32_t subbed = atomic->FetchSub(3, std::memory_order_relaxed);
    uint32_t anded = atomic->FetchAnd(0x2f, std::memory_order_relaxed);
    uint32_t ored = atomic->FetchOr(0x80, std::memory_order_relaxed);
    uint32_t xored = atomic->FetchXor(0x0f, std::memory_order_relaxed);
    std::cout << "ATOMIC load=" << load << " cas_ok=" << casOk << " cas_fail=" << casFail
              << " exchange=" << exchanged << " add=" << added << " sub=" << subbed
              << " and=" << anded << " or=" << ored << " xor=" << xored
              << " final=" << atomic->GetFieldValue() << '\n';

    auto* object = reinterpret_cast<BaseObject*>(uintptr_t{0x123456789ab0});
    RefField<> plainRef(object, 1, 1);
    std::cout << "REF raw=" << plainRef.GetFieldValue() << " address=" << plainRef.GetAddress()
              << " tagged=" << plainRef.IsTagged() << " tag=" << plainRef.GetTagID() << '\n';
    plainRef.SetTargetObject(reinterpret_cast<BaseObject*>(uintptr_t{0x223344556670}));
    std::cout << "REF_SET raw=" << plainRef.GetFieldValue()
              << " target=" << reinterpret_cast<uintptr_t>(plainRef.GetTargetObject()) << '\n';

    RefField<true> atomicRef(reinterpret_cast<BaseObject*>(uintptr_t{0x1000}));
    auto old = atomicRef.Exchange(uintptr_t{0x2000}, std::memory_order_acq_rel);
    bool refCasOk = atomicRef.CompareExchange(uintptr_t{0x2000}, uintptr_t{0x3000},
        std::memory_order_seq_cst, std::memory_order_acquire);
    bool refCasFail = atomicRef.CompareExchange(uintptr_t{0x2000}, uintptr_t{0x4000},
        std::memory_order_seq_cst, std::memory_order_acquire);
    std::cout << "ATOMIC_REF old=" << old << " final=" << atomicRef.GetFieldValue()
              << " cas_ok=" << refCasOk << " cas_fail=" << refCasFail << '\n';
}
