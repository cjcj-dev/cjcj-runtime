package rt.cstring

import rt.base.{LOG, RTLOG_FATAL}

foreign {
    func malloc(size: UIntNative): CPointer<Unit>
    func free(address: CPointer<Unit>): Unit
    func strlen(str: CPointer<UInt8>): UIntNative
    func memcpy_s(dest: CPointer<UInt8>, destMax: UIntNative,
        src: CPointer<UInt8>, count: UIntNative): Int32
}

// Base/CString.h:19-149; reachable subset selected from
// Heap/Allocator/RegionManager.cpp:245-256 -> Base/LogFile.cpp:133-195,271-305.
public class CString {
    private static const C_STRING_MIN_SIZE: UIntNative = 16

    private var str: CPointer<UInt8> = CPointer<UInt8>()
    private var capacity: UIntNative = C_STRING_MIN_SIZE
    private var length: UIntNative = 0

    // Base/CString.cpp:27-42, CString::CString(const char*).
    public init(initStr: CPointer<UInt8>) {
        if (!initStr.isNull()) {
            let initLen = unsafe { strlen(initStr) }
            while (capacity < initLen + 1) {
                capacity <<= 1
            }
            str = unsafe { CPointer<UInt8>(malloc(capacity)) }
            if (str.isNull()) {
                LOG(RTLOG_FATAL, "CString::Init failed")
            }
            if (unsafe { initStr.read(0) } != 0u8 &&
                unsafe { memcpy_s(str, capacity, initStr, initLen) } != 0) {
                LOG(RTLOG_FATAL, "CString::CString memcpy_s failed")
            }
            length = initLen
            unsafe { str.write(Int64(length), 0u8) }
        }
    }

    // Base/CString.cpp:159-165, CString::~CString().
    ~init() {
        if (!str.isNull()) {
            unsafe { free(CPointer<Unit>(str)) }
            str = CPointer<UInt8>()
        }
    }

    // Base/CString.cpp:240, CString::Length().
    public func Length(): UIntNative {
        return length
    }

    // Base/CString.cpp:242, CString::Str().
    public func Str(): CPointer<UInt8> {
        return str
    }

    // Base/CString.cpp:301-316, CString::RemoveBlankSpace().
    public func RemoveBlankSpace(): CString {
        var index: UIntNative = 0
        let noBlankSpaceStr = CString(Str())
        if (length == 0) {
            return noBlankSpaceStr
        }
        var i: UIntNative = 0
        while (i < length) {
            let current = unsafe { str.read(Int64(i)) }
            if (current != b' ') {
                unsafe { noBlankSpaceStr.str.write(Int64(index), current) }
                index++
            }
            i++
        }
        unsafe { noBlankSpaceStr.str.write(Int64(index), 0u8) }
        noBlankSpaceStr.length = index
        return noBlankSpaceStr
    }

    // FEATURE_DEBT(CSTRING_SPLIT_VECTOR): std::vector<CString> has no approved C ABI container mapping.
    // FEATURE_DEBT(CSTRING_VARIADIC_FORMAT): Cangjie cannot define a variadic function body owning va_list.
}
