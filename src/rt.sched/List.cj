// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

package rt.sched

// CJThread runtime/util/list/include/list.h:25-28,223-226. Both list node
// forms are two native pointers on every target; neither header branch nor
// operating-system-owned storage is present.
@C
public struct Link {
    public var prev: CPointer<Link>
    public var next: CPointer<Link>

    public init() {
        prev = CPointer<Link>()
        next = CPointer<Link>()
    }
}

@NoHeapAlloc
private func DulinkPrev(node: CPointer<Dulink>): CPointer<Dulink> {
    return unsafe { CPointer<CPointer<Dulink>>(node).read(0) }
}

@NoHeapAlloc
private func DulinkNext(node: CPointer<Dulink>): CPointer<Dulink> {
    return unsafe { CPointer<CPointer<Dulink>>(node).read(1) }
}

@NoHeapAlloc
private func DulinkSetPrev(node: CPointer<Dulink>, value: CPointer<Dulink>): Unit {
    unsafe { CPointer<CPointer<Dulink>>(node).write(0, value) }
}

@NoHeapAlloc
private func DulinkSetNext(node: CPointer<Dulink>, value: CPointer<Dulink>): Unit {
    unsafe { CPointer<CPointer<Dulink>>(node).write(1, value) }
}

// list.h:36-217. These functions retain the header's exact mutation order.
// As in C++, callers own all nodes and must satisfy each operation's stated
// non-empty/index precondition.
@NoHeapAlloc
public func DulinkInit(dulink: CPointer<Dulink>): Unit {
    DulinkSetNext(dulink, dulink)
    DulinkSetPrev(dulink, dulink)
}

@NoHeapAlloc
public func DulinkIsEmpty(dulink: CPointer<Dulink>): Bool {
    return DulinkNext(dulink).toUIntNative() == dulink.toUIntNative()
}

@NoHeapAlloc
public func DulinkRemove(item: CPointer<Dulink>): Unit {
    let prev = DulinkPrev(item)
    let next = DulinkNext(item)
    DulinkSetNext(prev, next)
    DulinkSetPrev(next, prev)
}

@NoHeapAlloc
public func DulinkAdd(item: CPointer<Dulink>, `where`: CPointer<Dulink>): Unit {
    DulinkSetNext(item, DulinkNext(`where`))
    DulinkSetPrev(item, `where`)
    DulinkSetNext(`where`, item)
    DulinkSetPrev(DulinkNext(item), item)
}

@NoHeapAlloc
public func DulinkPushtail(dulink: CPointer<Dulink>, object: CPointer<Unit>): Unit {
    let newNode = CPointer<Dulink>(object)
    let tail = DulinkPrev(dulink)
    DulinkSetNext(tail, newNode)
    DulinkSetPrev(newNode, tail)
    DulinkSetNext(newNode, dulink)
    DulinkSetPrev(dulink, newNode)
}

@NoHeapAlloc
public func DulinkPushHead(dulink: CPointer<Dulink>, object: CPointer<Unit>): Unit {
    let node = CPointer<Dulink>(object)
    DulinkSetNext(node, DulinkNext(dulink))
    DulinkSetPrev(node, dulink)
    DulinkSetNext(dulink, node)
    DulinkSetPrev(DulinkNext(node), node)
}

@NoHeapAlloc
public func DulinkPopTail(dulink: CPointer<Dulink>): Unit {
    let tail = DulinkPrev(dulink)
    let prev = DulinkPrev(tail)
    let next = DulinkNext(tail)
    DulinkSetNext(prev, next)
    DulinkSetPrev(next, prev)
}

@NoHeapAlloc
public func DulinkPopHead(dulink: CPointer<Dulink>): Unit {
    let head = DulinkNext(dulink)
    let prev = DulinkPrev(head)
    let next = DulinkNext(head)
    DulinkSetNext(prev, next)
    DulinkSetPrev(next, prev)
}

@NoHeapAlloc
public func DulinkGetIndexByNext(head: CPointer<Dulink>, index: Int32): CPointer<Dulink> {
    var link = head
    var i: Int32 = 0
    while (i < index) {
        link = DulinkNext(link)
        i++
    }
    return link
}

@NoHeapAlloc
public func DulinkGetIndexByPrev(head: CPointer<Dulink>, index: Int32): CPointer<Dulink> {
    var link = head
    var i: Int32 = 0
    while (i < index) {
        link = DulinkPrev(link)
        i++
    }
    return link
}

@NoHeapAlloc
public func DulinkInsertHead(head: CPointer<Dulink>, beg: CPointer<Dulink>, end: CPointer<Dulink>): Unit {
    let oldFirst = DulinkNext(head)
    DulinkSetPrev(oldFirst, end)
    DulinkSetNext(end, oldFirst)
    DulinkSetNext(head, beg)
    DulinkSetPrev(beg, head)
}

@NoHeapAlloc
public func DulinkMove(toHead: CPointer<Dulink>, fromHead: CPointer<Dulink>,
    countOfMoveOrReserve: Int32): Unit {
    let beg = DulinkNext(fromHead)
    let end = if (countOfMoveOrReserve > 0) {
        DulinkGetIndexByNext(fromHead, countOfMoveOrReserve)
    } else {
        DulinkGetIndexByPrev(fromHead, -countOfMoveOrReserve + 1)
    }
    let after = DulinkNext(end)
    DulinkSetNext(fromHead, after)
    DulinkSetPrev(after, fromHead)
    DulinkInsertHead(toHead, beg, end)
}

@NoHeapAlloc
private func LinkPrev(node: CPointer<Link>): CPointer<Link> {
    return unsafe { CPointer<CPointer<Link>>(node).read(0) }
}

@NoHeapAlloc
private func LinkNext(node: CPointer<Link>): CPointer<Link> {
    return unsafe { CPointer<CPointer<Link>>(node).read(1) }
}

@NoHeapAlloc
private func LinkSetPrev(node: CPointer<Link>, value: CPointer<Link>): Unit {
    unsafe { CPointer<CPointer<Link>>(node).write(0, value) }
}

@NoHeapAlloc
private func LinkSetNext(node: CPointer<Link>, value: CPointer<Link>): Unit {
    unsafe { CPointer<CPointer<Link>>(node).write(1, value) }
}

// list.h:233-302. Link is deliberately non-cyclic and LinkPushTail receives
// the current tail, exactly as the C++ header does.
@NoHeapAlloc
public func LinkInit(link: CPointer<Link>): Unit {
    LinkSetNext(link, CPointer<Link>())
    LinkSetPrev(link, CPointer<Link>())
}

@NoHeapAlloc
public func LinkRemove(item: CPointer<Link>): Unit {
    let prev = LinkPrev(item)
    let next = LinkNext(item)
    if (!prev.isNull()) {
        LinkSetNext(prev, next)
    }
    if (!next.isNull()) {
        LinkSetPrev(next, prev)
    }
}

@NoHeapAlloc
public func LinkPushHead(link: CPointer<Link>, object: CPointer<Unit>): Unit {
    let node = CPointer<Link>(object)
    LinkSetNext(node, LinkNext(link))
    LinkSetPrev(node, link)
    LinkSetNext(link, node)
    let next = LinkNext(node)
    if (!next.isNull()) {
        LinkSetPrev(next, node)
    }
}

@NoHeapAlloc
public func LinkPushTail(linkTail: CPointer<Link>, object: CPointer<Unit>): Unit {
    let node = CPointer<Link>(object)
    LinkSetNext(node, CPointer<Link>())
    LinkSetNext(linkTail, node)
    LinkSetPrev(node, linkTail)
}

@NoHeapAlloc
public func LinkIsEmpty(link: CPointer<Link>): Bool {
    return LinkNext(link).isNull() && LinkPrev(link).isNull()
}
