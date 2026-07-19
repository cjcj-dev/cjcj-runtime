// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.

package rt.base

foreign {
    func cj_pthread_spin_init(p: CPointer<Int32>): Unit
    func cj_pthread_spin_lock(p: CPointer<Int32>): Unit
    func cj_pthread_spin_unlock(p: CPointer<Int32>): Unit
    func cj_pthread_spin_trylock(p: CPointer<Int32>): Int32
}

// Base/SpinLock.h:15-18,28-30. Linux x86_64 pthread_spinlock_t is an inline
// volatile int with size/alignment 4/4; the only field remains at offset zero.
// LANG-BOUNDARY: Cangjie requires field initialization before the constructor
// body. pthread_spin_init then establishes the source-defined live state.
@C
public struct SpinLock {
    private var spinlock: Int32

    public init() {
        spinlock = 0
        unsafe { cj_pthread_spin_init(CPointer<Int32>(inout this.spinlock)) }
    }
}

// Base/SpinLock.h:22. Exactly one pthread_spin_lock call on the original field.
public func Lock(self: CPointer<SpinLock>): Unit {
    unsafe { cj_pthread_spin_lock(CPointer<Int32>(self)) }
}

// Base/SpinLock.h:24. Exactly one pthread_spin_unlock call on the original field.
public func Unlock(self: CPointer<SpinLock>): Unit {
    unsafe { cj_pthread_spin_unlock(CPointer<Int32>(self)) }
}

// Base/SpinLock.h:26. Exactly one try call; true iff the native return code is zero.
public func TryLock(self: CPointer<SpinLock>): Bool {
    return unsafe { cj_pthread_spin_trylock(CPointer<Int32>(self)) == 0 }
}

// SCOPED-SPINLOCK-DETERMINISTIC-DESTRUCTION: Base/SpinLock.h:20,33-39 remain
// unported. Inline @C structs reject ~init, while class ~init is GC-timed.
