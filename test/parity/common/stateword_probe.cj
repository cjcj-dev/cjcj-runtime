package rt.common

// Test-only C entries. This file is added only to a copied probe package; the production archive
// contains no StateWord C ABI exports. Every entry delegates to the live pointer-oriented surface.
@C
public func CJRT_ObjectStateConstructZero(destination: CPointer<ObjectState>): Unit {
    unsafe { destination.write(0, ObjectState()) }
}

@C
public func CJRT_ObjectStateConstructRaw(destination: CPointer<ObjectState>, raw: UInt16): Unit {
    unsafe { destination.write(0, ObjectState(raw)) }
}

@C
public func CJRT_ObjectStateConstructCode(destination: CPointer<ObjectState>, code: UInt8): Unit {
    unsafe { destination.write(0, ObjectState(code)) }
}

@C
public func CJRT_ObjectStateConstructCopy(destination: CPointer<ObjectState>, source: CPointer<ObjectState>): Unit {
    let value = unsafe { source.read(0) }
    unsafe { destination.write(0, ObjectState(value)) }
}

@C
public func CJRT_ObjectStateAtomicGetObjectState(state: CPointer<ObjectState>): UInt16 {
    return state.AtomicGetObjectState().stateBits
}

@C
public func CJRT_ObjectStateGetStateCode(state: CPointer<ObjectState>): UInt8 {
    return GetStateCode(state)
}

@C
public func CJRT_ObjectStateSetStateCode(state: CPointer<ObjectState>, code: UInt8): Unit {
    SetStateCode(state, code)
}

@C
public func CJRT_ObjectStatePredicates(state: CPointer<ObjectState>): UInt8 {
    let forwardable = if (IsForwardableState(state)) { 1u8 } else { 0u8 }
    let locked = if (state.IsLockedState()) { 2u8 } else { 0u8 }
    let forwarded = if (IsForwardedState(state)) { 4u8 } else { 0u8 }
    return forwardable | locked | forwarded
}

@C
public func CJRT_ObjectStateGetStateBits(state: CPointer<ObjectState>): UInt16 {
    return state.GetStateBits()
}

@C
public func CJRT_ObjectStateAtomicGetStateBits(state: CPointer<ObjectState>): UInt16 {
    return state.AtomicGetStateBits()
}

@C
public func CJRT_ObjectStateSetStateBits(state: CPointer<ObjectState>, raw: UInt16): Unit {
    state.SetStateBits(raw)
}

@C
public func CJRT_ObjectStateAtomicSetStateBits(state: CPointer<ObjectState>, raw: UInt16): Unit {
    state.AtomicSetStateBits(raw)
}

@C
public func CJRT_ObjectStateCompareExchangeStateBits(state: CPointer<ObjectState>, expected: UInt16,
    desired: UInt16): Int32 {
    return if (state.CompareExchangeStateBits(expected, desired)) { 1 } else { 0 }
}

@C
public func CJRT_StateWordSetRawState(stateWord: CPointer<StateWord>, raw: UInt16): Unit {
    let state = unsafe { CPointer<ObjectState>(CPointer<UInt8>(stateWord) + 6) }
    state.SetStateBits(raw)
}

@C
public func CJRT_StateWordGetRawState(stateWord: CPointer<StateWord>): UInt16 {
    let state = unsafe { CPointer<ObjectState>(CPointer<UInt8>(stateWord) + 6) }
    return state.GetStateBits()
}

@C
public func CJRT_StateWordGetTypeInfo(stateWord: CPointer<StateWord>): UIntNative {
    return unsafe { stateWord.GetTypeInfo().toUIntNative() }
}

@C
public func CJRT_StateWordSetTypeInfo(stateWord: CPointer<StateWord>, address: UIntNative): Unit {
    let typeInfo = unsafe { CPointer<Unit>(CPointer<UInt8>() + Int64(address)) }
    stateWord.SetTypeInfo(typeInfo)
}

@C
public func CJRT_StateWordIsValidStateWord(stateWord: CPointer<StateWord>): Int32 {
    return if (stateWord.IsValidStateWord()) { 1 } else { 0 }
}

@C
public func CJRT_StateWordGetStateWord(stateWord: CPointer<StateWord>, copy: CPointer<StateWord>): Unit {
    unsafe { copy.write(0, stateWord.GetStateWord()) }
}

@C
public func CJRT_StateWordGetObjectState(stateWord: CPointer<StateWord>): UInt16 {
    return stateWord.GetObjectState().stateBits
}

@C
public func CJRT_StateWordGetStateCode(stateWord: CPointer<StateWord>): UInt8 {
    return GetStateCode(stateWord)
}

@C
public func CJRT_StateWordPredicates(stateWord: CPointer<StateWord>): UInt8 {
    let forwardable = if (IsForwardableState(stateWord)) { 1u8 } else { 0u8 }
    let forwarded = if (IsForwardedState(stateWord)) { 2u8 } else { 0u8 }
    let locked = if (stateWord.IsLockedWord()) { 4u8 } else { 0u8 }
    return forwardable | forwarded | locked
}

@C
public func CJRT_StateWordSetStateCode(stateWord: CPointer<StateWord>, code: UInt8): Unit {
    SetStateCode(stateWord, code)
}

@C
public func CJRT_StateWordTryLockStateWord(stateWord: CPointer<StateWord>, currentRaw: UInt16): Int32 {
    return if (stateWord.TryLockStateWord(ObjectState(currentRaw))) { 1 } else { 0 }
}

@C
public func CJRT_StateWordUnlockStateWord(stateWord: CPointer<StateWord>, newRaw: UInt16): Unit {
    stateWord.UnlockStateWord(ObjectState(newRaw))
}
