package rt.heap.allocator

foreign {
    // Common/BaseObject.cpp:139-150; retained until ObjectModel is ported.
    func _ZNK12MapleRuntime10BaseObject7GetSizeEv(baseObject: CPointer<Unit>): UIntNative

    // third_party_bounds_checking_function/include/securec.h.
    func memset_s(destination: CPointer<Unit>, destinationSize: UIntNative,
        value: Int32, count: UIntNative): Int32

    // Base/Log.h:292-297. No variadic arguments are needed for this fixed format.
    func _ZN12MapleRuntime6Logger9GetLoggerEv(): CPointer<Unit>
    func _ZN12MapleRuntime6Logger9FormatLogE10RTLogLevelbPKcz(logger: CPointer<Unit>,
        level: Int32, notInSignalHandler: Bool, format: CPointer<UInt8>): Unit
}

private const EOK: Int32 = 0
private const RTLOG_ERROR: Int32 = 5

private var slotListMemsetFailure: VArray<UInt8, $14> = [
    109u8, 101u8, 109u8, 115u8, 101u8, 116u8, 95u8, 115u8, 32u8, 102u8,
    97u8, 105u8, 108u8, 0u8
]

// Heap/Allocator/SlotList.h:14-17. StateWord is an opaque complete 8-byte word
// here because rt.common depends on this package; SlotList never reads its bits.
@C
public struct ObjectSlot {
    public var stateWord: UInt64
    public var next: CPointer<ObjectSlot>

    public init(stateWord: UInt64, next: CPointer<ObjectSlot>) {
        this.stateWord = stateWord
        unsafe { this.next = next }
    }
}

// Heap/Allocator/SlotList.h:19-54.
@C
public struct SlotList {
    private var head: CPointer<ObjectSlot>

    // Heap/Allocator/SlotList.h:53.
    public init() {
        head = CPointer<ObjectSlot>()
    }

    // Heap/Allocator/SlotList.h:21-27.
    @NoHeapAlloc
    public mut func PushFront(slot: CPointer<Unit>): Unit {
        let headSlot = unsafe { CPointer<ObjectSlot>(slot) }
        ClearExtraContent(slot)
        unsafe {
            CPointer<CPointer<ObjectSlot>>(CPointer<UInt8>(headSlot) +
                Int64(sizeOf<UInt64>())).write(0, head)
        }
        head = headSlot
    }

    // Heap/Allocator/SlotList.h:29-38.
    @NoHeapAlloc
    public mut func PopFront(size: UIntNative): UIntNative {
        if (head.isNull() || size != unsafe { _ZNK12MapleRuntime10BaseObject7GetSizeEv(CPointer<Unit>(head)) }) {
            return 0
        }
        let allocSlot = head
        head = unsafe { allocSlot.read().next }
        unsafe {
            CPointer<CPointer<ObjectSlot>>(CPointer<UInt8>(allocSlot) +
                Int64(sizeOf<UInt64>())).write(0, CPointer<ObjectSlot>())
        }
        return unsafe { allocSlot.toUIntNative() }
    }

    // Heap/Allocator/SlotList.h:40.
    @NoHeapAlloc
    public mut func Clear(): Unit {
        head = CPointer<ObjectSlot>()
    }

    // Heap/Allocator/SlotList.h:42-50.
    @NoHeapAlloc
    public func ClearExtraContent(slot: CPointer<Unit>): Unit {
        let size = unsafe { _ZNK12MapleRuntime10BaseObject7GetSizeEv(slot) } - sizeOf<ObjectSlot>()
        if (size > 0) {
            let start = unsafe { CPointer<Unit>(CPointer<UInt8>(slot) + Int64(sizeOf<ObjectSlot>())) }
            if (unsafe { memset_s(start, size, 0, size) } != EOK) {
                unsafe {
                    let logger = _ZN12MapleRuntime6Logger9GetLoggerEv()
                    _ZN12MapleRuntime6Logger9FormatLogE10RTLogLevelbPKcz(logger, RTLOG_ERROR,
                        true, CPointer<UInt8>(inout slotListMemsetFailure))
                }
            }
        }
    }
}
