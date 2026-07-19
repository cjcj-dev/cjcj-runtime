// Test-only executable entry. The rooted AS0 owner operation is defined in
// thread_semaphore_noheap_roots.cj and mirrors thread.h:52-80/cjthread.h:160-168.
foreign func CJRT_ThreadOwnerRun(): Int32

main(): Int64 {
    return Int64(unsafe { CJRT_ThreadOwnerRun() })
}
