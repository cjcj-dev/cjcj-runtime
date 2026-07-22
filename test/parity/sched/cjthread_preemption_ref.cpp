#include <cstdint>
#include <cstdio>

extern "C" int CJ_CJThreadPreemptOffCntAdd(void);
extern "C" int CJ_CJThreadPreemptOffCntSub(void);
extern "C" int CJ_CJThreadResched(void);

extern "C" int CJThreadPreemptionObserve(int32_t addResult, int32_t subResult,
                                         void* reschedEntry)
{
    const bool addSymbol = reinterpret_cast<void*>(&CJ_CJThreadPreemptOffCntAdd) != nullptr;
    const bool subSymbol = reinterpret_cast<void*>(&CJ_CJThreadPreemptOffCntSub) != nullptr;
    const bool reschedSymbol = reschedEntry == reinterpret_cast<void*>(&CJ_CJThreadResched);
    const bool result = addResult == 0 && subResult == 0 && addSymbol && subSymbol && reschedSymbol;
    std::printf("CJTHREAD_PREEMPTION add=%d sub=%d add_symbol=%d sub_symbol=%d resched_symbol=%d status=%s\n",
                addResult, subResult, addSymbol ? 1 : 0, subSymbol ? 1 : 0,
                reschedSymbol ? 1 : 0, result ? "PASS" : "FAIL");
    return result ? 0 : 1;
}
