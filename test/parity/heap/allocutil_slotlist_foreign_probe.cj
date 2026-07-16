package rt.heap.allocator

foreign {
    func RtFatal(message: CString): Unit

    @When[os != "Windows"]
    func munmap(address: CPointer<Unit>, size: UIntNative): Int32

    @When[os == "Windows"]
    func VirtualFree(address: CPointer<Unit>, size: UIntNative, freeType: UInt32): Int32
}
