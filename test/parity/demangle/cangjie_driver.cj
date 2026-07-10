package rt.demangle.parity

foreign func CJRT_DemangleParityNext(): CPointer<UInt8>
foreign func CJRT_DemangleParityEmit(input: CPointer<UInt8>, output: CPointer<UInt8>): Unit
foreign func CJ_MRT_DemangleHandle(input: CPointer<UInt8>): CPointer<UInt8>
foreign func free(pointer: CPointer<Unit>): Unit

main(): Int64 {
    var input = unsafe { CJRT_DemangleParityNext() }
    while (!input.isNull()) {
        let output = unsafe { CJ_MRT_DemangleHandle(input) }
        if (output.isNull()) {
            return 2
        }
        unsafe {
            CJRT_DemangleParityEmit(input, output)
            free(CPointer<Unit>(output))
        }
        input = unsafe { CJRT_DemangleParityNext() }
    }
    return 0
}
