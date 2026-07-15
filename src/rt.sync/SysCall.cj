package rt.sync

foreign {
    func _ZN12MapleRuntime5FutexEPVKiii(uaddr: CPointer<Int32>, op: Int32, val: Int32): Int32

    @When[os == "Linux"]
    func prctl(option: Int32, ...): Int32
}

// cangjie_runtime/runtime/src/Base/SysCall.h:31-34
@When[os == "Linux"]
public const PR_SET_VMA: Int32 = 0x53564d41
@When[os == "Linux"]
public const PR_SET_VMA_ANON_NAME: Int32 = 0

// cangjie_runtime/runtime/src/Base/SysCall.cpp:25-31
@When[os == "Linux"]
@NoHeapAlloc
func Futex(uaddr: CPointer<Int32>, op: Int32, val: Int32): Int32 {
    return unsafe { _ZN12MapleRuntime5FutexEPVKiii(uaddr, op, val) }
}

// cangjie_runtime/runtime/src/Base/SysCall.h:36-40
@When[os == "Linux"]
public func MRT_PRCTL(baseAddress: CPointer<Unit>, allocatedSize: UIntNative, mmtag: CString): Unit {
    unsafe {
        let _ = prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, baseAddress, allocatedSize, mmtag)
    }
}
