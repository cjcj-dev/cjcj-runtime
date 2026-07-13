package rt.heap.allocator

import rt.base.*

// Port of Heap/Allocator/LocalDeque.h (SingleUseDeque, LocalDeque, RTAllocatorT).
//
// The C++ types are `template<class ValType>` / `template<size_t, size_t>` but every
// one carries `static_assert(sizeof(ValType) == sizeof(void*))`, so their only legal
// instantiation is pointer-sized (they are only ever used with Node* / Node**). The
// selfhost compiler cannot yet compile a generic parameterised by CType through
// CPointer<T>/VArray<T,$n>, nor construct a CPointer from a raw integer address, so
// these are ported as pointer-typed structures whose element is CPointer<Unit> (void*)
// and whose addresses are byte offsets from a base CPointer reached by pointer
// arithmetic. That is behaviourally and layout identical to the C++ template's sole
// valid instantiation; only the generic syntax is dropped.

// LocalDeque.h:17-22. DEBUG_DEQUE is false, so DEQUE_ASSERT is a no-op; the bounds
// asserts are compiled out exactly as in C++.

// Slot/value size is sizeof(void*); the static_assert fixes it at 8 on every target.
const DEQUE_VAL_SIZE: Int64 = 8

// LocalDeque.h:41. "maple_alloc_ros_sud" with static, process-lifetime backing storage.
var SUD_TAG: VArray<UInt8, $20> = [
    109u8, 97u8, 112u8, 108u8, 101u8, 95u8, 97u8, 108u8, 108u8, 111u8,
    99u8, 95u8, 114u8, 111u8, 115u8, 95u8, 115u8, 117u8, 100u8, 0u8
]
// LocalDeque.h:197. "maplert_alloc".
var RTALLOC_TAG: VArray<UInt8, $14> = [
    109u8, 97u8, 112u8, 108u8, 101u8, 114u8, 116u8, 95u8, 97u8, 108u8, 108u8, 111u8, 99u8, 0u8
]

// Windows must commit reserved pages before first access; every other target maps them
// accessible up front. LocalDeque.h:44-46 / :200-202.
@When[os == "Windows"]
func CommitIfWindows(base: CPointer<Unit>, size: UIntNative): Unit {
    MemMap.CommitMemory(base, size)
}
@When[os != "Windows"]
func CommitIfWindows(base: CPointer<Unit>, size: UIntNative): Unit {
    let _ = base
    let _ = size
}

// Element pointer at a byte offset from a base, without integer->pointer construction.
func DequeSlot(base: CPointer<Unit>, off: Int64): CPointer<CPointer<Unit>> {
    return unsafe { CPointer<CPointer<Unit>>(CPointer<UInt8>(base) + off) }
}

// LocalDeque.h:33-101. Single-use deque: usable as a queue or a stack; Clear() is O(1)
// and the underlying MemMap is reused rather than freed.
public class SingleUseDeque {
    private var memMap: CPointer<MemMap> = CPointer<MemMap>()
    private var baseAddr: CPointer<Unit> = CPointer<Unit>()
    // Offsets from baseAddr, mirroring the C++ begin/front/top/end MAddress fields.
    private var beginOff: Int64 = 0
    private var frontOff: Int64 = 0
    private var topOff: Int64 = 0
    private var endOff: Int64 = 0

    // LocalDeque.h:37-50.
    public func Init(mapSize: UIntNative): Unit {
        let opt = Option(CString(CPointer<UInt8>(inout SUD_TAG)), CPointer<Unit>(),
            MemMap.DEFAULT_MEM_FLAGS, MemMap.DEFAULT_MEM_PROT, false)
        memMap = MemMap.MapMemory(mapSize, mapSize, opt: opt)
        let map = unsafe { memMap.read() }
        CommitIfWindows(map.GetBaseAddr(), mapSize)
        baseAddr = map.GetBaseAddr()
        beginOff = 0
        endOff = OffsetBytes(baseAddr, map.GetCurrEnd())
        Clear()
    }

    // LocalDeque.h:51-59. Share the same MemMap as another sud.
    public func Init(other: CPointer<MemMap>): Unit {
        memMap = other
        let map = unsafe { memMap.read() }
        baseAddr = map.GetBaseAddr()
        beginOff = 0
        endOff = OffsetBytes(baseAddr, map.GetCurrEnd())
        Clear()
    }

    // LocalDeque.h:60.
    public func Fini(): Unit {
        var mm = memMap
        MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout mm))
        memMap = mm
    }

    // LocalDeque.h:61.
    public func GetMemMap(): CPointer<MemMap> {
        return memMap
    }

    // LocalDeque.h:62.
    public func Empty(): Bool {
        return topOff < frontOff
    }

    // LocalDeque.h:63-68.
    public func Push(v: CPointer<Unit>): Unit {
        topOff += DEQUE_VAL_SIZE
        unsafe { DequeSlot(baseAddr, topOff).write(0, v) }
    }

    // LocalDeque.h:69-73.
    public func Top(): CPointer<Unit> {
        return unsafe { DequeSlot(baseAddr, topOff).read(0) }
    }

    // LocalDeque.h:74-78.
    public func Pop(): Unit {
        topOff -= DEQUE_VAL_SIZE
    }

    // LocalDeque.h:79-83.
    public func Front(): CPointer<Unit> {
        return unsafe { DequeSlot(baseAddr, frontOff).read(0) }
    }

    // LocalDeque.h:84-88.
    public func PopFront(): Unit {
        frontOff += DEQUE_VAL_SIZE
    }

    // LocalDeque.h:89-93.
    public func Clear(): Unit {
        frontOff = beginOff
        topOff = beginOff - DEQUE_VAL_SIZE
    }
}

// LocalDeque.h:107-179. Stack-local deque fronted by an inline array; it spills to a
// SingleUseDeque only after the local array fills, avoiding RAM visits and unfreeable
// memory for the common small case.
public class LocalDeque {
    // LocalDeque.h:111. ALLOC_UTIL_PAGE_SIZE / sizeof(ValType) = 4096 / 8.
    public static const LOCAL_LENGTH: Int64 = 512

    private var front: Int64 = 0
    private var top: Int64 = -1
    private let sud: SingleUseDeque
    private var array: VArray<CPointer<Unit>, $512>

    // LocalDeque.h:112.
    public init(singleUseDeque: SingleUseDeque) {
        sud = singleUseDeque
        array = VArray<CPointer<Unit>, $512>(repeat: CPointer<Unit>())
    }

    // LocalDeque.h:114.
    public func Empty(): Bool {
        return (top < front) || (front == LOCAL_LENGTH && sud.Empty())
    }

    // LocalDeque.h:115-125.
    public func Push(v: CPointer<Unit>): Unit {
        if (top < LOCAL_LENGTH - 1) {
            top += 1
            array[top] = v
            return
        } else if (top == LOCAL_LENGTH - 1) {
            top += 1
            sud.Clear()
        }
        sud.Push(v)
    }

    // LocalDeque.h:126-133.
    public func Top(): CPointer<Unit> {
        if (top < LOCAL_LENGTH) {
            return array[top]
        }
        return sud.Top()
    }

    // LocalDeque.h:134-153.
    public func Pop(): Unit {
        if (top < LOCAL_LENGTH) {
            top -= 1
            return
        }
        sud.Pop()
        if (sud.Empty()) {
            // if local array is empty, reuse local array
            if (front == LOCAL_LENGTH) {
                front = 0
                top = -1
            } else if (front < LOCAL_LENGTH) {
                top -= 1
                return
            }
        }
    }

    // LocalDeque.h:154-162.
    public func Front(): CPointer<Unit> {
        if (front < LOCAL_LENGTH) {
            return array[front]
        }
        return sud.Front()
    }

    // LocalDeque.h:163-172.
    public func PopFront(): Unit {
        if (front < LOCAL_LENGTH) {
            front += 1
            return
        }
        sud.PopFront()
    }
}

// LocalDeque.h:183-235. Lightweight fixed-size native allocator over a MemMap; it never
// recycles pages, only individual slots via an intrusive free list. The C++ non-type
// template params <allocSize, align> become an Init argument since the sole instantiation
// (CartesianTree's nodeAllocator) supplies concrete sizes; align is enforced by the
// caller-provided allocSize being a multiple of it, exactly as the static_asserts require.
public class RTAllocatorT {
    // Intrusive free-list head; null means bump from currAddr. LocalDeque.h:231.
    private var head: CPointer<Unit> = CPointer<Unit>()
    private var baseAddr: CPointer<Unit> = CPointer<Unit>()
    private var currOff: Int64 = 0
    private var endOff: Int64 = 0
    private var memMap: CPointer<MemMap> = CPointer<MemMap>()
    private var allocSize: Int64 = 0

    // LocalDeque.h:190-205.
    public func Init(allocSizeBytes: Int64, mapSize: UIntNative): Unit {
        allocSize = allocSizeBytes
        let opt = Option(CString(CPointer<UInt8>(inout RTALLOC_TAG)), CPointer<Unit>(),
            MemMap.DEFAULT_MEM_FLAGS, MemMap.DEFAULT_MEM_PROT, false)
        memMap = MemMap.MapMemory(mapSize, mapSize, opt: opt)
        let map = unsafe { memMap.read() }
        CommitIfWindows(map.GetBaseAddr(), mapSize)
        baseAddr = map.GetBaseAddr()
        currOff = 0
        endOff = OffsetBytes(baseAddr, map.GetCurrEnd())
    }

    // LocalDeque.h:207.
    public func Fini(): Unit {
        var mm = memMap
        MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout mm))
        memMap = mm
    }

    // LocalDeque.h:209-222. Bump-allocate a fresh slot, or reuse a freed one. No zeroing.
    public func Allocate(): CPointer<Unit> {
        if (head.isNull()) {
            let result = unsafe { CPointer<Unit>(CPointer<UInt8>(baseAddr) + currOff) }
            currOff += allocSize
            return result
        }
        let result = head
        head = unsafe { CPointer<CPointer<Unit>>(head).read(0) }
        return result
    }

    // LocalDeque.h:224-228. Push the slot onto the intrusive free list.
    public func Deallocate(address: CPointer<Unit>): Unit {
        unsafe { CPointer<CPointer<Unit>>(address).write(0, head) }
        head = address
    }
}

// Byte distance from base to end, mirroring the C++ MAddress subtraction used to derive
// the mapped current-size bound.
func OffsetBytes(base: CPointer<Unit>, end: CPointer<Unit>): Int64 {
    return Int64(end.toUIntNative() - base.toUIntNative())
}
