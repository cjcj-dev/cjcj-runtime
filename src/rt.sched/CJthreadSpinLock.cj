// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.sched

foreign {
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_pthread_spin_init(lock: CPointer<Int32>): Int32
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_pthread_spin_lock(lock: CPointer<Int32>): Int32
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_pthread_spin_unlock(lock: CPointer<Int32>): Int32
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_pthread_spin_destroy(lock: CPointer<Int32>): Int32
}

// CJThread schedule/include/inner/base.h:140-142. The Linux x86_64 oracle proves
// pthread_spinlock_t is the inline 4-byte/alignment-4 field at offset zero.
// LANG-BOUNDARY: Cangjie requires an initial field value before the source-defined
// PthreadSpinInit call establishes the live pthread object.
@When[os == "Linux" && arch == "x86_64"]
@C
public struct CJthreadSpinLock {
    public var lock: Int32

    public init() {
        lock = 0
    }
}

// CJThread schedule/include/inner/base.h:144-147. Exactly one process-private
// pthread_spin_init call on the original inline field; return its native code.
@When[os == "Linux" && arch == "x86_64"]
public func PthreadSpinInit(lock: CPointer<CJthreadSpinLock>): Int32 {
    return unsafe { cj_cjthread_pthread_spin_init(CPointer<Int32>(lock)) }
}

// CJThread schedule/include/inner/base.h:149-152. Exactly one blocking call on
// the original inline field; return its native code.
@When[os == "Linux" && arch == "x86_64"]
public func PthreadSpinLock(lock: CPointer<CJthreadSpinLock>): Int32 {
    return unsafe { cj_cjthread_pthread_spin_lock(CPointer<Int32>(lock)) }
}

// CJThread schedule/include/inner/base.h:154-157. Exactly one unlock call on
// the original inline field; return its native code.
@When[os == "Linux" && arch == "x86_64"]
public func PthreadSpinUnlock(lock: CPointer<CJthreadSpinLock>): Int32 {
    return unsafe { cj_cjthread_pthread_spin_unlock(CPointer<Int32>(lock)) }
}

// CJThread schedule/include/inner/base.h:159-162. This is a normal explicit
// source function: call exactly once when requested and return the native code.
@When[os == "Linux" && arch == "x86_64"]
public func PthreadSpinDestroy(lock: CPointer<CJthreadSpinLock>): Int32 {
    return unsafe { cj_cjthread_pthread_spin_destroy(CPointer<Int32>(lock)) }
}

// CJTHREAD-SPINLOCK-PLATFORM-LAYOUT: base.h:55-77 selects pthread_mutex_t for
// MRT_MACOS (macOS/iOS); its exact inline layout is not established on this host.
// CJTHREAD-SPINLOCK-PLATFORM-LAYOUT: base.h:115-138 selects pthread_mutex_t only
// for __ANDROID__ && VOS_WORDSIZE == 32 && MRT_HARDWARE_PLATFORM == MRT_ARM.
// CJTHREAD-SPINLOCK-PLATFORM-LAYOUT: base.h:139-164 selects pthread_spinlock_t
// for every other non-Mac target; only Linux x86_64 is layout-proved here.
