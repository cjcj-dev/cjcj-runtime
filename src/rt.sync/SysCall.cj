package rt.sync

foreign {
    func _ZN12MapleRuntime5FutexEPVKiii(uaddr: CPointer<Int32>, op: Int32, val: Int32): Int32

    @When[os == "Linux" || env == "ohos"]
    func prctl(option: Int32, ...): Int32

    @When[os == "macOS" || os == "iOS"]
    func strcmp(left: CString, right: CString): Int32
}

// cangjie_runtime/runtime/src/Base/SysCall.h:31-34
@When[os == "Linux" || env == "ohos"]
public const PR_SET_VMA: Int32 = 0x53564d41
@When[os == "Linux" || env == "ohos"]
public const PR_SET_VMA_ANON_NAME: Int32 = 0

// cangjie_runtime/runtime/src/Base/SysCall.cpp:25-31
@When[os == "Linux" || env == "ohos"]
@NoHeapAlloc
func Futex(uaddr: CPointer<Int32>, op: Int32, val: Int32): Int32 {
    return unsafe { _ZN12MapleRuntime5FutexEPVKiii(uaddr, op, val) }
}

// cangjie_runtime/runtime/src/Base/SysCall.h:36-40
@When[os == "Linux" || env == "ohos"]
public func MRT_PRCTL(baseAddress: CPointer<Unit>, allocatedSize: UIntNative, mmtag: CString): Unit {
    unsafe {
        let _ = prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, baseAddress, allocatedSize, mmtag)
    }
}

// cangjie_runtime/runtime/src/Base/SysCall.h:44-47.
@When[os == "macOS" || os == "iOS"]
public const CANGJIE_HEAP_VM_TAG: Int32 = 246

// cangjie_runtime/runtime/src/Base/SysCall.h:49-52.
@When[os == "macOS" || os == "iOS"]
public func IsCangjieHeapTag(tag: CString): Bool {
    if (CPointer<UInt8>(tag).isNull()) {
        return false
    }
    var cangjieHeap: VArray<UInt8, $13> = [
        99u8, 97u8, 110u8, 103u8, 106u8, 105u8, 101u8,
        95u8, 104u8, 101u8, 97u8, 112u8, 0u8
    ]
    return unsafe { strcmp(tag, CString(CPointer<UInt8>(inout cangjieHeap))) } == 0
}

// cangjie_runtime/runtime/src/Base/SysCall.h:54-61. Darwin VM_MAKE_TAG(tag)
// expands to tag << 24 in <mach/vm_statistics.h>.
@When[os == "macOS" || os == "iOS"]
public func MrtAppleMmapFd(fd: Int32, tag: CString): Int32 {
    if (IsCangjieHeapTag(tag)) {
        return CANGJIE_HEAP_VM_TAG << 24
    }
    return fd
}
