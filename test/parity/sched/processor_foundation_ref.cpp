// CJThread schedule/include/inner/processor.h:24-108 and schmon.h:20-28.
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <type_traits>

#include "processor.h"
#include "schmon.h"

size_t g_pageSize = 0;
void LogWrite(ThreadLogLevel, unsigned int, const char*, unsigned short, const char*, ...) {}

extern "C" int32_t ProcessorFoundationObserve(
    int32_t globalSchNum, int32_t queueCapacity, int32_t stealRatio,
    int32_t globalAddRatio, int32_t parrayNum, int32_t stealRounds,
    int32_t runningSearchingMultiple, int32_t keyTimer, int32_t stealSleep,
    int32_t schedCount, uint32_t idle, uint32_t running, uint32_t exiting,
    uint32_t syscallState, size_t stateSize, size_t stateAlign,
    size_t freelistSize, size_t freelistAlign, size_t freelistCountOffset,
    size_t observedSize, size_t observedAlign, size_t observedTimeOffset,
    size_t infoSize, size_t infoAlign, size_t infoStateOffset,
    size_t infoRunqOffset, size_t infoSchedOffset, size_t infoThreadOffset,
    int32_t midSchmon, int32_t argInvalid, int32_t initFailed)
{
    using StateUnderlying = std::underlying_type<ProcessorState>::type;
    const int32_t policy[] = {GLOBAL_SCH_NUM, PROCESSOR_QUEUE_CAPACITY,
        PROCESSOR_STEAL_RATIO, GLOBAL_ADD_RATIO, PROCESSOR_PARRAY_NUM,
        PROCESSOR_STEAL_ROUNDS, RUNNING_PROCESSOR_SEARCHING_NUM_MULTIPLE,
        KEY_TIMER, PROCESSOR_STEAL_SLEEP_THRESHOLD,
        PROCESSOR_SCHED_COUNT_THRESHOLD};
    const int32_t receivedPolicy[] = {globalSchNum, queueCapacity, stealRatio,
        globalAddRatio, parrayNum, stealRounds, runningSearchingMultiple,
        keyTimer, stealSleep, schedCount};
    for (size_t index = 0; index < 10; ++index) {
        if (policy[index] != receivedPolicy[index]) return 1;
    }
    if (idle != PROCESSOR_IDLE || running != PROCESSOR_RUNNING ||
        exiting != PROCESSOR_EXITING || syscallState != PROCESSOR_SYSCALL ||
        stateSize != sizeof(ProcessorState) || stateAlign != alignof(ProcessorState) ||
        std::is_unsigned<StateUnderlying>::value == 0) return 2;
    if (freelistSize != sizeof(ProcessorFreelist) ||
        freelistAlign != alignof(ProcessorFreelist) ||
        freelistCountOffset != offsetof(ProcessorFreelist, cjthreadNum)) return 3;
    if (observedSize != sizeof(ProcessorObservedRecord) ||
        observedAlign != alignof(ProcessorObservedRecord) ||
        observedTimeOffset != offsetof(ProcessorObservedRecord, lastTime)) return 4;
    if (infoSize != sizeof(ProcessorInfo) || infoAlign != alignof(ProcessorInfo) ||
        infoStateOffset != offsetof(ProcessorInfo, state) ||
        infoRunqOffset != offsetof(ProcessorInfo, runqCnt) ||
        infoSchedOffset != offsetof(ProcessorInfo, schedCnt) ||
        infoThreadOffset != offsetof(ProcessorInfo, threadId)) return 5;
    if (midSchmon != MID_SCHMON || argInvalid != ERRNO_SCHMON_ARG_INVALID ||
        initFailed != ERRNO_SCHMON_INIT_FAILED) return 6;

    std::printf("PROCESSOR_POLICY values=%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
        globalSchNum, queueCapacity, stealRatio, globalAddRatio, parrayNum,
        stealRounds, runningSearchingMultiple, keyTimer, stealSleep, schedCount);
    std::printf("PROCESSOR_STATE size=%zu align=%zu signed=0 values=%u,%u,%u,%u\n",
        stateSize, stateAlign, idle, running, exiting, syscallState);
    std::printf("PROCESSOR_FREELIST size=%zu align=%zu freeList=0 cjthreadNum=%zu\n",
        freelistSize, freelistAlign, freelistCountOffset);
    std::printf("PROCESSOR_OBSERVED size=%zu align=%zu lastSchedCnt=0 lastTime=%zu\n",
        observedSize, observedAlign, observedTimeOffset);
    std::printf("PROCESSOR_INFO size=%zu align=%zu processorId=0 state=%zu runqCnt=%zu schedCnt=%zu threadId=%zu\n",
        infoSize, infoAlign, infoStateOffset, infoRunqOffset, infoSchedOffset,
        infoThreadOffset);
    std::printf("SCHMON_ERRORS mid=%d arg_invalid=%d init_failed=%d\n",
        midSchmon, argInvalid, initFailed);
    return 0;
}

#ifdef PROCESSOR_FOUNDATION_CPP_ORACLE
int main()
{
    return ProcessorFoundationObserve(GLOBAL_SCH_NUM, PROCESSOR_QUEUE_CAPACITY,
        PROCESSOR_STEAL_RATIO, GLOBAL_ADD_RATIO, PROCESSOR_PARRAY_NUM,
        PROCESSOR_STEAL_ROUNDS, RUNNING_PROCESSOR_SEARCHING_NUM_MULTIPLE,
        KEY_TIMER, PROCESSOR_STEAL_SLEEP_THRESHOLD,
        PROCESSOR_SCHED_COUNT_THRESHOLD, PROCESSOR_IDLE, PROCESSOR_RUNNING,
        PROCESSOR_EXITING, PROCESSOR_SYSCALL, sizeof(ProcessorState),
        alignof(ProcessorState), sizeof(ProcessorFreelist),
        alignof(ProcessorFreelist), offsetof(ProcessorFreelist, cjthreadNum),
        sizeof(ProcessorObservedRecord), alignof(ProcessorObservedRecord),
        offsetof(ProcessorObservedRecord, lastTime), sizeof(ProcessorInfo),
        alignof(ProcessorInfo), offsetof(ProcessorInfo, state),
        offsetof(ProcessorInfo, runqCnt), offsetof(ProcessorInfo, schedCnt),
        offsetof(ProcessorInfo, threadId), MID_SCHMON,
        ERRNO_SCHMON_ARG_INVALID, ERRNO_SCHMON_INIT_FAILED);
}
#endif
