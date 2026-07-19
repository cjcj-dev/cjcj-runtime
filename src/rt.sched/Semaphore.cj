// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.sched

foreign {
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_semaphore_init(sem: CPointer<UInt64>, pshared: Int32, value: UInt32): Int32
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_semaphore_wait(sem: CPointer<UInt64>): Int32
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_semaphore_wait_no_intr(sem: CPointer<UInt64>): Int32
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_semaphore_post(sem: CPointer<UInt64>): Int32
    @When[os == "Linux" && arch == "x86_64"]
    func cj_cjthread_semaphore_destroy(sem: CPointer<UInt64>): Int32
}

// CJThread schedule/include/inner/base.h:82-84. The Linux x86_64 oracle proves
// sem_t is caller-owned inline storage with size 32, alignment 8, and offset zero.
// LANG-BOUNDARY: Cangjie requires initialized field bytes before SemaphoreInit
// establishes the live native semaphore.
@When[os == "Linux" && arch == "x86_64"]
@C
public struct Semaphore {
    public var sem: VArray<UInt64, $4>

    public init() {
        sem = VArray<UInt64, $4>(repeat: 0u64)
    }
}

// CJThread schedule/include/inner/base.h:86-89. Preserve both caller arguments,
// use the original inline storage address, and return the native result.
@When[os == "Linux" && arch == "x86_64"]
public func SemaphoreInit(sem: CPointer<Semaphore>, pshared: Int32, value: UInt32): Int32 {
    return unsafe { cj_cjthread_semaphore_init(CPointer<UInt64>(sem), pshared, value) }
}

// CJThread schedule/include/inner/base.h:91-94.
@When[os == "Linux" && arch == "x86_64"]
public func SemaphoreWait(sem: CPointer<Semaphore>): Int32 {
    return unsafe { cj_cjthread_semaphore_wait(CPointer<UInt64>(sem)) }
}

// CJThread schedule/include/inner/base.h:96-103. The Layer0 leaf preserves the
// exact errno-coupled do/while because errno is native thread-local state.
@When[os == "Linux" && arch == "x86_64"]
public func SemaphoreWaitNoIntr(sem: CPointer<Semaphore>): Int32 {
    return unsafe { cj_cjthread_semaphore_wait_no_intr(CPointer<UInt64>(sem)) }
}

// CJThread schedule/include/inner/base.h:105-108.
@When[os == "Linux" && arch == "x86_64"]
public func SemaphorePost(sem: CPointer<Semaphore>): Int32 {
    return unsafe { cj_cjthread_semaphore_post(CPointer<UInt64>(sem)) }
}

// CJThread schedule/include/inner/base.h:110-113.
@When[os == "Linux" && arch == "x86_64"]
public func SemaphoreDestroy(sem: CPointer<Semaphore>): Int32 {
    return unsafe { cj_cjthread_semaphore_destroy(CPointer<UInt64>(sem)) }
}

// CJTHREAD-SEMAPHORE-DARWIN-LAYOUT: base.h:10-53 selects an inline
// dispatch_semaphore_t on MRT_MACOS. This Linux host cannot prove the Darwin
// pointer layout or dispatch ABI, so no dispatch type is guessed and no POSIX
// representation stands in for macOS/iOS.
// CJTHREAD-SEMAPHORE-INLINE-LAYOUT: base.h:79-113 selects sem_t for every
// non-Mac target. Only Linux x86_64 is layout-compiled and executed here;
// aarch64 Linux, Android, Win64, OHOS, and other targets remain uncompiled.
