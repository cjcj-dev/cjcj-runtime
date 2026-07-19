// Compile-fail probe for Base/SpinLock.h:20,33-39. The only Cangjie
// finalizer spelling is intentionally applied to inline @C value records;
// the pinned compiler must reject it rather than silently give GC lifetime.
@C
struct SpinLockLifetimeProbe {
    var state: Int32

    init() {
        state = 0
    }

    ~init() {
        state = -1
    }
}

@C
struct ScopedEnterSpinLockLifetimeProbe {
    var spinLock: CPointer<SpinLockLifetimeProbe>

    init(spinLock: CPointer<SpinLockLifetimeProbe>) {
        this.spinLock = spinLock
    }

    ~init() {
        unsafe { spinLock.write(SpinLockLifetimeProbe()) }
    }
}

main(): Int64 {
    return 0
}
