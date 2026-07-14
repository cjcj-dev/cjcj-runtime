package rt.common

import std.overflow.*

foreign {
    // Common/StateWord.h:61,64. Inline UInt16 acquire/release primitives.
    func cj_atomic_u16_load(pointer: CPointer<UInt16>): UInt16
    func cj_atomic_u16_store(pointer: CPointer<UInt16>, value: UInt16): Unit

    // Common/StateWord.h:66-75. The Layer0 bridge preserves the architecture-specific CAS order.
    func cj_stateword_u16_cas(pointer: CPointer<UInt16>, expected: UInt16, desired: UInt16): Int32
}

// Common/StateWord.h:21-30. C++ ObjectStateCode has uint8_t storage.
public type ObjectStateCode = UInt8
public const NORMAL: ObjectStateCode = 0u8
public const LOCKED: ObjectStateCode = 1u8
public const FORWARDING: ObjectStateCode = 2u8
public const FORWARDED: ObjectStateCode = 3u8

// Common/StateWord.h:32.
public const STATE_BIT_COUNT: UIntNative = 2

// Common/StateWord.h:17-78. The union's two-bit view occupies the low bits of this complete word.
@C
public struct ObjectState {
    public var stateBits: UInt16

    // Common/StateWord.h:35.
    public init() {
        stateBits = 0u16
    }

    // Common/StateWord.h:36.
    public init(word: UInt16) {
        stateBits = word
    }

    // Common/StateWord.h:37.
    public init(state: ObjectStateCode) {
        stateBits = UInt16(state)
    }

    // Common/StateWord.h:38.
    public init(state: ObjectState) {
        stateBits = state.stateBits
    }
}

// Common/StateWord.h:42-76. Pointer receivers keep the live object-header storage in native AS0.
extend CPointer<ObjectState> {
    // Common/StateWord.h:42.
    @NoHeapAlloc
    public func AtomicGetObjectState(): ObjectState {
        return ObjectState(AtomicGetStateBits())
    }

    // Common/StateWord.h:44.
    @NoHeapAlloc
    public func GetStateCode(): ObjectStateCode {
        return UInt8(GetStateBits() & 0x3u16)
    }

    // Common/StateWord.h:45. C++ bitfield assignment preserves the upper fourteen bits.
    @NoHeapAlloc
    public func SetStateCode(state: ObjectStateCode): Unit {
        let oldState = GetStateBits()
        let newState = (oldState & 0xfffcu16) | (UInt16(state) & 0x3u16)
        SetStateBits(newState)
    }

    // Common/StateWord.h:47.
    @NoHeapAlloc
    public func IsForwardableState(): Bool {
        return GetStateCode() == NORMAL
    }

    // Common/StateWord.h:48.
    @NoHeapAlloc
    public func IsLockedState(): Bool {
        return GetStateCode() == LOCKED
    }

    // Common/StateWord.h:49.
    @NoHeapAlloc
    public func IsForwardedState(): Bool {
        return GetStateCode() == FORWARDED
    }

    // Common/StateWord.h:60. ObjectState has one field at offset zero.
    @NoHeapAlloc
    public func GetStateBits(): UInt16 {
        return unsafe { CPointer<UInt16>(this).read(0) }
    }

    // Common/StateWord.h:61. ObjectState has one field at offset zero.
    @NoHeapAlloc
    public func AtomicGetStateBits(): UInt16 {
        return unsafe { cj_atomic_u16_load(CPointer<UInt16>(this)) }
    }

    // Common/StateWord.h:63. ObjectState has one field at offset zero.
    @NoHeapAlloc
    public func SetStateBits(newState: UInt16): Unit {
        unsafe { CPointer<UInt16>(this).write(0, newState) }
    }

    // Common/StateWord.h:64. ObjectState has one field at offset zero.
    @NoHeapAlloc
    public func AtomicSetStateBits(newState: UInt16): Unit {
        unsafe { cj_atomic_u16_store(CPointer<UInt16>(this), newState) }
    }

    // Common/StateWord.h:66-76.
    @NoHeapAlloc
    public func CompareExchangeStateBits(expected: UInt16, newState: UInt16): Bool {
        return unsafe { cj_stateword_u16_cas(CPointer<UInt16>(this), expected, newState) != 0 }
    }
}

// Common/StateWord.h:82-91.
public const ADDRESS_BIT_COUNT: UIntNative = 48
public const ADDRESS_ALIGN_MASK: UInt64 = 7u64
public const LOW_ADDRESS_BIT_COUNT: UIntNative = 32
public const LOW_ADDRESS_SHIFT: UInt64 = 0u64
public const LOW_ADDRESS_MASK: UInt64 = 0xffffffffu64
public const HIGH_ADDRESS_BIT_COUNT: UIntNative = 16
public const HIGH_ADDRESS_SHIFT: UInt64 = 32u64
public const HIGH_ADDRESS_MASK: UInt64 = 0xffffu64

// Common/StateWord.h:154-160,168-171. The 32-bit ARM object-header ABI keeps explicit padding.
@When[arch == "arm"]
@C
public struct StateWord {
    public var typeInfo: UInt32
    public var padding: UInt16
    public var objectState: ObjectState

    // Common/StateWord.h:156-160.
    init(typeInfo: UInt32, state: ObjectState) {
        this.typeInfo = typeInfo
        padding = 0u16
        objectState = state
    }
}

// Common/StateWord.h:161-164,172-175. Non-ARM targets store the complete 48-bit metadata address.
@When[arch != "arm"]
@C
public struct StateWord {
    public var typeInfoLow32: UInt32
    public var typeInfoHigh16: UInt16
    public var objectState: ObjectState

    // Common/StateWord.h:162-164.
    init(low32: UInt32, hi16: UInt16, state: ObjectState) {
        typeInfoLow32 = low32
        typeInfoHigh16 = hi16
        objectState = state
    }
}

// Base/Log.h:270-275 and Common/StateWord.h:147.
private var stateWordCheckMessage: VArray<UInt8, $38> = [
    67u8, 104u8, 101u8, 99u8, 107u8, 32u8, 102u8, 97u8, 105u8, 108u8, 101u8,
    100u8, 58u8, 32u8, 99u8, 117u8, 114u8, 114u8, 101u8, 110u8, 116u8, 46u8,
    73u8, 115u8, 76u8, 111u8, 99u8, 107u8, 101u8, 100u8, 83u8, 116u8, 97u8,
    116u8, 101u8, 40u8, 41u8, 0u8
]

// Common/StateWord.h:93-102. ARM keeps only the native 32-bit metadata address.
@When[arch == "arm"]
extend CPointer<StateWord> {
    @NoHeapAlloc
    public func GetTypeInfo(): CPointer<Unit> {
        let address = unsafe { CPointer<UInt32>(this).read(0) }
        var addressBits = UIntNative(address)
        return unsafe { CPointer<CPointer<Unit>>(inout addressBits).read(0) }
    }

    // Common/StateWord.h:105-113.
    @NoHeapAlloc
    public func SetTypeInfo(typeInfo: CPointer<Unit>): Unit {
        let address = unsafe { typeInfo.toUIntNative() }
        unsafe { CPointer<UInt32>(this).write(0, UInt32(address)) }
    }

    // Common/StateWord.h:117-123,154-160.
    @NoHeapAlloc
    public func GetStateWord(): StateWord {
        let typeInfo = unsafe { CPointer<UInt32>(this).read(0) }
        return StateWord(typeInfo, GetObjectState())
    }
}

// Common/StateWord.h:93-102. Non-ARM targets recombine the complete 48-bit metadata address.
@When[arch != "arm"]
extend CPointer<StateWord> {
    @NoHeapAlloc
    public func GetTypeInfo(): CPointer<Unit> {
        let low = UInt64(unsafe { CPointer<UInt32>(this).read(0) })
        var highAddress = unsafe { this.toUIntNative() }.wrappingAdd(4)
        let highPointer = unsafe { CPointer<CPointer<UInt16>>(inout highAddress).read(0) }
        let high = UInt64(unsafe { highPointer.read(0) })
        let address = high.wrappingShl(HIGH_ADDRESS_SHIFT) | low
        var addressBits = UIntNative(address)
        return unsafe { CPointer<CPointer<Unit>>(inout addressBits).read(0) }
    }

    // Common/StateWord.h:105-113.
    @NoHeapAlloc
    public func SetTypeInfo(typeInfo: CPointer<Unit>): Unit {
        let address = UInt64(unsafe { typeInfo.toUIntNative() })
        let low = UInt32(address.wrappingShr(LOW_ADDRESS_SHIFT) & LOW_ADDRESS_MASK)
        let high = UInt16(address.wrappingShr(HIGH_ADDRESS_SHIFT) & HIGH_ADDRESS_MASK)
        var highAddress = unsafe { this.toUIntNative() }.wrappingAdd(4)
        let highPointer = unsafe { CPointer<CPointer<UInt16>>(inout highAddress).read(0) }
        unsafe {
            CPointer<UInt32>(this).write(0, low)
            highPointer.write(0, high)
        }
    }

    // Common/StateWord.h:117-123,161-164.
    @NoHeapAlloc
    public func GetStateWord(): StateWord {
        let low = unsafe { CPointer<UInt32>(this).read(0) }
        var highAddress = unsafe { this.toUIntNative() }.wrappingAdd(4)
        let highPointer = unsafe { CPointer<CPointer<UInt16>>(inout highAddress).read(0) }
        let high = unsafe { highPointer.read(0) }
        return StateWord(low, high, GetObjectState())
    }
}

// Common/StateWord.h:116-151. These operations are layout-independent because ObjectState is at byte 6.
extend CPointer<StateWord> {
    // Common/StateWord.h:116.
    @NoHeapAlloc
    public func IsValidStateWord(): Bool {
        return unsafe { !GetTypeInfo().isNull() }
    }

    // Common/StateWord.h:126.
    @NoHeapAlloc
    public func GetObjectState(): ObjectState {
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        return objectState.AtomicGetObjectState()
    }

    // Common/StateWord.h:127.
    @NoHeapAlloc
    public func GetStateCode(): ObjectStateCode {
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        return objectState.GetStateCode()
    }

    // Common/StateWord.h:129.
    @NoHeapAlloc
    public func IsForwardableState(): Bool {
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        return objectState.IsForwardableState()
    }

    // Common/StateWord.h:130.
    @NoHeapAlloc
    public func IsForwardedState(): Bool {
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        return objectState.IsForwardedState()
    }

    // Common/StateWord.h:132.
    @NoHeapAlloc
    public func IsLockedWord(): Bool {
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        return objectState.IsLockedState()
    }

    // Common/StateWord.h:133.
    @NoHeapAlloc
    public func SetStateCode(state: ObjectStateCode): Unit {
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        objectState.SetStateCode(state)
    }

    // Common/StateWord.h:135-141. The desired complete raw word is deliberately one.
    @NoHeapAlloc
    public func TryLockStateWord(current: ObjectState): Bool {
        var currentValue = current
        let currentPointer = unsafe { CPointer<ObjectState>(inout currentValue) }
        if (currentPointer.IsLockedState()) {
            return false
        }
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        return objectState.CompareExchangeStateBits(current.stateBits, UInt16(LOCKED))
    }

    // Common/StateWord.h:143-151.
    @NoHeapAlloc
    public func UnlockStateWord(newState: ObjectState): Unit {
        var objectStateAddress = unsafe { this.toUIntNative() }.wrappingAdd(6)
        let objectState = unsafe { CPointer<CPointer<ObjectState>>(inout objectStateAddress).read(0) }
        while (true) {
            var current = objectState.AtomicGetObjectState()
            let currentPointer = unsafe { CPointer<ObjectState>(inout current) }
            if (!currentPointer.IsLockedState()) {
                unsafe { RtFatal(CString(CPointer<UInt8>(inout stateWordCheckMessage))) }
            }
            if (objectState.CompareExchangeStateBits(current.stateBits, newState.stateBits)) {
                return
            }
        }
    }
}
