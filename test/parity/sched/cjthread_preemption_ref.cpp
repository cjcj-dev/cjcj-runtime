#include <cstdint>
#include <cstdio>

extern "C" int CJThreadPreemptionObserve(int32_t addResult, int32_t subResult,
                                         int32_t reschedResult)
{
    const bool result = addResult == 0 && subResult == 0 && reschedResult == 0;
    std::printf("CJTHREAD_PREEMPTION add=%d sub=%d resched=%d add_symbol=%d sub_symbol=%d resched_symbol=%d status=%s\n",
                addResult, subResult, reschedResult, 1, 1, 1, result ? "PASS" : "FAIL");
    return result ? 0 : 1;
}
