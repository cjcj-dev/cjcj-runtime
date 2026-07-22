package rt.gc

foreign {
    // Common/MarkWorkStack.h:82,99,103,129. The runtime does not override global
    // operator new/delete. All three supported C++ targets use the Itanium ABI.
    @When[os == "Linux" || env == "ohos"]
    func _Znwm(size: UIntNative): CPointer<Unit>
    @When[os == "macOS" || os == "iOS"]
    func _Znwm(size: UIntNative): CPointer<Unit>
    @When[os == "Windows"]
    func _Znwm(size: UIntNative): CPointer<Unit>

    @When[os == "Linux" || env == "ohos"]
    func _ZdlPv(address: CPointer<Unit>): Unit
    @When[os == "macOS" || os == "iOS"]
    func _ZdlPv(address: CPointer<Unit>): Unit
    @When[os == "Windows"]
    func _ZdlPv(address: CPointer<Unit>): Unit

    func abort(): Unit
}

// Common/MarkWorkStack.h has one production instantiation: MarkStack<BaseObject*>.
// Erasing BaseObject* to CPointer<Unit> preserves the pointer representation while
// keeping this collector foundation independent of the not-yet-ported object owner.
@C
public struct MarkStackBuf {
    public static const MAX: UIntNative = 64

    public var next: CPointer<MarkStackBuf>
    public var pre: CPointer<MarkStackBuf>
    private var count: UIntNative
    private var stack: VArray<CPointer<Unit>, $64>

    public init() {
        next = CPointer<MarkStackBuf>()
        pre = CPointer<MarkStackBuf>()
        count = 0
        stack = VArray<CPointer<Unit>, $64>(repeat: CPointer<Unit>())
    }
}

@C
public struct MarkStack {
    private var h: CPointer<MarkStackBuf>
    private var t: CPointer<MarkStackBuf>
    private var s: UIntNative

    public init() {
        h = CPointer<MarkStackBuf>()
        t = CPointer<MarkStackBuf>()
        s = 0
    }
}

private func BufCountAddress(buf: CPointer<MarkStackBuf>): CPointer<UIntNative> {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(buf) + 16) }
}

private func BufStackAddress(buf: CPointer<MarkStackBuf>): CPointer<CPointer<Unit>> {
    return unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(buf) + 24) }
}

private func StackHeadAddress(stack: CPointer<MarkStack>): CPointer<CPointer<MarkStackBuf>> {
    return CPointer<CPointer<MarkStackBuf>>(stack)
}

private func StackTailAddress(stack: CPointer<MarkStack>): CPointer<CPointer<MarkStackBuf>> {
    return unsafe { CPointer<CPointer<MarkStackBuf>>(CPointer<UInt8>(stack) + 8) }
}

private func StackSizeAddress(stack: CPointer<MarkStack>): CPointer<UIntNative> {
    return unsafe { CPointer<UIntNative>(CPointer<UInt8>(stack) + 16) }
}

private func NewBuffer(): CPointer<MarkStackBuf> {
    let raw = unsafe { _Znwm(sizeOf<MarkStackBuf>()) }
    let buf = CPointer<MarkStackBuf>(raw)
    unsafe {
        CPointer<CPointer<MarkStackBuf>>(buf).write(0, CPointer<MarkStackBuf>())
        CPointer<CPointer<MarkStackBuf>>(CPointer<UInt8>(buf) + 8).write(0, CPointer<MarkStackBuf>())
        BufCountAddress(buf).write(0, 0)
    }
    return buf
}

private func DeleteBuffer(buf: CPointer<MarkStackBuf>): Unit {
    unsafe { _ZdlPv(CPointer<Unit>(buf)) }
}

// MarkWorkStack.h:24-45.
public func MarkStackBufFull(buf: CPointer<MarkStackBuf>): Bool {
    return unsafe { BufCountAddress(buf).read(0) } == MarkStackBuf.MAX
}

public func MarkStackBufEmpty(buf: CPointer<MarkStackBuf>): Bool {
    return unsafe { BufCountAddress(buf).read(0) } == 0
}

public func MarkStackBufPushBack(buf: CPointer<MarkStackBuf>, value: CPointer<Unit>): Unit {
    let count = unsafe { BufCountAddress(buf).read(0) }
    if (count == MarkStackBuf.MAX) {
        unsafe { abort() }
    }
    unsafe {
        BufStackAddress(buf).write(Int64(count), value)
        BufCountAddress(buf).write(0, count + 1)
    }
}

public func MarkStackBufBack(buf: CPointer<MarkStackBuf>): CPointer<Unit> {
    let count = unsafe { BufCountAddress(buf).read(0) }
    if (count == 0) {
        unsafe { abort() }
    }
    return unsafe { BufStackAddress(buf).read(Int64(count - 1)) }
}

public func MarkStackBufPopBack(buf: CPointer<MarkStackBuf>): Unit {
    let count = unsafe { BufCountAddress(buf).read(0) }
    if (count == 0) {
        unsafe { abort() }
    }
    unsafe { BufCountAddress(buf).write(0, count - 1) }
}

// MarkWorkStack.h:52-78. Cangjie values do not expose C++ move constructors, so
// owner storage is initialized explicitly and move construction is a named leaf.
public func MarkStackConstruct(stack: CPointer<MarkStack>): Unit {
    unsafe {
        StackHeadAddress(stack).write(0, CPointer<MarkStackBuf>())
        StackTailAddress(stack).write(0, CPointer<MarkStackBuf>())
        StackSizeAddress(stack).write(0, 0)
    }
}

public func MarkStackMoveConstruct(destination: CPointer<MarkStack>, source: CPointer<MarkStack>): Unit {
    unsafe {
        StackHeadAddress(destination).write(0, MarkStackHead(source))
        StackTailAddress(destination).write(0, MarkStackTail(source))
        StackSizeAddress(destination).write(0, MarkStackSize(source))
    }
    MarkStackClean(source)
}

public func MarkStackConstructFromBuffer(stack: CPointer<MarkStack>, buf: CPointer<MarkStackBuf>): Unit {
    MarkStackConstruct(stack)
    unsafe { StackHeadAddress(stack).write(0, buf) }
    var current = buf
    while (!current.isNull()) {
        unsafe {
            StackSizeAddress(stack).write(0, StackSizeAddress(stack).read(0) + 1)
            if (current.read(0).next.isNull()) {
                StackTailAddress(stack).write(0, current)
            }
            current = current.read(0).next
        }
    }
}

public func MarkStackHead(stack: CPointer<MarkStack>): CPointer<MarkStackBuf> {
    return unsafe { StackHeadAddress(stack).read(0) }
}

public func MarkStackTail(stack: CPointer<MarkStack>): CPointer<MarkStackBuf> {
    return unsafe { StackTailAddress(stack).read(0) }
}

public func MarkStackSize(stack: CPointer<MarkStack>): UIntNative {
    return unsafe { StackSizeAddress(stack).read(0) }
}

public func MarkStackEmpty(stack: CPointer<MarkStack>): Bool {
    return MarkStackSize(stack) == 0 && MarkStackHead(stack).isNull() && MarkStackTail(stack).isNull()
}

public func MarkStackClear(stack: CPointer<MarkStack>): Unit {
    while (!MarkStackEmpty(stack)) {
        let tmp = MarkStackHead(stack)
        let next = unsafe { tmp.read(0).next }
        unsafe {
            StackHeadAddress(stack).write(0, next)
            if (!next.isNull()) {
                CPointer<CPointer<MarkStackBuf>>(CPointer<UInt8>(next) + 8).write(
                    0, CPointer<MarkStackBuf>())
            }
            StackSizeAddress(stack).write(0, MarkStackSize(stack) - 1)
        }
        DeleteBuffer(tmp)
    }
    unsafe { StackTailAddress(stack).write(0, CPointer<MarkStackBuf>()) }
}

public func MarkStackDestroy(stack: CPointer<MarkStack>): Unit {
    MarkStackClear(stack)
}

private func MarkStackPushBuffer(stack: CPointer<MarkStack>, buf: CPointer<MarkStackBuf>): Unit {
    if (MarkStackEmpty(stack)) {
        unsafe {
            StackHeadAddress(stack).write(0, buf)
            StackTailAddress(stack).write(0, buf)
            StackSizeAddress(stack).write(0, MarkStackSize(stack) + 1)
        }
        return
    }
    let tail = MarkStackTail(stack)
    unsafe {
        CPointer<CPointer<MarkStackBuf>>(CPointer<UInt8>(buf) + 8).write(0, tail)
        CPointer<CPointer<MarkStackBuf>>(tail).write(0, buf)
        StackTailAddress(stack).write(0, buf)
        StackSizeAddress(stack).write(0, MarkStackSize(stack) + 1)
    }
}

private func MarkStackPopBuffer(stack: CPointer<MarkStack>): CPointer<MarkStackBuf> {
    if (MarkStackEmpty(stack)) {
        return CPointer<MarkStackBuf>()
    }
    let result = MarkStackTail(stack)
    let pre = unsafe { result.read(0).pre }
    unsafe {
        StackTailAddress(stack).write(0, pre)
        if (!pre.isNull()) {
            CPointer<CPointer<MarkStackBuf>>(pre).write(0, CPointer<MarkStackBuf>())
        } else {
            StackHeadAddress(stack).write(0, CPointer<MarkStackBuf>())
        }
        CPointer<CPointer<MarkStackBuf>>(CPointer<UInt8>(result) + 8).write(
            0, CPointer<MarkStackBuf>())
        StackSizeAddress(stack).write(0, MarkStackSize(stack) - 1)
    }
    return result
}

public func MarkStackPushBack(stack: CPointer<MarkStack>, value: CPointer<Unit>): Unit {
    let tail = MarkStackTail(stack)
    if (tail.isNull() || MarkStackBufFull(tail)) {
        MarkStackPushBuffer(stack, NewBuffer())
    }
    MarkStackBufPushBack(MarkStackTail(stack), value)
}

public func MarkStackBack(stack: CPointer<MarkStack>): CPointer<Unit> {
    let tail = MarkStackTail(stack)
    if (tail.isNull()) {
        return CPointer<Unit>()
    }
    return MarkStackBufBack(tail)
}

public func MarkStackPopBack(stack: CPointer<MarkStack>): Unit {
    if (MarkStackEmpty(stack)) {
        unsafe { abort() }
    }
    let tail = MarkStackTail(stack)
    MarkStackBufPopBack(tail)
    if (MarkStackBufEmpty(tail)) {
        DeleteBuffer(MarkStackPopBuffer(stack))
    }
}

// MarkWorkStack.h:112-132.
public func MarkStackInsert(stack: CPointer<MarkStack>, other: CPointer<MarkStack>): Unit {
    if (MarkStackEmpty(other)) {
        return
    }
    if (MarkStackHead(stack).isNull()) {
        unsafe {
            StackHeadAddress(stack).write(0, MarkStackHead(other))
            StackTailAddress(stack).write(0, MarkStackTail(other))
            StackSizeAddress(stack).write(0, MarkStackSize(other))
        }
        MarkStackClean(other)
        return
    }
    let tail = MarkStackTail(stack)
    let otherHead = MarkStackHead(other)
    unsafe {
        CPointer<CPointer<MarkStackBuf>>(tail).write(0, otherHead)
        CPointer<CPointer<MarkStackBuf>>(CPointer<UInt8>(otherHead) + 8).write(0, tail)
        StackTailAddress(stack).write(0, MarkStackTail(other))
        StackSizeAddress(stack).write(0, MarkStackSize(stack) + MarkStackSize(other))
    }
    MarkStackClean(other)
}

public func MarkStackSplit(stack: CPointer<MarkStack>, splitNum: UIntNative): CPointer<MarkStackBuf> {
    if (splitNum == 0 || MarkStackSize(stack) == 0) {
        return CPointer<MarkStackBuf>()
    }
    let result = MarkStackHead(stack)
    var num: UIntNative = 0
    while (num < splitNum) {
        let head = MarkStackHead(stack)
        let next = unsafe { head.read(0).next }
        unsafe { StackHeadAddress(stack).write(0, next) }
        if (num == splitNum - 1) {
            if (!next.isNull()) {
                unsafe {
                    CPointer<CPointer<MarkStackBuf>>(CPointer<UInt8>(next) + 8).write(
                        0, CPointer<MarkStackBuf>())
                }
            }
            unsafe { CPointer<CPointer<MarkStackBuf>>(head).write(0, CPointer<MarkStackBuf>()) }
        }
        unsafe { StackSizeAddress(stack).write(0, MarkStackSize(stack) - 1) }
        num += 1
        if (MarkStackHead(stack).isNull()) {
            unsafe { StackTailAddress(stack).write(0, CPointer<MarkStackBuf>()) }
            return result
        }
    }
    return result
}

// MarkWorkStack.h:172-181. clean transfers ownership without deleting buffers.
public func MarkStackClean(stack: CPointer<MarkStack>): Unit {
    if (MarkStackEmpty(stack)) {
        return
    }
    MarkStackConstruct(stack)
}
