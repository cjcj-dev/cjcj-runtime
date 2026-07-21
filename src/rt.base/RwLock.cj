// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.base

foreign {
    func sched_yield(): Int32
    func cj_atomic_i32_cas(p: CPointer<Int32>, expected: Int32, desired: Int32): Int32
    func cj_atomic_i32_load(p: CPointer<Int32>): Int32
    func cj_atomic_i32_store(p: CPointer<Int32>, v: Int32): Unit
    func cj_atomic_i32_fetch_sub(p: CPointer<Int32>, v: Int32): Int32
    func abort(): Unit
}

// Base/Log.h:270-275. NUL-terminated static expansion of
// CHECK(lockCount.load() == WRITE_LOCKED), consumed by the existing native fatal path.
private var rwLockWriteCheckMessage: VArray<UInt8, $47> = [
    67u8, 104u8, 101u8, 99u8, 107u8, 32u8, 102u8, 97u8, 105u8, 108u8, 101u8, 100u8,
    58u8, 32u8, 108u8, 111u8, 99u8, 107u8, 67u8, 111u8, 117u8, 110u8, 116u8, 46u8,
    108u8, 111u8, 97u8, 100u8, 40u8, 41u8, 32u8, 61u8, 61u8, 32u8, 87u8, 82u8,
    73u8, 84u8, 69u8, 95u8, 76u8, 79u8, 67u8, 75u8, 69u8, 68u8, 0u8
]

// Base/RwLock.h:15,70-75. Inline 4-byte lock state (mirrors std::atomic<int> lockCount),
// so RwLock is byte-faithful and value-embeddable in UnitMetadata. Atomics go through the
// rt0 Atomic.cpp Layer0 bridge; the lock algorithm below is a faithful Cangjie port.
@C
public struct RwLock {
    // Base/RwLock.h:71-74. 0 = unlocked, -1 = write-locked, +N = N read holders.
    private static const WRITE_LOCKED: Int32 = -1
    var lockCount: Int32

    // Base/RwLock.h:75. Mirrors std::atomic<int> lockCount{0}.
    public init() {
        lockCount = 0
    }

    // Base/RwLock.h:17-26. SeqCst bridge operations are stronger than the C++
    // acquire/release orders; failed strong CAS explicitly reloads the expected count.
    public mut func LockRead(): Unit {
        let p = unsafe { CPointer<Int32>(inout this.lockCount) }
        var count = unsafe { cj_atomic_i32_load(p) }
        var acquired = false
        do {
            while (count == WRITE_LOCKED) {
                unsafe { let _ = sched_yield() }
                count = unsafe { cj_atomic_i32_load(p) }
            }
            acquired = unsafe { cj_atomic_i32_cas(p, count, count + 1) != 0 }
            if (!acquired) {
                count = unsafe { cj_atomic_i32_load(p) }
            }
        } while (!acquired)
    }

    // Base/RwLock.h:28-34. Retry 0 -> WRITE_LOCKED and yield after every failed CAS.
    public mut func LockWrite(): Unit {
        let p = unsafe { CPointer<Int32>(inout this.lockCount) }
        var count: Int32 = 0
        while (unsafe { cj_atomic_i32_cas(p, count, WRITE_LOCKED) == 0 }) {
            unsafe { let _ = sched_yield() }
            count = 0
        }
    }

    // Base/RwLock.h:36-43. Make exactly one 0 -> WRITE_LOCKED CAS attempt.
    public mut func TryLockWrite(): Bool {
        let p = unsafe { CPointer<Int32>(inout this.lockCount) }
        let count: Int32 = 0
        if (unsafe { cj_atomic_i32_cas(p, count, WRITE_LOCKED) != 0 }) {
            return true
        }
        return false
    }

    // Base/RwLock.h:45-54. Reject WRITE_LOCKED; otherwise retry count -> count + 1,
    // explicitly reloading count after each failed strong CAS.
    public mut func TryLockRead(): Bool {
        let p = unsafe { CPointer<Int32>(inout this.lockCount) }
        var count = unsafe { cj_atomic_i32_load(p) }
        var acquired = false
        do {
            if (count == WRITE_LOCKED) {
                return false
            }
            acquired = unsafe { cj_atomic_i32_cas(p, count, count + 1) != 0 }
            if (!acquired) {
                count = unsafe { cj_atomic_i32_load(p) }
            }
        } while (!acquired)
        return true
    }

    // Base/RwLock.h:56-62. fetch_sub returns the pre-decrement count; a negative
    // prior state is fatal, matching the C++ std::abort() branch.
    public mut func UnlockRead(): Unit {
        let p = unsafe { CPointer<Int32>(inout this.lockCount) }
        let count = unsafe { cj_atomic_i32_fetch_sub(p, 1) }
        if (count < 0) {
            unsafe { abort() }
        }
    }

    // Base/RwLock.h:64-68 and Base/Log.h:270-275. Diagnose and abort before the
    // release store on failure; only the successful check releases the lock.
    public mut func UnlockWrite(): Unit {
        let p = unsafe { CPointer<Int32>(inout this.lockCount) }
        if (unsafe { cj_atomic_i32_load(p) != WRITE_LOCKED }) {
            unsafe { RtFatal(CString(CPointer<UInt8>(inout rwLockWriteCheckMessage))) }
        } else {
            unsafe { cj_atomic_i32_store(p, 0) }
        }
    }
}
