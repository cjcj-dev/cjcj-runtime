// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package rt.sched

// CJThread schedule/include/schedule.h:262-292. C and C++ expose these handles
// and callbacks as opaque native data/function pointers. Cangjie closures are
// not ABI-compatible with those function pointers.
public type ScheduleHandle = CPointer<Unit>
public type CJThreadHandle = CPointer<Unit>
public type CJThreadFunc = CPointer<Unit>
public type LuaCJThreadFunc = CPointer<Unit>
public type CJThreadKey = UInt32
public type DestructorFunc = CPointer<Unit>
public type ParkCallbackFunc = CPointer<Unit>

// CJThread schedule/include/schedule.h:383-393.
public const ATTR_MAX_SIZE: UIntNative = 128

@C
public struct CJThreadAttr {
    public var attr: VArray<UInt8, $128>

    public init() {
        attr = VArray<UInt8, $128>(repeat: 0u8)
    }
}

// CJThread util/list/include/list.h:22-28. This descriptor does not port any
// Dulink operation from list.h:30 onward.
@C
public struct Dulink {
    public var prev: CPointer<Dulink>
    public var next: CPointer<Dulink>

    public init() {
        prev = CPointer<Dulink>()
        next = CPointer<Dulink>()
    }
}

// CJThread schedule/include/inner/thread.h:40-46. The Linux x86_64 oracle
// proves std::atomic<ThreadState> has the same 4-byte size, 4-byte alignment,
// and value bytes as Int32 for all five enumerators. This descriptor adds no
// state load/store/CAS operation and no managed Atomic owner.
public type ThreadState = Int32
public const THREAD_INIT: ThreadState = 0
public const THREAD_CLOSE: ThreadState = 1
public const THREAD_RUNNING: ThreadState = 2
public const THREAD_PRE_SLEEP: ThreadState = 3
public const THREAD_SLEEP: ThreadState = 4

// CJThread schedule/include/schedule.h:403-410. The target enum has no #if
// branches. The Linux x86_64 oracle proves a 4-byte unsigned representation.
public type CJThreadCreateSource = UInt32
public const CJTHREAD_CREATE_SOURCE_DEFAULT: CJThreadCreateSource = 0u32
public const CJTHREAD_CREATE_SOURCE_SIGNAL: CJThreadCreateSource = 1u32
public const CJTHREAD_CREATE_SOURCE_FINALIZER: CJThreadCreateSource = 2u32

// CJThread schedule/include/schedule.h:415-420. The target enum has no #if
// branches. LuaCJThread stores this vocabulary in its signed int state field.
public type LuaCJThreadState = Int32
public const LUA_CJTHREAD_INIT: LuaCJThreadState = 0
public const LUA_CJTHREAD_SUSPENDING: LuaCJThreadState = 1
public const LUA_CJTHREAD_RUNNING: LuaCJThreadState = 2
public const LUA_CJTHREAD_DONE: LuaCJThreadState = 3

// CJThread schedule/include/schedule.h:423-430. The Linux x86_64 C++ oracle
// proves the public vocabulary has a 4-byte unsigned representation and values 0-3.
public type ScheduleType = UInt32
public const SCHEDULE_DEFAULT: ScheduleType = 0u32
public const SCHEDULE_UI_THREAD: ScheduleType = 1u32
public const SCHEDULE_FOREIGN_THREAD: ScheduleType = 2u32
public const SCHEDULE_EXCLUSIVE: ScheduleType = 3u32

// CJThread schedule/include/inner/gas/x86/x86_64/cjthread_context.h:17-42.
// The selected Linux x86_64 record ends after fpuCw; the compiler supplies the
// two tail-padding bytes required by its 8-byte aggregate alignment.
@When[os == "Linux" && arch == "x86_64"]
@C
public struct CJThreadContext {
    public var rsp: UInt64
    public var rbp: UInt64
    public var rbx: UInt64
    public var rip: UInt64
    public var r12: UInt64
    public var r13: UInt64
    public var r14: UInt64
    public var r15: UInt64
    public var mxcsr: UInt32
    public var fpuCw: UInt16

    public init() {
        rsp = 0u64
        rbp = 0u64
        rbx = 0u64
        rip = 0u64
        r12 = 0u64
        r13 = 0u64
        r14 = 0u64
        r15 = 0u64
        mxcsr = 0u32
        fpuCw = 0u16
    }
}

// CJThread schedule/include/inner/thread.h:52-80. Every field is inline and in
// source order. In particular cjthread/cjthread0 retain the assembly-sensitive
// offsets 16/24 and sem is the accepted inline Semaphore at offset 72.
@When[os == "Linux" && arch == "x86_64"]
@C
public struct Thread {
    public var link2schd: Dulink
    public var cjthread: CPointer<Unit>
    public var cjthread0: CPointer<Unit>
    public var preemptFlag: CPointer<UIntNative>
    public var preemptRequest: CPointer<UIntNative>
    public var state: ThreadState
    public var processor: CPointer<Unit>
    public var oldProcessor: CPointer<Unit>
    public var sem: Semaphore
    public var tid: Int32
    public var osThread: UInt64
    public var context: CJThreadContext
    public var isSearching: Bool
    public var boundCJThread: CPointer<Unit>
    public var nextProcessor: CPointer<Unit>
    public var allThreadDulink: Dulink

    public init() {
        link2schd = Dulink()
        cjthread = CPointer<Unit>()
        cjthread0 = CPointer<Unit>()
        preemptFlag = CPointer<UIntNative>()
        preemptRequest = CPointer<UIntNative>()
        state = THREAD_INIT
        processor = CPointer<Unit>()
        oldProcessor = CPointer<Unit>()
        sem = Semaphore()
        tid = 0
        osThread = 0u64
        context = CJThreadContext()
        isSearching = false
        boundCJThread = CPointer<Unit>()
        nextProcessor = CPointer<Unit>()
        allThreadDulink = Dulink()
    }
}

// CJThread schedule/include/inner/cjthread.h:157-168. LuaCJThread is the exact
// seven-field lua2cj descriptor; no CJThread allocation or lifecycle API is
// part of this surface.
@When[os == "Linux" && arch == "x86_64"]
@C
public struct LuaCJThread {
    public var cjthread: CJThreadHandle
    public var `func`: LuaCJThreadFunc
    public var arg: CPointer<Unit>
    public var result: CPointer<Unit>
    public var sem: Semaphore
    public var state: LuaCJThreadState
    public var attrUser: CJThreadAttr

    public init() {
        cjthread = CPointer<Unit>()
        `func` = CPointer<Unit>()
        arg = CPointer<Unit>()
        result = CPointer<Unit>()
        sem = Semaphore()
        state = LUA_CJTHREAD_INIT
        attrUser = CJThreadAttr()
    }
}

// CJTHREAD-CONTEXT-PLATFORM-LAYOUT: cjthread_context.h:23-27,43-59 adds the
// Win64 frame rule and rdi/rsi/XMM6-XMM15/GS fields; gas/arm/arm32 and arm64
// define different records. macOS/iOS, aarch64 Linux, Android ARM32/ARM64,
// Win64, OHOS, and other targets remain explicit descriptor debts.
// THREAD-DESCRIPTOR-LAYOUT: thread.h:68-72 selects unsigned long long tid on
// macOS and pid_t elsewhere. No Linux pid_t/pthread_t/context projection is
// enabled for another target.
// CJTHREAD-SEMAPHORE-DARWIN-LAYOUT and CJTHREAD-SEMAPHORE-INLINE-LAYOUT remain
// the accepted Semaphore debts recorded in Semaphore.cj:68-74.
// LUA-CJTHREAD-ABI: cjthread.h:152-154 adds an OHOS-only vector to the enclosing
// CJThread (outside LuaCJThread); it must be resolved before that full owner is
// attempted and is not represented by this descriptor prerequisite.
