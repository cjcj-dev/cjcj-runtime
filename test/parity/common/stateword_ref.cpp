#include <array>
#include <atomic>
#include <cinttypes>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <new>
#include <pthread.h>

#ifdef STATEWORD_ORACLE
#define private public
#include "Common/StateWord.h"
#undef private
using MapleRuntime::ObjectState;
using MapleRuntime::StateWord;
#else
struct ObjectState;
struct StateWord;
extern "C" void CJRT_ObjectStateConstructZero(ObjectState*);
extern "C" void CJRT_ObjectStateConstructRaw(ObjectState*, uint16_t);
extern "C" void CJRT_ObjectStateConstructCode(ObjectState*, uint8_t);
extern "C" void CJRT_ObjectStateConstructCopy(ObjectState*, ObjectState*);
extern "C" uint16_t CJRT_ObjectStateAtomicGetObjectState(ObjectState*);
extern "C" uint8_t CJRT_ObjectStateGetStateCode(ObjectState*);
extern "C" void CJRT_ObjectStateSetStateCode(ObjectState*, uint8_t);
extern "C" uint8_t CJRT_ObjectStatePredicates(ObjectState*);
extern "C" uint16_t CJRT_ObjectStateGetStateBits(ObjectState*);
extern "C" uint16_t CJRT_ObjectStateAtomicGetStateBits(ObjectState*);
extern "C" void CJRT_ObjectStateSetStateBits(ObjectState*, uint16_t);
extern "C" void CJRT_ObjectStateAtomicSetStateBits(ObjectState*, uint16_t);
extern "C" int32_t CJRT_ObjectStateCompareExchangeStateBits(ObjectState*, uint16_t, uint16_t);
extern "C" void CJRT_StateWordSetRawState(StateWord*, uint16_t);
extern "C" uint16_t CJRT_StateWordGetRawState(StateWord*);
extern "C" uintptr_t CJRT_StateWordGetTypeInfo(StateWord*);
extern "C" void CJRT_StateWordSetTypeInfo(StateWord*, uintptr_t);
extern "C" int32_t CJRT_StateWordIsValidStateWord(StateWord*);
extern "C" void CJRT_StateWordGetStateWord(StateWord*, StateWord*);
extern "C" uint16_t CJRT_StateWordGetObjectState(StateWord*);
extern "C" uint8_t CJRT_StateWordGetStateCode(StateWord*);
extern "C" uint8_t CJRT_StateWordPredicates(StateWord*);
extern "C" void CJRT_StateWordSetStateCode(StateWord*, uint8_t);
extern "C" int32_t CJRT_StateWordTryLockStateWord(StateWord*, uint16_t);
extern "C" void CJRT_StateWordUnlockStateWord(StateWord*, uint16_t);
#endif

namespace {
constexpr size_t TRACE_OPERATIONS = 100000;
constexpr size_t THREAD_COUNT = 4;
constexpr size_t LOCKS_PER_THREAD = 5000;

struct alignas(4) StateWordStorage {
    uint8_t bytes[8];
};

struct alignas(2) ObjectStateStorage {
    uint8_t bytes[2];
};

ObjectState* AsObjectState(ObjectStateStorage& storage)
{
    return reinterpret_cast<ObjectState*>(storage.bytes);
}

StateWord* AsStateWord(StateWordStorage& storage)
{
    return reinterpret_cast<StateWord*>(storage.bytes);
}

#ifdef STATEWORD_ORACLE
void ObjectStateConstructZero(ObjectState* destination) { new (destination) ObjectState(); }
void ObjectStateConstructRaw(ObjectState* destination, uint16_t raw) { new (destination) ObjectState(raw); }
void ObjectStateConstructCode(ObjectState* destination, uint8_t code)
{
    new (destination) ObjectState(static_cast<ObjectState::ObjectStateCode>(code));
}
void ObjectStateConstructCopy(ObjectState* destination, ObjectState* source) { new (destination) ObjectState(*source); }
uint16_t ObjectStateAtomicGetObjectState(ObjectState* state) { return state->AtomicGetObjectState().GetStateBits(); }
uint8_t ObjectStateGetStateCode(ObjectState* state) { return static_cast<uint8_t>(state->GetStateCode()); }
void ObjectStateSetStateCode(ObjectState* state, uint8_t code)
{
    state->SetStateCode(static_cast<ObjectState::ObjectStateCode>(code));
}
uint8_t ObjectStatePredicates(ObjectState* state)
{
    return (state->IsForwardableState() ? 1 : 0) | (state->IsLockedState() ? 2 : 0) |
        (state->IsForwardedState() ? 4 : 0);
}
uint16_t ObjectStateGetStateBits(ObjectState* state) { return state->GetStateBits(); }
uint16_t ObjectStateAtomicGetStateBits(ObjectState* state) { return state->AtomicGetStateBits(); }
void ObjectStateSetStateBits(ObjectState* state, uint16_t raw) { state->SetStateBits(raw); }
void ObjectStateAtomicSetStateBits(ObjectState* state, uint16_t raw) { state->AtomicSetStateBits(raw); }
int32_t ObjectStateCompareExchangeStateBits(ObjectState* state, uint16_t expected, uint16_t desired)
{
    return state->CompareExchangeStateBits(expected, desired) ? 1 : 0;
}
void StateWordSetRawState(StateWord* stateWord, uint16_t raw) { stateWord->objectState.SetStateBits(raw); }
uint16_t StateWordGetRawState(StateWord* stateWord) { return stateWord->objectState.GetStateBits(); }
uintptr_t StateWordGetTypeInfo(StateWord* stateWord) { return reinterpret_cast<uintptr_t>(stateWord->GetTypeInfo()); }
void StateWordSetTypeInfo(StateWord* stateWord, uintptr_t address)
{
    stateWord->SetTypeInfo(reinterpret_cast<MapleRuntime::TypeInfo*>(address));
}
int32_t StateWordIsValidStateWord(StateWord* stateWord) { return stateWord->IsValidStateWord() ? 1 : 0; }
void StateWordGetStateWord(StateWord* stateWord, StateWord* copy) { new (copy) StateWord(stateWord->GetStateWord()); }
uint16_t StateWordGetObjectState(StateWord* stateWord) { return stateWord->GetObjectState().GetStateBits(); }
uint8_t StateWordGetStateCode(StateWord* stateWord) { return static_cast<uint8_t>(stateWord->GetStateCode()); }
uint8_t StateWordPredicates(StateWord* stateWord)
{
    return (stateWord->IsForwardableState() ? 1 : 0) | (stateWord->IsForwardedState() ? 2 : 0) |
        (stateWord->IsLockedWord() ? 4 : 0);
}
void StateWordSetStateCode(StateWord* stateWord, uint8_t code)
{
    stateWord->SetStateCode(static_cast<ObjectState::ObjectStateCode>(code));
}
int32_t StateWordTryLockStateWord(StateWord* stateWord, uint16_t currentRaw)
{
    return stateWord->TryLockStateWord(ObjectState(currentRaw)) ? 1 : 0;
}
void StateWordUnlockStateWord(StateWord* stateWord, uint16_t newRaw) { stateWord->UnlockStateWord(ObjectState(newRaw)); }
#else
void ObjectStateConstructZero(ObjectState* destination) { CJRT_ObjectStateConstructZero(destination); }
void ObjectStateConstructRaw(ObjectState* destination, uint16_t raw) { CJRT_ObjectStateConstructRaw(destination, raw); }
void ObjectStateConstructCode(ObjectState* destination, uint8_t code) { CJRT_ObjectStateConstructCode(destination, code); }
void ObjectStateConstructCopy(ObjectState* destination, ObjectState* source) { CJRT_ObjectStateConstructCopy(destination, source); }
uint16_t ObjectStateAtomicGetObjectState(ObjectState* state) { return CJRT_ObjectStateAtomicGetObjectState(state); }
uint8_t ObjectStateGetStateCode(ObjectState* state) { return CJRT_ObjectStateGetStateCode(state); }
void ObjectStateSetStateCode(ObjectState* state, uint8_t code) { CJRT_ObjectStateSetStateCode(state, code); }
uint8_t ObjectStatePredicates(ObjectState* state) { return CJRT_ObjectStatePredicates(state); }
uint16_t ObjectStateGetStateBits(ObjectState* state) { return CJRT_ObjectStateGetStateBits(state); }
uint16_t ObjectStateAtomicGetStateBits(ObjectState* state) { return CJRT_ObjectStateAtomicGetStateBits(state); }
void ObjectStateSetStateBits(ObjectState* state, uint16_t raw) { CJRT_ObjectStateSetStateBits(state, raw); }
void ObjectStateAtomicSetStateBits(ObjectState* state, uint16_t raw) { CJRT_ObjectStateAtomicSetStateBits(state, raw); }
int32_t ObjectStateCompareExchangeStateBits(ObjectState* state, uint16_t expected, uint16_t desired)
{
    return CJRT_ObjectStateCompareExchangeStateBits(state, expected, desired);
}
void StateWordSetRawState(StateWord* stateWord, uint16_t raw) { CJRT_StateWordSetRawState(stateWord, raw); }
uint16_t StateWordGetRawState(StateWord* stateWord) { return CJRT_StateWordGetRawState(stateWord); }
uintptr_t StateWordGetTypeInfo(StateWord* stateWord) { return CJRT_StateWordGetTypeInfo(stateWord); }
void StateWordSetTypeInfo(StateWord* stateWord, uintptr_t address) { CJRT_StateWordSetTypeInfo(stateWord, address); }
int32_t StateWordIsValidStateWord(StateWord* stateWord) { return CJRT_StateWordIsValidStateWord(stateWord); }
void StateWordGetStateWord(StateWord* stateWord, StateWord* copy) { CJRT_StateWordGetStateWord(stateWord, copy); }
uint16_t StateWordGetObjectState(StateWord* stateWord) { return CJRT_StateWordGetObjectState(stateWord); }
uint8_t StateWordGetStateCode(StateWord* stateWord) { return CJRT_StateWordGetStateCode(stateWord); }
uint8_t StateWordPredicates(StateWord* stateWord) { return CJRT_StateWordPredicates(stateWord); }
void StateWordSetStateCode(StateWord* stateWord, uint8_t code) { CJRT_StateWordSetStateCode(stateWord, code); }
int32_t StateWordTryLockStateWord(StateWord* stateWord, uint16_t currentRaw)
{
    return CJRT_StateWordTryLockStateWord(stateWord, currentRaw);
}
void StateWordUnlockStateWord(StateWord* stateWord, uint16_t newRaw) { CJRT_StateWordUnlockStateWord(stateWord, newRaw); }
#endif

void PrintBytes(const uint8_t* bytes)
{
    for (size_t index = 0; index < 8; ++index) {
        std::printf("%02x", bytes[index]);
    }
}

void PrintWordRecord(const char* prefix, StateWordStorage& word)
{
    std::printf("%s bytes=", prefix);
    PrintBytes(word.bytes);
    std::printf(" type=%012" PRIxPTR " raw=%04x code=%u pred=%u valid=%d\n",
        StateWordGetTypeInfo(AsStateWord(word)), StateWordGetRawState(AsStateWord(word)),
        static_cast<unsigned>(StateWordGetStateCode(AsStateWord(word))),
        static_cast<unsigned>(StateWordPredicates(AsStateWord(word))),
        StateWordIsValidStateWord(AsStateWord(word)));
}

uint64_t NextRandom(uint64_t& state)
{
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return state;
}

StateWordStorage contentionWord{};
uint64_t contentionCounter = 0;
std::atomic<int32_t> contentionFailure{0};

void* ContentionThread(void*)
{
    StateWord* word = AsStateWord(contentionWord);
    for (size_t iteration = 0; iteration < LOCKS_PER_THREAD; ++iteration) {
        bool acquired = false;
        while (!acquired) {
            uint16_t current = StateWordGetObjectState(word);
            acquired = StateWordTryLockStateWord(word, current) != 0;
        }
        uint64_t value = contentionCounter;
        contentionCounter = value + 1;
        if (StateWordGetRawState(word) != 1) {
            contentionFailure.store(1, std::memory_order_relaxed);
        }
        StateWordUnlockStateWord(word, 0);
    }
    return nullptr;
}

int RunProbe()
{
#ifdef STATEWORD_ORACLE
    constexpr size_t objectStateSize = sizeof(ObjectState);
    constexpr size_t objectStateAlign = alignof(ObjectState);
    constexpr size_t objectStateBits = offsetof(ObjectState, stateBits);
    constexpr size_t stateWordSize = sizeof(StateWord);
    constexpr size_t stateWordAlign = alignof(StateWord);
#ifdef __arm__
    constexpr size_t stateWordLow = offsetof(StateWord, typeInfo);
    constexpr size_t stateWordHigh = offsetof(StateWord, padding);
#else
    constexpr size_t stateWordLow = offsetof(StateWord, typeInfoLow32);
    constexpr size_t stateWordHigh = offsetof(StateWord, typeInfoHigh16);
#endif
    constexpr size_t stateWordState = offsetof(StateWord, objectState);
#else
    constexpr size_t objectStateSize = CJ_OBJECTSTATE_SIZE;
    constexpr size_t objectStateAlign = CJ_OBJECTSTATE_ALIGN;
    constexpr size_t objectStateBits = CJ_OBJECTSTATE_BITS;
    constexpr size_t stateWordSize = CJ_STATEWORD_SIZE;
    constexpr size_t stateWordAlign = CJ_STATEWORD_ALIGN;
    constexpr size_t stateWordLow = CJ_STATEWORD_LOW;
    constexpr size_t stateWordHigh = CJ_STATEWORD_HIGH;
    constexpr size_t stateWordState = CJ_STATEWORD_STATE;
#endif
    std::printf("OBJECTSTATE_LAYOUT sizeof=%zu align=%zu stateBits=%zu\n",
        objectStateSize, objectStateAlign, objectStateBits);
    std::printf("STATEWORD_LAYOUT sizeof=%zu align=%zu typeInfoLow32=%zu typeInfoHigh16=%zu objectState=%zu\n",
        stateWordSize, stateWordAlign, stateWordLow, stateWordHigh, stateWordState);

    ObjectStateStorage first{};
    ObjectStateStorage second{};
    ObjectState* firstState = AsObjectState(first);
    ObjectState* secondState = AsObjectState(second);
    ObjectStateConstructZero(firstState);
    std::printf("OBJECTSTATE_CTOR kind=zero raw=%04x\n", ObjectStateGetStateBits(firstState));
    ObjectStateConstructRaw(firstState, 0xa5a3);
    std::printf("OBJECTSTATE_CTOR kind=raw raw=%04x\n", ObjectStateGetStateBits(firstState));
    ObjectStateConstructCode(firstState, 2);
    std::printf("OBJECTSTATE_CTOR kind=code raw=%04x\n", ObjectStateGetStateBits(firstState));
    ObjectStateConstructRaw(firstState, 0xa5a3);
    ObjectStateConstructCopy(secondState, firstState);
    std::printf("OBJECTSTATE_CTOR kind=copy raw=%04x\n", ObjectStateGetStateBits(secondState));

    for (uint8_t code = 0; code < 4; ++code) {
        ObjectStateConstructCode(firstState, code);
        std::printf("OBJECTSTATE_CODE code=%u get=%u pred=%u\n", static_cast<unsigned>(code),
            static_cast<unsigned>(ObjectStateGetStateCode(firstState)),
            static_cast<unsigned>(ObjectStatePredicates(firstState)));
    }
    for (uint8_t code = 0; code < 4; ++code) {
        ObjectStateConstructRaw(firstState, 0xa5a0);
        ObjectStateSetStateCode(firstState, code);
        std::printf("OBJECTSTATE_LOWBIT code=%u raw=%04x\n", static_cast<unsigned>(code),
            ObjectStateGetStateBits(firstState));
    }

    const uint16_t atomicValues[] = {0, 1, 2, 3, 0xffff};
    for (uint16_t value : atomicValues) {
        ObjectStateSetStateBits(firstState, value);
        uint16_t ordinary = ObjectStateGetStateBits(firstState);
        ObjectStateAtomicSetStateBits(firstState, value);
        uint16_t atomic = ObjectStateAtomicGetStateBits(firstState);
        uint16_t copied = ObjectStateAtomicGetObjectState(firstState);
        std::printf("OBJECTSTATE_VALUE input=%04x ordinary=%04x atomic=%04x copy=%04x\n",
            value, ordinary, atomic, copied);
    }
    ObjectStateSetStateBits(firstState, 0x1234);
    int32_t casSuccess = ObjectStateCompareExchangeStateBits(firstState, 0x1234, 0xabcd);
    int32_t casStale = ObjectStateCompareExchangeStateBits(firstState, 0x1234, 0xeeee);
    std::printf("OBJECTSTATE_CAS success=%d stale=%d raw=%04x\n", casSuccess, casStale,
        ObjectStateGetStateBits(firstState));

    StateWordStorage word{};
    StateWordStorage copy{};
    StateWord* stateWord = AsStateWord(word);
    StateWord* stateCopy = AsStateWord(copy);
    const uintptr_t typeValues[] = {
        0, 1, UINT64_C(0xffffffff), UINT64_C(0x100000000),
        UINT64_C(0xffff00000000), UINT64_C(0xffffffffffff)
    };
    for (uintptr_t address : typeValues) {
        std::memset(word.bytes, 0, sizeof(word.bytes));
        StateWordSetTypeInfo(stateWord, address);
        StateWordSetRawState(stateWord, 0xa5a3);
        std::memset(copy.bytes, 0, sizeof(copy.bytes));
        StateWordGetStateWord(stateWord, stateCopy);
        std::printf("STATEWORD_TYPE input=%012" PRIxPTR " output=%012" PRIxPTR " valid=%d bytes=",
            address, StateWordGetTypeInfo(stateWord), StateWordIsValidStateWord(stateWord));
        PrintBytes(word.bytes);
        std::printf(" copy=");
        PrintBytes(copy.bytes);
        std::printf(" object=%04x\n", StateWordGetObjectState(stateWord));
    }

    const uint16_t lockStarts[] = {0xa5a0, 0xa5a2, 0xa5a3};
    for (uint16_t start : lockStarts) {
        StateWordSetRawState(stateWord, start);
        int32_t result = StateWordTryLockStateWord(stateWord, start);
        std::printf("STATEWORD_LOCK start=%04x result=%d raw=%04x\n", start, result,
            StateWordGetRawState(stateWord));
    }
    StateWordSetRawState(stateWord, 0xa5a1);
    std::printf("STATEWORD_LOCK start=a5a1 result=%d raw=%04x\n",
        StateWordTryLockStateWord(stateWord, 0xa5a1), StateWordGetRawState(stateWord));
    StateWordSetRawState(stateWord, 0xa5a0);
    std::printf("STATEWORD_LOCK start=a5a0 stale_result=%d raw=%04x\n",
        StateWordTryLockStateWord(stateWord, 0xa5a2), StateWordGetRawState(stateWord));

    for (uint16_t value : atomicValues) {
        StateWordSetRawState(stateWord, 1);
        StateWordUnlockStateWord(stateWord, value);
        std::printf("STATEWORD_UNLOCK target=%04x raw=%04x\n", value,
            StateWordGetRawState(stateWord));
    }

    uint64_t random = UINT64_C(0x6a09e667f3bcc909);
    StateWordSetTypeInfo(stateWord, UINT64_C(0x123456789ab0));
    StateWordSetRawState(stateWord, 0);
    for (size_t index = 0; index < TRACE_OPERATIONS; ++index) {
        uint64_t value = NextRandom(random);
        uint8_t operation = static_cast<uint8_t>(value & 7);
        uint16_t argument = static_cast<uint16_t>(value >> 16);
        uintptr_t address = static_cast<uintptr_t>((value >> 8) & UINT64_C(0xffffffffffff));
        int32_t result = 0;
        std::memset(copy.bytes, 0, sizeof(copy.bytes));
        switch (operation) {
            case 0:
                StateWordSetTypeInfo(stateWord, address);
                result = StateWordIsValidStateWord(stateWord);
                break;
            case 1:
                StateWordSetStateCode(stateWord, static_cast<uint8_t>(argument & 3));
                result = StateWordGetStateCode(stateWord);
                break;
            case 2:
                StateWordSetRawState(stateWord, argument);
                result = StateWordGetRawState(stateWord);
                break;
            case 3: {
                ObjectState* objectState = reinterpret_cast<ObjectState*>(word.bytes + 6);
                ObjectStateAtomicSetStateBits(objectState, argument);
                result = ObjectStateAtomicGetStateBits(objectState);
                break;
            }
            case 4: {
                ObjectState* objectState = reinterpret_cast<ObjectState*>(word.bytes + 6);
                uint16_t expected = (value & 0x100) ? ObjectStateGetStateBits(objectState) :
                    static_cast<uint16_t>(ObjectStateGetStateBits(objectState) ^ 4);
                result = ObjectStateCompareExchangeStateBits(objectState, expected, argument);
                break;
            }
            case 5: {
                uint16_t current = StateWordGetObjectState(stateWord);
                result = StateWordTryLockStateWord(stateWord, current);
                break;
            }
            case 6:
                if ((StateWordGetRawState(stateWord) & 3) != 1) {
                    StateWordSetRawState(stateWord, 1);
                }
                StateWordUnlockStateWord(stateWord, argument);
                result = StateWordGetStateCode(stateWord);
                break;
            case 7:
                StateWordGetStateWord(stateWord, stateCopy);
                result = static_cast<int32_t>(StateWordGetObjectState(stateCopy));
                break;
        }
        std::printf("TRACE i=%zu op=%u arg=%04x address=%012" PRIxPTR " result=%d bytes=",
            index, static_cast<unsigned>(operation), argument, address, result);
        PrintBytes(word.bytes);
        std::printf(" copy=");
        PrintBytes(copy.bytes);
        std::printf("\n");
    }
    std::printf("STATEWORD_TRACE operations=%zu seed=6a09e667f3bcc909 status=PASS\n",
        TRACE_OPERATIONS);

    std::memset(contentionWord.bytes, 0, sizeof(contentionWord.bytes));
    StateWordSetTypeInfo(AsStateWord(contentionWord), UINT64_C(0x123456789ab0));
    StateWordSetRawState(AsStateWord(contentionWord), 0);
    std::array<pthread_t, THREAD_COUNT> threads{};
    for (size_t index = 0; index < THREAD_COUNT; ++index) {
        if (pthread_create(&threads[index], nullptr, ContentionThread, nullptr) != 0) {
            return 2;
        }
    }
    for (pthread_t thread : threads) {
        if (pthread_join(thread, nullptr) != 0) {
            return 3;
        }
    }
    bool contentionPass = contentionCounter == THREAD_COUNT * LOCKS_PER_THREAD &&
        contentionFailure.load(std::memory_order_relaxed) == 0 &&
        StateWordGetRawState(AsStateWord(contentionWord)) == 0;
    std::printf("STATEWORD_CONTENTION threads=%zu locks_per_thread=%zu counter=%" PRIu64
        " raw=%04x status=%s\n", THREAD_COUNT, LOCKS_PER_THREAD, contentionCounter,
        StateWordGetRawState(AsStateWord(contentionWord)), contentionPass ? "PASS" : "FAIL");
    return contentionPass ? 0 : 4;
}
} // namespace

#ifdef STATEWORD_ORACLE
int main()
{
    return RunProbe();
}
#else
extern "C" int StateWordProbeMain()
{
    return RunProbe();
}
#endif
