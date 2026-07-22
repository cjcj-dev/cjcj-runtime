package rt.exception

foreign {
    // CompilerCalls.h:48,161. EH matching consumes the existing ObjectModel C ABI;
    // the implementation stays in RT-A and no RT-A source is duplicated here.
    func MCC_GetObjClass(object: CPointer<Unit>): CPointer<Unit>
    func CJ_MCC_IsSubType(typeInfo: CPointer<Unit>, superTypeInfo: CPointer<Unit>): Bool
    func RtFatal(message: CString): Unit
}

private var unsupportedTTypeMessage: VArray<UInt8, $28> = [
    85u8, 110u8, 115u8, 117u8, 112u8, 112u8, 111u8, 114u8, 116u8, 101u8, 100u8, 32u8, 116u8, 116u8,
    121u8, 112u8, 101u8, 32u8, 101u8, 110u8, 99u8, 111u8, 100u8, 105u8, 110u8, 103u8, 33u8, 0u8
]

@When[debug]
@NoHeapAlloc
private func CheckTTypeEncoding(flag: UInt8): Unit {
    if (flag != UInt8(ABS_PTR) && flag != UInt8(U_DATA_4) &&
        flag != UInt8(INDIR_PC_REL_S_DATA_4) && flag != UInt8(INDIR_PC_REL_S_DATA_8)) {
        unsafe { RtFatal(CString(CPointer<UInt8>(inout unsupportedTTypeMessage))) }
    }
}

@When[!debug]
@NoHeapAlloc
private func CheckTTypeEncoding(flag: UInt8): Unit { let _ = flag }

// Exception/EhTable.h:41-100. This is the five-pointer LSDA view owned by the
// C++ EHTable. It deliberately does not own unwind frames or exception storage.
@C
public struct EHTable {
    var callSiteTableStart: CPointer<UInt8>
    var callSiteTableEnd: CPointer<UInt8>
    var actionTableStart: CPointer<UInt8>
    var ttypeEncoding: CPointer<UInt8>
    var exceptionTypeStart: CPointer<UInt8>

    // Exception/EhTable.cpp:92-119. The two ignored encoding bytes and both
    // ULEB cursor transitions are retained exactly.
    @NoHeapAlloc
    public init(lsda: CPointer<UInt8>) {
        var curPtr = lsda
        let lpStartEncoding = unsafe { curPtr.read() }
        curPtr = unsafe { curPtr + 1 }
        ttypeEncoding = curPtr
        let typeEncoding = unsafe { curPtr.read() }
        curPtr = unsafe { curPtr + 1 }
        CheckTTypeEncoding(typeEncoding)
        let classInfoOffset = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout curPtr) })
        exceptionTypeStart = unsafe { curPtr + Int64(classInfoOffset) }
        let callSiteEncoding = unsafe { curPtr.read() }
        curPtr = unsafe { curPtr + 1 }
        let _ = lpStartEncoding
        let _ = callSiteEncoding
        let callSiteTableLength = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout curPtr) })
        callSiteTableStart = curPtr
        callSiteTableEnd = unsafe { curPtr + Int64(callSiteTableLength) }
        actionTableStart = callSiteTableEnd
    }

    // Exception/EhTable.cpp:165-216. Action offsets intentionally inherit the
    // published ReadSLEB128 cursor quirk before applying the signed displacement.
    @NoHeapAlloc
    public func MatchActionTable(actionEntryIdx: UInt64, exceptionRef: CPointer<Unit>, flag: UInt8): UInt8 {
        var actionPtr = unsafe { actionTableStart + Int64(actionEntryIdx - 1u64) }
        while (true) {
            let typeIndex = UInt64(unsafe { actionPtr.read() })
            actionPtr = unsafe { actionPtr + 1 }
            if (typeIndex > 0u64) {
                var catchType = CPointer<Unit>()
                if (flag == UInt8(ABS_PTR)) {
                    catchType = ReadAbsPtr(unsafe { exceptionTypeStart - Int64(typeIndex * UInt64(sizeOf<UIntNative>())) })
                } else if (flag == UInt8(U_DATA_4)) {
                    catchType = ReadUData4(unsafe { exceptionTypeStart - Int64(typeIndex * 4u64) })
                } else if (flag == UInt8(INDIR_PC_REL_S_DATA_4)) {
                    catchType = ReadIndirPcRelSData4(unsafe { exceptionTypeStart - Int64(typeIndex * 4u64) })
                } else if (flag == UInt8(INDIR_PC_REL_S_DATA_8)) {
                    catchType = ReadIndirPcRelSData8(unsafe { exceptionTypeStart - Int64(typeIndex * 8u64) })
                } else {
                    unsafe { RtFatal(CString(CPointer<UInt8>(inout unsupportedTTypeMessage))) }
                }
                if (catchType.isNull() || unsafe {
                    CJ_MCC_IsSubType(MCC_GetObjClass(exceptionRef), catchType)
                }) {
                    return UInt8(typeIndex)
                }
            }
            if (unsafe { actionPtr.read() } == 0u8) {
                return 0u8
            }
            let offset = ReadSLEB128(unsafe { CPointer<CPointer<UInt8>>(inout actionPtr) })
            actionPtr = unsafe { actionPtr + offset }
        }
        return 0u8
    }

    // Exception/EhTable.cpp:121-160. ExceptionWrapper::GetExceptionRef() is
    // projected as the already-extracted ref while that RT-D-coupled owner remains native.
    @NoHeapAlloc
    public func ScanEHTable(pc: CPointer<UInt32>, exceptionRef: CPointer<Unit>, startIp: CPointer<UInt32>,
        result: CPointer<ScanResult>): Unit {
        let ip = pc.toUIntNative() - 1
        let funcstart = startIp.toUIntNative()
        let ipOffset = UInt64(ip - funcstart)
        var curPtr = callSiteTableStart
        while (curPtr.toUIntNative() < callSiteTableEnd.toUIntNative()) {
            let start = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout curPtr) })
            let length = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout curPtr) })
            var landingPad = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout curPtr) })
            let actionEntry = ReadULEB128(unsafe { CPointer<CPointer<UInt8>>(inout curPtr) })
            if (start <= ipOffset && ipOffset < start + length) {
                if (landingPad == 0u64) { continue }
                landingPad = UInt64(startIp.toUIntNative()) + landingPad
                if (actionEntry == 0u64) {
                    unsafe { CPointer<UInt64>(CPointer<UInt8>(result) + 8).write(landingPad) }
                    return
                }
                let exceptionTypeIndex = MatchActionTable(actionEntry, exceptionRef, unsafe { ttypeEncoding.read() })
                if (exceptionTypeIndex > 0u8) {
                    unsafe {
                        CPointer<UInt64>(result).write(UInt64(exceptionTypeIndex))
                        CPointer<UInt64>(CPointer<UInt8>(result) + 8).write(landingPad)
                        CPointer<Bool>(CPointer<UInt8>(result) + 16).write(true)
                    }
                    return
                }
            }
        }
    }
}
