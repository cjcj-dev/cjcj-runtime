package schedlowdeps.noheap

import rt.sched.*

foreign {
    func SchedLowdepsObserveList(stage: Int32, head: CPointer<Dulink>, a: CPointer<Dulink>,
        b: CPointer<Dulink>, c: CPointer<Dulink>, other: CPointer<Dulink>): Int32
    func SchedLowdepsObserveLink(stage: Int32, head: CPointer<Link>, a: CPointer<Link>,
        b: CPointer<Link>, c: CPointer<Link>): Int32
    func SchedLowdepsObserveStack(stackSize: UIntNative, stackAlign: UIntNative,
        totalOffset: UIntNative, topOffset: UIntNative, guardOffset: UIntNative,
        baseOffset: UIntNative, sizeOffset: UIntNative, actualBaseOffset: UIntNative,
        growOffset: UIntNative, infoSize: UIntNative, argSize: UIntNative,
        stackAttrSize: UIntNative, stackAttrGrowOffset: UIntNative,
        enumSize: UIntNative, localBuf: UInt32, globalBuf: UInt32, noBuf: UInt32,
        alignUp: UIntNative, alignDown: UIntNative): Int32
    func SchedLowdepsObserveTimer(mid: Int32, firstError: Int32, lastError: Int32,
        forks: UInt32, statusSize: UIntNative, moving: UInt32,
        nodeSize: UIntNative, nodeAlign: UIntNative, deadlineOffset: UIntNative,
        statusOffset: UIntNative, autoOffset: UIntNative, moveSize: UIntNative,
        resetSize: UIntNative, stoppedSize: UIntNative): Int32
}

@NoHeapAlloc
func ListRun(): Int32 {
    var head = Dulink()
    var a = Dulink()
    var b = Dulink()
    var c = Dulink()
    var other = Dulink()
    let hp = unsafe { CPointer<Dulink>(inout head) }
    let ap = unsafe { CPointer<Dulink>(inout a) }
    let bp = unsafe { CPointer<Dulink>(inout b) }
    let cp = unsafe { CPointer<Dulink>(inout c) }
    let op = unsafe { CPointer<Dulink>(inout other) }
    DulinkInit(hp)
    DulinkInit(ap)
    DulinkInit(bp)
    DulinkInit(cp)
    DulinkInit(op)
    var result: Int32 = if (DulinkIsEmpty(hp)) { 0 } else { 1 }
    DulinkPushtail(hp, CPointer<Unit>(ap))
    DulinkPushHead(hp, CPointer<Unit>(bp))
    DulinkAdd(cp, ap)
    result |= unsafe { SchedLowdepsObserveList(1, hp, ap, bp, cp, op) }
    result |= if (DulinkGetIndexByNext(hp, 2).toUIntNative() == ap.toUIntNative() &&
        DulinkGetIndexByPrev(hp, 1).toUIntNative() == cp.toUIntNative()) { 0 } else { 2 }
    DulinkRemove(ap)
    result |= unsafe { SchedLowdepsObserveList(2, hp, ap, bp, cp, op) }
    DulinkPopHead(hp)
    result |= unsafe { SchedLowdepsObserveList(3, hp, ap, bp, cp, op) }
    DulinkPushHead(hp, CPointer<Unit>(bp))
    DulinkPopTail(hp)
    result |= unsafe { SchedLowdepsObserveList(4, hp, ap, bp, cp, op) }

    DulinkInit(hp)
    DulinkInit(op)
    DulinkPushtail(hp, CPointer<Unit>(ap))
    DulinkPushtail(hp, CPointer<Unit>(bp))
    DulinkPushtail(hp, CPointer<Unit>(cp))
    DulinkMove(op, hp, 2)
    result |= unsafe { SchedLowdepsObserveList(5, hp, ap, bp, cp, op) }
    DulinkMove(hp, op, -1)
    result |= unsafe { SchedLowdepsObserveList(6, hp, ap, bp, cp, op) }
    return result
}

@NoHeapAlloc
func LinkRun(): Int32 {
    var head = Link()
    var a = Link()
    var b = Link()
    var c = Link()
    let hp = unsafe { CPointer<Link>(inout head) }
    let ap = unsafe { CPointer<Link>(inout a) }
    let bp = unsafe { CPointer<Link>(inout b) }
    let cp = unsafe { CPointer<Link>(inout c) }
    LinkInit(hp)
    LinkInit(ap)
    LinkInit(bp)
    LinkInit(cp)
    var result: Int32 = if (LinkIsEmpty(hp)) { 0 } else { 4 }
    LinkPushHead(hp, CPointer<Unit>(ap))
    LinkPushHead(hp, CPointer<Unit>(bp))
    LinkPushTail(ap, CPointer<Unit>(cp))
    result |= unsafe { SchedLowdepsObserveLink(1, hp, ap, bp, cp) }
    LinkRemove(ap)
    result |= unsafe { SchedLowdepsObserveLink(2, hp, ap, bp, cp) }
    return result
}

@NoHeapAlloc
func StackRun(): Int32 {
    var stack = CJThreadStack()
    let base = unsafe { CPointer<UInt8>(inout stack).toUIntNative() }
    var attr = StackAttr()
    let attrBase = unsafe { CPointer<UInt8>(inout attr).toUIntNative() }
    return unsafe {
        SchedLowdepsObserveStack(sizeOf<CJThreadStack>(), alignOf<CJThreadStack>(),
            CPointer<UInt8>(inout stack.totalSize).toUIntNative() - base,
            CPointer<UInt8>(inout stack.stackTopAddr).toUIntNative() - base,
            CPointer<UInt8>(inout stack.stackGuard).toUIntNative() - base,
            CPointer<UInt8>(inout stack.stackBaseAddr).toUIntNative() - base,
            CPointer<UInt8>(inout stack.stackSize).toUIntNative() - base,
            CPointer<UInt8>(inout stack.cjthreadStackBaseAddr).toUIntNative() - base,
            CPointer<UInt8>(inout stack.stackGrowCnt).toUIntNative() - base,
            sizeOf<StackInfo>(), sizeOf<ArgAttr>(), sizeOf<StackAttr>(),
            CPointer<UInt8>(inout attr.stackGrow).toUIntNative() - attrBase,
            sizeOf<CJThreadBuf>(), LOCAL_BUF, GLOBAL_BUF, NO_BUF,
            StackAddrAlignUp(0x1003, CJTHREAD_ARG_ALIGN),
            StackAddrAlignDown(0x100f, CJTHREAD_ARG_ALIGN))
    }
}

@NoHeapAlloc
func TimerRun(): Int32 {
    var node = TimerNode()
    let base = unsafe { CPointer<UInt8>(inout node).toUIntNative() }
    return unsafe {
        SchedLowdepsObserveTimer(MID_TIMER, ERROR_TIMER_ALLOC, ERROR_TIMER_FREE,
            FORKS_NUM, sizeOf<TimerStatus>(), TIMER_MOVING, sizeOf<TimerNode>(),
            alignOf<TimerNode>(), CPointer<UInt8>(inout node.deadline).toUIntNative() - base,
            CPointer<UInt8>(inout node.status).toUIntNative() - base,
            CPointer<UInt8>(inout node.autoReleasing).toUIntNative() - base,
            sizeOf<MoveItem>(), sizeOf<TimerResetPara>(), sizeOf<TimerStoppedPara>())
    }
}

@C
public func CJRT_SchedLowdepsRun(): Int32 {
    return ListRun() | LinkRun() | StackRun() | TimerRun()
}
