package rt.demangle

// Cangjie.h: char* CJ_MRT_DemangleHandle(const char* functionName).
// The returned buffer is allocated by libc malloc and is owned by the caller.
@C
public func CJRT_Demangle(functionName: CPointer<UInt8>): CPointer<UInt8> {
    let arena = RtArenaCreate()
    if (arena.isNull()) {
        return CPointer<UInt8>()
    }

    var mangled = RtFromCString(functionName, arena)
    let withoutTypeInfo = RtLit(242)
    if (mangled.EndsWith(withoutTypeInfo)) {
        mangled = mangled.SubStr(0, mangled.size - withoutTypeInfo.size)
    }

    var demangler = Demangler(mangled)
    let info = demangler.Demangle()
    let methodName = info.GetFullName(demangler.ScopeResolution())
    let packageName = info.GetPkgName()
    let demangled = if (packageName.isEmpty()) {
        methodName
    } else {
        packageName + RtLit(22) + methodName
    }
    let result = RtToCString(demangled)
    RtArenaDestroy(arena)
    return result
}
