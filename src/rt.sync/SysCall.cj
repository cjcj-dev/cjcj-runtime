package rt.sync

foreign {
    func _ZN12MapleRuntime5FutexEPVKiii(uaddr: CPointer<Int32>, op: Int32, val: Int32): Int32
}

// cangjie_runtime/runtime/src/Base/SysCall.cpp:25-31
@When[os == "Linux"]
@NoHeapAlloc
func Futex(uaddr: CPointer<Int32>, op: Int32, val: Int32): Int32 {
    return unsafe { _ZN12MapleRuntime5FutexEPVKiii(uaddr, op, val) }
}
