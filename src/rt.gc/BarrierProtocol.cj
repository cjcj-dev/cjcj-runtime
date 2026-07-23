package rt.gc

foreign {
    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_TryUpdateRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        toVersion: CPointer<CPointer<Unit>>): UInt8
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_TryUpdateRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        toVersion: CPointer<CPointer<Unit>>): UInt8
    @When[os == "Windows"]
    public func CJ_RT_TryUpdateRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        toVersion: CPointer<CPointer<Unit>>): UInt8

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_TryUntagRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        target: CPointer<CPointer<Unit>>): UInt8
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_TryUntagRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        target: CPointer<CPointer<Unit>>): UInt8
    @When[os == "Windows"]
    public func CJ_RT_TryUntagRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        target: CPointer<CPointer<Unit>>): UInt8

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_IsOldPointer(field: CPointer<UIntNative>): UInt8
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_IsOldPointer(field: CPointer<UIntNative>): UInt8
    @When[os == "Windows"]
    public func CJ_RT_IsOldPointer(field: CPointer<UIntNative>): UInt8

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_IsCurrentPointer(field: CPointer<UIntNative>): UInt8
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_IsCurrentPointer(field: CPointer<UIntNative>): UInt8
    @When[os == "Windows"]
    public func CJ_RT_IsCurrentPointer(field: CPointer<UIntNative>): UInt8

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_FindToVersion(object: CPointer<Unit>): CPointer<Unit>
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_FindToVersion(object: CPointer<Unit>): CPointer<Unit>
    @When[os == "Windows"]
    public func CJ_RT_FindToVersion(object: CPointer<Unit>): CPointer<Unit>

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_GetAndTryTagRefField(object: CPointer<Unit>): UIntNative
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_GetAndTryTagRefField(object: CPointer<Unit>): UIntNative
    @When[os == "Windows"]
    public func CJ_RT_GetAndTryTagRefField(object: CPointer<Unit>): UIntNative

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_IsUnmovableFromObject(object: CPointer<Unit>): UInt8
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_IsUnmovableFromObject(object: CPointer<Unit>): UInt8
    @When[os == "Windows"]
    public func CJ_RT_IsUnmovableFromObject(object: CPointer<Unit>): UInt8

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_TryForwardRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        toVersion: CPointer<CPointer<Unit>>): UInt8
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_TryForwardRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        toVersion: CPointer<CPointer<Unit>>): UInt8
    @When[os == "Windows"]
    public func CJ_RT_TryForwardRefField(object: CPointer<Unit>, field: CPointer<UIntNative>,
        toVersion: CPointer<CPointer<Unit>>): UInt8

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_ForwardObject(object: CPointer<Unit>): CPointer<Unit>
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_ForwardObject(object: CPointer<Unit>): CPointer<Unit>
    @When[os == "Windows"]
    public func CJ_RT_ForwardObject(object: CPointer<Unit>): CPointer<Unit>

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_RememberObjectInSatbBuffer(object: CPointer<Unit>): Unit
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_RememberObjectInSatbBuffer(object: CPointer<Unit>): Unit
    @When[os == "Windows"]
    public func CJ_RT_RememberObjectInSatbBuffer(object: CPointer<Unit>): Unit

    @When[os == "Linux" || env == "ohos"]
    public func CJ_RT_IsHeapAddress(address: CPointer<Unit>): UInt8
    @When[os == "macOS" || os == "iOS"]
    public func CJ_RT_IsHeapAddress(address: CPointer<Unit>): UInt8
    @When[os == "Windows"]
    public func CJ_RT_IsHeapAddress(address: CPointer<Unit>): UInt8
}
