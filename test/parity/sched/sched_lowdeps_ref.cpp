// CJThread list.h:25-302, cjthread.h:30-100,173-185 and timer_impl.h:21-94.
#include <cstddef>
#include <cstdint>
#include <cerrno>
#include <cstdio>
#include <type_traits>

#include "cjthread.h"
#include "timer_impl.h"

static int NodeId(const Dulink* value, const Dulink* head, const Dulink* a,
                  const Dulink* b, const Dulink* c, const Dulink* other)
{
    if (value == nullptr) return 0;
    if (value == head) return 1;
    if (value == a) return 2;
    if (value == b) return 3;
    if (value == c) return 4;
    if (value == other) return 5;
    return 15;
}

extern "C" int32_t SchedLowdepsObserveList(int32_t stage, Dulink* head, Dulink* a,
    Dulink* b, Dulink* c, Dulink* other)
{
    Dulink* nodes[] = {head, a, b, c, other};
    uint64_t signature = 0;
    for (size_t i = 0; i < 5; ++i) {
        signature |= static_cast<uint64_t>(NodeId(nodes[i]->prev, head, a, b, c, other)) << (i * 8);
        signature |= static_cast<uint64_t>(NodeId(nodes[i]->next, head, a, b, c, other)) << (i * 8 + 4);
    }
    std::printf("LIST_DULINK stage=%d signature=%010llx\n", stage,
        static_cast<unsigned long long>(signature));
    return signature == 0 || (signature & 0xf0f0f0f0f0ULL) == 0xf0f0f0f0f0ULL ? 1 : 0;
}

static int LinkId(const Link* value, const Link* head, const Link* a,
                  const Link* b, const Link* c)
{
    if (value == nullptr) return 0;
    if (value == head) return 1;
    if (value == a) return 2;
    if (value == b) return 3;
    if (value == c) return 4;
    return 15;
}

extern "C" int32_t SchedLowdepsObserveLink(int32_t stage, Link* head, Link* a,
    Link* b, Link* c)
{
    Link* nodes[] = {head, a, b, c};
    uint32_t signature = 0;
    for (size_t i = 0; i < 4; ++i) {
        signature |= static_cast<uint32_t>(LinkId(nodes[i]->prev, head, a, b, c)) << (i * 8);
        signature |= static_cast<uint32_t>(LinkId(nodes[i]->next, head, a, b, c)) << (i * 8 + 4);
    }
    std::printf("LIST_LINK stage=%d signature=%08x\n", stage, signature);
    return signature == 0 || (signature & 0xf0f0f0f0U) == 0xf0f0f0f0U ? 1 : 0;
}

extern "C" int32_t SchedLowdepsObserveStack(size_t stackSize, size_t stackAlign,
    size_t totalOffset, size_t topOffset, size_t guardOffset, size_t baseOffset,
    size_t sizeOffset, size_t actualBaseOffset, size_t growOffset, size_t infoSize,
    size_t argSize, size_t stackAttrSize, size_t stackAttrGrowOffset, size_t enumSize,
    uint32_t localBuf, uint32_t globalBuf, uint32_t noBuf, size_t alignUp, size_t alignDown)
{
    using BufUnderlying = std::underlying_type<CJThreadBuf>::type;
    bool ok = stackSize == sizeof(CJThreadStack) && stackAlign == alignof(CJThreadStack) &&
        totalOffset == offsetof(CJThreadStack, totalSize) && topOffset == offsetof(CJThreadStack, stackTopAddr) &&
        guardOffset == offsetof(CJThreadStack, stackGuard) && baseOffset == offsetof(CJThreadStack, stackBaseAddr) &&
        sizeOffset == offsetof(CJThreadStack, stackSize) &&
        actualBaseOffset == offsetof(CJThreadStack, cjthreadStackBaseAddr) &&
        growOffset == offsetof(CJThreadStack, stackGrowCnt) && infoSize == sizeof(StackInfo) &&
        argSize == sizeof(ArgAttr) && stackAttrSize == sizeof(StackAttr) &&
        stackAttrGrowOffset == offsetof(StackAttr, stackGrow) && enumSize == sizeof(CJThreadBuf) &&
        std::is_unsigned<BufUnderlying>::value && localBuf == LOCAL_BUF && globalBuf == GLOBAL_BUF &&
        noBuf == NO_BUF && alignUp == STACK_ADDR_ALIGN_UP(0x1003, CJTHREAD_ARG_ALIGN) &&
        alignDown == STACK_ADDR_ALIGN_DOWN(0x100f, CJTHREAD_ARG_ALIGN);
    std::printf("CJTHREAD_STACK size=%zu align=%zu offsets=%zu,%zu,%zu,%zu,%zu,%zu,%zu aux=%zu,%zu,%zu,%zu enum=%zu:%u,%u,%u alignfn=%zu,%zu\n",
        stackSize, stackAlign, totalOffset, topOffset, guardOffset, baseOffset, sizeOffset,
        actualBaseOffset, growOffset, infoSize, argSize, stackAttrSize, stackAttrGrowOffset,
        enumSize, localBuf, globalBuf, noBuf, alignUp, alignDown);
    return ok ? 0 : 8;
}

extern "C" int32_t SchedLowdepsObserveTimer(int32_t mid, int32_t firstError,
    int32_t lastError, uint32_t forks, size_t statusSize, uint32_t moving,
    size_t nodeSize, size_t nodeAlign, size_t deadlineOffset, size_t statusOffset,
    size_t autoOffset, size_t moveSize, size_t resetSize, size_t stoppedSize)
{
    using StatusUnderlying = std::underlying_type<TimerStatus>::type;
    bool ok = mid == MID_TIMER && firstError == ERROR_TIMER_ALLOC && lastError == ERROR_TIMER_FREE &&
        forks == FORKS_NUM && statusSize == sizeof(TimerStatus) &&
        std::is_unsigned<StatusUnderlying>::value && moving == TIMER_MOVING &&
        nodeSize == sizeof(TimerNode) && nodeAlign == alignof(TimerNode) &&
        deadlineOffset == offsetof(TimerNode, deadline) && statusOffset == offsetof(TimerNode, status) &&
        autoOffset == offsetof(TimerNode, autoReleasing) && moveSize == sizeof(MoveItem) &&
        resetSize == sizeof(TimerResetPara) && stoppedSize == sizeof(TimerStoppedPara);
    std::printf("TIMER_FOUNDATION errors=%x,%x,%x forks=%u status=%zu:%u node=%zu:%zu:%zu,%zu,%zu aux=%zu,%zu,%zu\n",
        static_cast<unsigned>(mid), static_cast<unsigned>(firstError), static_cast<unsigned>(lastError),
        forks, statusSize, moving, nodeSize, nodeAlign, deadlineOffset, statusOffset, autoOffset,
        moveSize, resetSize, stoppedSize);
    return ok ? 0 : 16;
}

#ifdef SCHED_LOWDEPS_CPP_ORACLE
int main()
{
    Dulink head, a, b, c, other;
    DulinkInit(&head); DulinkInit(&a); DulinkInit(&b); DulinkInit(&c); DulinkInit(&other);
    DulinkPushtail(&head, &a); DulinkPushHead(&head, &b); DulinkAdd(&c, &a);
    int result = SchedLowdepsObserveList(1, &head, &a, &b, &c, &other);
    result |= (DulinkGetIndexByNext(&head, 2) == &a && DulinkGetIndexByPrev(&head, 1) == &c) ? 0 : 2;
    DulinkRemove(&a); result |= SchedLowdepsObserveList(2, &head, &a, &b, &c, &other);
    DulinkPopHead(&head); result |= SchedLowdepsObserveList(3, &head, &a, &b, &c, &other);
    DulinkPushHead(&head, &b); DulinkPopTail(&head);
    result |= SchedLowdepsObserveList(4, &head, &a, &b, &c, &other);
    DulinkInit(&head); DulinkInit(&other); DulinkPushtail(&head, &a);
    DulinkPushtail(&head, &b); DulinkPushtail(&head, &c); DulinkMove(&other, &head, 2);
    result |= SchedLowdepsObserveList(5, &head, &a, &b, &c, &other);
    DulinkMove(&head, &other, -1);
    result |= SchedLowdepsObserveList(6, &head, &a, &b, &c, &other);

    Link linkHead, la, lb, lc;
    LinkInit(&linkHead); LinkInit(&la); LinkInit(&lb); LinkInit(&lc);
    LinkPushHead(&linkHead, &la); LinkPushHead(&linkHead, &lb); LinkPushTail(&la, &lc);
    result |= SchedLowdepsObserveLink(1, &linkHead, &la, &lb, &lc);
    LinkRemove(&la); result |= SchedLowdepsObserveLink(2, &linkHead, &la, &lb, &lc);
    result |= SchedLowdepsObserveStack(sizeof(CJThreadStack), alignof(CJThreadStack),
        offsetof(CJThreadStack, totalSize), offsetof(CJThreadStack, stackTopAddr),
        offsetof(CJThreadStack, stackGuard), offsetof(CJThreadStack, stackBaseAddr),
        offsetof(CJThreadStack, stackSize), offsetof(CJThreadStack, cjthreadStackBaseAddr),
        offsetof(CJThreadStack, stackGrowCnt), sizeof(StackInfo), sizeof(ArgAttr), sizeof(StackAttr),
        offsetof(StackAttr, stackGrow), sizeof(CJThreadBuf), LOCAL_BUF, GLOBAL_BUF, NO_BUF,
        STACK_ADDR_ALIGN_UP(0x1003, CJTHREAD_ARG_ALIGN), STACK_ADDR_ALIGN_DOWN(0x100f, CJTHREAD_ARG_ALIGN));
    result |= SchedLowdepsObserveTimer(MID_TIMER, ERROR_TIMER_ALLOC, ERROR_TIMER_FREE,
        FORKS_NUM, sizeof(TimerStatus), TIMER_MOVING, sizeof(TimerNode), alignof(TimerNode),
        offsetof(TimerNode, deadline), offsetof(TimerNode, status), offsetof(TimerNode, autoReleasing),
        sizeof(MoveItem), sizeof(TimerResetPara), sizeof(TimerStoppedPara));
    return result;
}
#endif
