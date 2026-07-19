// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.base

foreign {
    func cj_atomic_flag_test_and_set(p: CPointer<UInt8>): Bool
    func cj_atomic_flag_clear(p: CPointer<UInt8>): Unit
}

// Base/AtomicSpinLock.h:14-31. The atomic flag is the single inline byte at
// offset zero; operations below always address the original value through its pointer.
@C
public struct AtomicSpinLock {
    private var state: UInt8

    // Base/AtomicSpinLock.h:16-17,29. ATOMIC_FLAG_INIT is the clear byte and
    // the default destructor has no cleanup behavior.
    public init() {
        state = 0u8
    }
}

extend CPointer<AtomicSpinLock> {
    // Base/AtomicSpinLock.h:19-22. Tight empty-body acquire test-and-set loop.
    public func Lock(): Unit {
        while (unsafe { cj_atomic_flag_test_and_set(CPointer<UInt8>(this)) }) {}
    }

    // Base/AtomicSpinLock.h:24. Release the caller-owned inline flag.
    public func Unlock(): Unit {
        unsafe { cj_atomic_flag_clear(CPointer<UInt8>(this)) }
    }

    // Base/AtomicSpinLock.h:26. Exactly one acquire test-and-set attempt.
    public func TryLock(): Bool {
        return !unsafe { cj_atomic_flag_test_and_set(CPointer<UInt8>(this)) }
    }
}
