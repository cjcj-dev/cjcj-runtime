// Mechanically derived from selfhost packages/mangle/src/Demangler.cj; semantic oracle remains runtime/src/Demangler.
package rt.demangle

// C++ source mapping:
// - demangler/Demangler.h and demangler/Demangler.cpp define template Demangler<T> and DemangleInfo<T>.
// - demangler/StdString.h adapts std::string to the CString-like API.
// In selfhost packages/mangle the only string carrier is Cangjie RtString, so the C++ template-over-string-type is
// collapsed once here: every C++ T/StdString/CString operation maps to RtString indexing, slicing, and concatenation.

// These accessors must remain pure value construction.  Package initializers
// do not run before runtime entry points are callable in a hybrid image.
private func ARGS_DELIMITER(): RtString { return RtLit(19) }
private func ARGS_DELIMITER_TYPE(): RtString { return RtLit(18) }
private func LEFT_BRACKET(): RtString { return RtLit(12) }
private func RIGHT_BRACKET(): RtString { return RtLit(14) }
private func MODULE_SPLIT(): RtString { return RtLit(24) }
private func MANGLE_MODULE_SPLIT(): RtString { return RtLit(6) }
private func MANGLE_FUNCTY_PREFIX(): RtString { return RtLit(47) }
private func MANGLE_C_FUNCTY_PREFIX(): RtString { return RtLit(48) }
private func MANGLE_FLOAT16_PREFIX(): RtString { return RtLit(46) }
private func MANGLE_SET_PREFIX(): RtString { return RtLit(171) }
private func MANGLE_GET_PREFIX(): RtString { return RtLit(168) }
private func GLOBAL_VARIABLE_INIT_PREFIX(): RtString { return RtLit(54) }
private func MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER(): RtString { return RtLit(78) }
private func MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER(): RtString { return RtLit(77) }
private func MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER(): RtString { return RtLit(79) }
private func MANGLE_GLOBAL_INIT_SUFFIX(): RtString { return RtLit(156) }
private func MANGLE_GLOBAL_INIT_RESET_SUFFIX(): RtString { return RtLit(162) }
private func MANGLE_GLOBAL_INIT_FLAG_RESET_SUFFIX(): RtString { return RtLit(155) }
private func MANGLE_GLOBAL_INIT_LITERAL_RESET_SUFFIX(): RtString { return RtLit(157) }
private func MANGLE_GLOBAL_INIT_IMPORTS_INIT(): RtString { return RtLit(152) }
private func MANGLE_GLOBAL_LITERAL_IMPORTS_INIT(): RtString { return RtLit(153) }
private func MANGLE_INNER_FUNCTION_PREFIX(): RtString { return RtLit(8) }
private func MANGLE_CFUNCTION_WRAPPER(): RtString { return RtLit(9) }
private func MANGLE_WRAPPED_FUNCTION_PREFIX(): RtString { return RtLit(80) }
private func BOX_DECL_PREFIX(): RtString { return RtLit(7) }
private func CJ_FILE_EXT(): RtString { return RtLit(23) }
private func ERROR_EXCEED_THE_INPUT_STRING_LENGTH(): RtString { return RtLit(151) }
private func MANGLE_TUPLE_STR(): RtString { return RtLit(65) }
private func MANGLE_ARRAY_STR(): RtString { return RtLit(62) }
private func MANGLE_VARRAY_STR(): RtString { return RtLit(72) }
private func MANGLE_PTR_STR(): RtString { return RtLit(43) }
private func MANGLE_CSTRING_STR(): RtString { return RtLit(44) }
private func BASE62_CHARS(): RtString { return RtLit(27) }
private func DECIMAL_CHARS(): RtString { return RtLit(26) }
private func WRAPPED_FUNCTION_SUFFIX_INFO(): RtString { return RtLit(37) }
private func MANGLE_CANGJIE_PREFIX(): RtString { return RtLit(240) }
private func MANGLE_NESTED_PREFIX(): RtString { return RtLit(241) }
private func MANGLE_DOLLAR_PREFIX(): RtString { return RtLit(6) }
private func MANGLE_WILDCARD_PREFIX(): RtString { return RtLit(76) }
private let BASE62_CHARS_SIZE: Int64 = 62
private let MAX_ARGS_SIZE: Int64 = 16
private let UINT32_MAX_AS_INT64: Int64 = 4294967295
private let MANGLE_CHAR_LEN: Int64 = 1
private let MANGLE_SPECIAL_NAME_LEN: Int64 = 2
private let FILE_HASH_LEN: Int64 = 13

enum DemanglerTypeKind {
    | NAME
    | PRIMITIVE
    | CSTRING
    | CLASS
    | STRUCT
    | INTERFACE
    | ENUM
    | RAW_ARRAY
    | VARRAY
    | TUPLE
    | CPOINTER
    | FUNCTION
    | COMMON_DECL
    | FUNCTION_DECL
    | FUNCTION_PARAMETER_TYPES
    | LAMBDA_FUNCTION
    | GENERIC_TYPES
    | GENERIC_CONSTRAINTS
    | WRAPPED_FUNCTION
}

extend DemanglerTypeKind <: Equatable<DemanglerTypeKind> {
    public operator func ==(right: DemanglerTypeKind): Bool {
        return match (this) {
            case DemanglerTypeKind.NAME => match (right) { case DemanglerTypeKind.NAME => true case _ => false }
            case DemanglerTypeKind.PRIMITIVE => match (right) { case DemanglerTypeKind.PRIMITIVE => true case _ => false }
            case DemanglerTypeKind.CSTRING => match (right) { case DemanglerTypeKind.CSTRING => true case _ => false }
            case DemanglerTypeKind.CLASS => match (right) { case DemanglerTypeKind.CLASS => true case _ => false }
            case DemanglerTypeKind.STRUCT => match (right) { case DemanglerTypeKind.STRUCT => true case _ => false }
            case DemanglerTypeKind.INTERFACE => match (right) { case DemanglerTypeKind.INTERFACE => true case _ => false }
            case DemanglerTypeKind.ENUM => match (right) { case DemanglerTypeKind.ENUM => true case _ => false }
            case DemanglerTypeKind.RAW_ARRAY => match (right) { case DemanglerTypeKind.RAW_ARRAY => true case _ => false }
            case DemanglerTypeKind.VARRAY => match (right) { case DemanglerTypeKind.VARRAY => true case _ => false }
            case DemanglerTypeKind.TUPLE => match (right) { case DemanglerTypeKind.TUPLE => true case _ => false }
            case DemanglerTypeKind.CPOINTER => match (right) { case DemanglerTypeKind.CPOINTER => true case _ => false }
            case DemanglerTypeKind.FUNCTION => match (right) { case DemanglerTypeKind.FUNCTION => true case _ => false }
            case DemanglerTypeKind.COMMON_DECL => match (right) { case DemanglerTypeKind.COMMON_DECL => true case _ => false }
            case DemanglerTypeKind.FUNCTION_DECL => match (right) { case DemanglerTypeKind.FUNCTION_DECL => true case _ => false }
            case DemanglerTypeKind.FUNCTION_PARAMETER_TYPES => match (right) {
                case DemanglerTypeKind.FUNCTION_PARAMETER_TYPES => true
                case _ => false
            }
            case DemanglerTypeKind.LAMBDA_FUNCTION => match (right) { case DemanglerTypeKind.LAMBDA_FUNCTION => true case _ => false }
            case DemanglerTypeKind.GENERIC_TYPES => match (right) { case DemanglerTypeKind.GENERIC_TYPES => true case _ => false }
            case DemanglerTypeKind.GENERIC_CONSTRAINTS => match (right) {
                case DemanglerTypeKind.GENERIC_CONSTRAINTS => true
                case _ => false
            }
            case DemanglerTypeKind.WRAPPED_FUNCTION => match (right) { case DemanglerTypeKind.WRAPPED_FUNCTION => true case _ => false }
        }
    }

    public operator func !=(right: DemanglerTypeKind): Bool {
        return !(this == right)
    }
}

private func GetPrimitiveDemangleMap(t: Byte): RtString {
    return match (t) {
        case b'u' => RtLit(71)
        case b'n' => RtLit(60)
        case b'b' => RtLit(42)
        case b'D' => RtLit(49)
        case b'f' => RtLit(50)
        case b'd' => RtLit(51)
        case b'c' => RtLit(63)
        case b'a' => RtLit(58)
        case b's' => RtLit(55)
        case b'i' => RtLit(56)
        case b'l' => RtLit(57)
        case b'h' => RtLit(69)
        case b't' => RtLit(66)
        case b'j' => RtLit(67)
        case b'm' => RtLit(68)
        case b'q' => RtLit(59)
        case b'r' => RtLit(70)
        case _ => RtLit(0)
    }
}

private func GetOperatorNameMap(replaced: RtString): RtString {
    let chBase: Int64 = 97
    if (!((replaced[0] >= b'a' && replaced[0] <= b'z') && (replaced[1] >= b'a' && replaced[1] <= b'z'))) {
        return RtLit(0)
    }
    let operatorIndex = ((Int64(replaced[0]) - chBase) << 5) + Int64(replaced[1]) - chBase
    return match (operatorIndex) {
        case 279 => RtLit(74)
        case 435 => RtLit(4)
        case 422 => RtLit(21)
        case 502 => RtLit(16)
        case 395 => RtLit(15)
        case 117 => RtLit(24)
        case 556 => RtLit(10)
        case 491 => RtLit(17)
        case 370 => RtLit(35)
        case 562 => RtLit(41)
        case 371 => RtLit(34)
        case 211 => RtLit(39)
        case 356 => RtLit(36)
        case 196 => RtLit(40)
        case 144 => RtLit(38)
        case 420 => RtLit(5)
        case 13 => RtLit(11)
        case 142 => RtLit(75)
        case 465 => RtLit(239)
        case 75 => RtLit(13)
        case _ => RtLit(0)
    }
}

private func ReplaceString(str: RtString, pattern: RtString, replacement: RtString): RtString {
    if (str.isEmpty()) {
        return str
    }
    var out = str
    var pos = out.Find(pattern)
    while (pos >= 0) {
        let currentLen = out.size
        if (currentLen - pos - pattern.size <= 0) {
            break
        }
        out = out.SubStr(0, pos) + replacement + out.SubStr(pos + pattern.size, currentLen - pos - pattern.size)
        pos = out.Find(pattern)
    }
    return out
}

private func IsPrimitive(ch: Byte): Bool {
    return GetPrimitiveDemangleMap(ch) != RtLit(0)
}

private func IsCurrentCharDigit(ch: Byte): Bool {
    return ch >= b'0' && ch <= b'9'
}

private func IsGeneric(ch: Byte): Bool {
    return ch == b'I'
}

private func IsFunction(ch: Byte): Bool {
    return ch == b'H'
}

struct DemangleInfo {
    var `type`: DemanglerTypeKind = DemanglerTypeKind.NAME
    var pkgName: RtString = RtLit(0)
    var args: RtString = RtLit(0)
    var genericConstraints: RtString = RtLit(0)
    var genericTypes: RtString = RtLit(0)
    var functionParameterTypes: RtString = RtLit(0)
    var demangled: RtString = RtLit(0)
    var isPrivateDeclaration: Bool = false
    private var isValid: Bool = true

    init() {}

    init(name: RtString, kind: DemanglerTypeKind) {
        this.`type` = kind
        this.demangled = name
    }

    init(name: RtString, kind: DemanglerTypeKind, pIsValid: Bool) {
        this.`type` = kind
        this.demangled = name
        this.isValid = pIsValid
    }

    private func MatchSuffix(pattern: RtString, len: Int64): Bool {
        let index = if (demangled.size > len) { demangled.size - len } else { 0 }
        let suffix = demangled.SubStr(index)
        return suffix == pattern
    }

    private func OwnerArena(): CPointer<RtArena> {
        if (!demangled.arena.isNull()) { return demangled.arena }
        if (!pkgName.arena.isNull()) { return pkgName.arena }
        if (!args.arena.isNull()) { return args.arena }
        if (!genericTypes.arena.isNull()) { return genericTypes.arena }
        if (!genericConstraints.arena.isNull()) { return genericConstraints.arena }
        return functionParameterTypes.arena
    }

    private func Punctuation(id: Int64): RtString {
        return RtLit(id).WithArena(OwnerArena())
    }

    func GetFullName(scopeRes: RtString): RtString {
        return GetFullName(scopeRes, 0)
    }

    func GetFullName(scopeRes: RtString, argsNum: Int64): RtString {
        var fullDemangledName = RtEmpty(OwnerArena())
        match (this.`type`) {
            case DemanglerTypeKind.FUNCTION => return GetFunctionName()
            case DemanglerTypeKind.GENERIC_CONSTRAINTS => return GetGenericConstraintsName()
            case _ =>
                let pkg = GetPkgName()
                let identifier = GetIdentifier()
                if (!IsFunctionLike() && this.`type` != DemanglerTypeKind.COMMON_DECL) {
                    if (!pkg.isEmpty() && !identifier.isEmpty()) {
                        fullDemangledName += pkg
                        fullDemangledName += scopeRes
                        fullDemangledName += identifier
                    } else {
                        fullDemangledName += pkg
                        fullDemangledName += identifier
                    }
                } else {
                    fullDemangledName += identifier
                }
                fullDemangledName += GetGenericTypes()
                fullDemangledName += GetArgTypesName(argsNum)
                fullDemangledName += GetGenericConstraints()
        }
        return fullDemangledName
    }

    func GetPkgName(): RtString {
        return pkgName
    }

    func GetReturnType(): RtString {
        return demangled
    }

    private func GetGenericConstraints(): RtString {
        return genericConstraints
    }

    private func GetGenericTypes(): RtString {
        return genericTypes
    }

    private func GetGenericConstraintsName(): RtString {
        let separatorFromDecl = Punctuation(19)
        var gcName = separatorFromDecl + demangled
        gcName += Punctuation(3)
        gcName += ReplaceString(args, Punctuation(18), Punctuation(1))
        return gcName
    }

    func GetArgTypesName(): RtString {
        return GetArgTypesName(0)
    }

    func GetArgTypesName(argsNum: Int64): RtString {
        if (args.isEmpty()) {
            return if (IsFunctionLike()) { Punctuation(13) } else { RtEmpty(OwnerArena()) }
        }
        if (IsFunctionLike()) {
            return Punctuation(12) + args + Punctuation(14)
        }
        if (argsNum != 0) {
            let numStr = RtIntToString(args.arena, argsNum)
            return Punctuation(34) + args + Punctuation(20) + numStr + Punctuation(39)
        }
        return Punctuation(34) + args + Punctuation(39)
    }

    func IsFunctionLike(): Bool {
        return `type` == DemanglerTypeKind.FUNCTION_DECL || `type` == DemanglerTypeKind.LAMBDA_FUNCTION ||
            `type` == DemanglerTypeKind.FUNCTION || `type` == DemanglerTypeKind.WRAPPED_FUNCTION
    }

    func IsValid(): Bool {
        return isValid
    }

    private func GetFunctionName(): RtString {
        return GetArgTypesName() + Punctuation(2) + GetReturnType()
    }

    func GetIdentifier(): RtString {
        if (!demangled.isEmpty() && demangled[0] == b'<' && EndsWith(demangled, Punctuation(39))) {
            return demangled.SubStr(1, demangled.size - 2)
        }
        return demangled
    }
}

private func GetArgTypesFullName(args: CPointer<RtString>, argSize: Int64, delimiter: RtString): RtString {
    if (argSize == 0) {
        return RtLit(0)
    }
    var argTypesFullName = RtStringSlotGet(args, 0)
    var i: Int64 = 1
    while (i < argSize) {
        argTypesFullName += delimiter + RtStringSlotGet(args, i)
        i++
    }
    return argTypesFullName
}

struct Demangler {
    private var isValid: Bool = true
    private var curType: DemanglerTypeKind = DemanglerTypeKind.NAME
    private var currentIndex: Int64 = 0
    private var mangledName: RtString
    private var scopeResolution: RtString
    private var dumpDi: DemangleInfo

    init(mangled: RtString, stripUnderscore!: Bool = false, scopeRes!: RtString = RtLit(29)) {
        this.scopeResolution = scopeRes
        this.mangledName = mangled
        if (stripUnderscore && !mangled.isEmpty() && mangled[0] == b'_') {
            this.mangledName = this.mangledName.SubStr(1)
        }
        this.dumpDi = DemangleInfo(this.mangledName, DemanglerTypeKind.NAME, false)
    }

    mut func ScopeResolution(): RtString {
        return scopeResolution
    }

    private mut func IsProp(): Bool {
        if (currentIndex + MANGLE_CHAR_LEN < mangledName.size) {
            let str = mangledName.SubStr(currentIndex, MANGLE_SPECIAL_NAME_LEN)
            return str == MANGLE_SET_PREFIX() || str == MANGLE_GET_PREFIX()
        }
        return false
    }

    private mut func IsInnerFunction(): Bool {
        if (mangledName.size - MANGLE_CHAR_LEN > MANGLE_INNER_FUNCTION_PREFIX().size) {
            return mangledName.Find(MANGLE_INNER_FUNCTION_PREFIX()) >= 0
        }
        return false
    }

    private mut func IsOperatorName(): Bool {
        let id = currentIndex + MANGLE_SPECIAL_NAME_LEN
        if (id < mangledName.size &&
            GetOperatorNameMap(mangledName.SubStr(currentIndex, MANGLE_SPECIAL_NAME_LEN)) != RtEmpty(mangledName.arena) &&
            (mangledName[id] == b'I' || mangledName[id] == b'H' || mangledName[id] == b'K')) {
            return true
        }
        return false
    }

    private mut func IsMaybeDefaultFuncParamFunction(): Bool {
        return currentIndex < mangledName.size && mangledName[currentIndex] == b'$'
    }

    private mut func IsNotEndOfMangledName(): Bool {
        return currentIndex < mangledName.size && mangledName[currentIndex] != b'E'
    }

    private mut func DemangleLength(): Int64 {
        if (currentIndex >= mangledName.size) {
            Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH())
            return 0
        }
        if (mangledName[currentIndex] == b'0') {
            currentIndex++
            return 0
        }

        var numStr = RtEmpty(mangledName.arena)
        isValid = false
        while (currentIndex < mangledName.size && IsCurrentCharDigit(mangledName[currentIndex])) {
            numStr += RtByte(mangledName.arena, mangledName[currentIndex])
            currentIndex++
            isValid = true
        }
        if (numStr.isEmpty()) {
            return 0
        }
        var num: Int64 = 0
        var digitIndex: Int64 = 0
        while (digitIndex < numStr.size) {
            num = num * 10 + Int64(numStr[digitIndex] - b'0')
            if (num > UINT32_MAX_AS_INT64) {
                return 0
            }
            digitIndex++
        }
        return num
    }

    private mut func UIntToString(value: Int64): RtString {
        return RtIntToString(mangledName.arena, value)
    }

    private mut func IsGlobalInit(): Bool {
        let isPkgInit = MatchForward(MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER(),
            MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER().size)
        let isFileInit = MatchForward(MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER(),
            MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER().size)
        return isPkgInit || isFileInit
    }

    private mut func IsParamInit(): Bool {
        return MatchForward(MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER(), MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER().size)
    }

    private mut func IsCFunctionWrapper(): Bool {
        if (mangledName.size > MANGLE_CFUNCTION_WRAPPER().size) {
            return mangledName.Find(MANGLE_CFUNCTION_WRAPPER(), 0) >= 0
        }
        return false
    }

    private mut func IsWrappedFunction(): Bool {
        return mangledName.Find(MANGLE_WRAPPED_FUNCTION_PREFIX(), 0) == 0
    }

    private mut func IsQualifiedType(): Bool {
        if (currentIndex >= mangledName.size) {
            return false
        }
        if (currentIndex + MANGLE_CHAR_LEN < mangledName.size) {
            if ((mangledName[currentIndex] == b'D' && mangledName[currentIndex + MANGLE_CHAR_LEN] == b'h') ||
                (mangledName[currentIndex] == b'F' && mangledName[currentIndex + MANGLE_CHAR_LEN] == b'0') ||
                (mangledName[currentIndex] == b'F' && mangledName[currentIndex + MANGLE_CHAR_LEN] == b'C')) {
                return true
            }
        }
        if (IsPrimitive(mangledName[currentIndex])) {
            return true
        }
        return match (mangledName[currentIndex]) {
            case b'C' | b'R' | b'F' | b'N' | b'T' | b'P' | b'A' | b'k' | b'V' | b'G' => true
            case _ => false
        }
    }

    private mut func IsDecl(): Bool {
        return MatchForward(MANGLE_NESTED_PREFIX(), MANGLE_NESTED_PREFIX().size)
    }

    private mut func ErrorLog(msg: RtString): Unit {}

    private mut func MatchForward(pattern: RtString, len: Int64): Bool {
        if (currentIndex >= mangledName.size) {
            return len == 0
        }
        let maxLen = mangledName.size - currentIndex
        let realLen = if (len > maxLen) { maxLen } else { len }
        let prefix = mangledName.SubStr(currentIndex, realLen)
        return prefix == pattern
    }

    private mut func PeekChar(): Byte {
        if (currentIndex >= mangledName.size) {
            return 0u8
        }
        return mangledName[currentIndex]
    }

    private mut func GetChar(): Byte {
        let ch = PeekChar()
        if (ch != 0u8) {
            currentIndex++
            return ch
        }
        return 0u8
    }

    private mut func SkipChar(ch: Byte): Unit {
        if (currentIndex >= mangledName.size) {
            Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH())
            return
        }
        if (mangledName[currentIndex] != ch) {
            Reject(RtLit(173) + RtByte(mangledName.arena, ch))
            return
        }
        currentIndex++
    }

    private mut func SkipOptionalChar(ch: Byte): Unit {
        if (currentIndex >= mangledName.size) {
            return
        }
        if (mangledName[currentIndex] == ch) {
            currentIndex++
        }
    }

    private mut func SkipString(pattern: RtString): Unit {
        var i: Int64 = 0
        while (i < pattern.size) {
            SkipChar(pattern[i])
            if (!isValid) {
                return
            }
            i++
        }
    }

    mut func DemangleGlobalInit(): DemangleInfo {
        var prefix = RtEmpty(mangledName.arena)
        if (MatchForward(MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER(), MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER().size)) {
            SkipString(MANGLE_GLOBAL_PACKAGE_INIT_PREFIX_DEMANGLER())
            let pkgDi = DemanglePackageName()
            prefix = pkgDi.pkgName + RtLit(32)
        } else if (MatchForward(MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER(), MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER().size)) {
            SkipString(MANGLE_GLOBAL_FILE_INIT_PREFIX_DEMANGLER())
            let pkgDi = DemanglePackageName()
            prefix = pkgDi.pkgName + RtLit(30)
        } else {
            return Reject(RtLit(160))
        }
        if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_RESET_SUFFIX())) {
            return DemangleInfo(prefix + RtLit(86), DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_FLAG_RESET_SUFFIX())) {
            return DemangleInfo(prefix + RtLit(81), DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_LITERAL_RESET_SUFFIX())) {
            return DemangleInfo(prefix + RtLit(85), DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_INIT_IMPORTS_INIT())) {
            return DemangleInfo(prefix + RtLit(84), DemanglerTypeKind.NAME, isValid)
        } else if (EndsWith(mangledName, MANGLE_GLOBAL_LITERAL_IMPORTS_INIT())) {
            return DemangleInfo(prefix + RtLit(83), DemanglerTypeKind.NAME, isValid)
        } else if (!EndsWith(mangledName, MANGLE_GLOBAL_INIT_SUFFIX())) {
            return Reject(RtLit(154))
        }
        return DemangleInfo(prefix + RtLit(82), DemanglerTypeKind.NAME, isValid)
    }

    mut func DemangleParamInit(): DemangleInfo {
        SkipString(MANGLE_FUNC_PARA_INIT_PREFIX_DEMANGLER())
        var di = DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.COMMON_DECL)
        let pkgDi = DemanglePackageName()
        di.pkgName = pkgDi.pkgName
        di.isPrivateDeclaration = pkgDi.isPrivateDeclaration
        let nestedDi = DemangleNestedDecls(isParamInit: true)
        di.demangled = nestedDi.demangled
        di.`type` = nestedDi.`type`
        di.args = nestedDi.args
        if (!isValid || di.demangled.isEmpty()) {
            return Reject()
        }
        if (di.`type` == DemanglerTypeKind.FUNCTION_DECL) {
            di.args = nestedDi.functionParameterTypes
        }
        return di
    }

    mut func DemangleClassType(): RtString {
        return DemangleClass(DemanglerTypeKind.CLASS).GetIdentifier()
    }

    mut func DemangleQualifiedName(): RtString {
        let info = Demangle(isType: true)
        let pkgName = info.GetPkgName()
        let clsName = info.GetIdentifier()
        if (pkgName.isEmpty()) {
            return clsName
        }
        return pkgName + RtLit(22) + clsName
    }

    mut func Demangle(isType!: Bool = false): DemangleInfo {
        if (isType) {
            if (!IsQualifiedType()) {
                return Reject(RtLit(161))
            }
            return DemangleNextUnit(RtLit(161))
        }
        if (mangledName.isEmpty()) {
            return Reject(RtLit(161))
        }
        var decompression = DeCompression(mangledName)
        mangledName = decompression.CJMangledDeCompression()
        if (IsGlobalInit()) {
            return DemangleGlobalInit()
        }
        if (IsParamInit()) {
            return DemangleParamInit()
        }
        if (IsInnerFunction()) {
            return DemangleInnerFunction()
        }
        if (IsCFunctionWrapper()) {
            return DemangleInfo(mangledName.SubStr(0, mangledName.size - MANGLE_CFUNCTION_WRAPPER().size), DemanglerTypeKind.NAME, isValid)
        }
        if (IsWrappedFunction()) {
            return DemangleWrappedFunction()
        }
        return DemangleDecl()
    }

    mut func DemanglePackageName(): DemangleInfo {
        if (currentIndex >= mangledName.size) {
            Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH())
            return DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.COMMON_DECL)
        }
        var pkg = RtEmpty(mangledName.arena)
        if (currentIndex + MANGLE_SPECIAL_NAME_LEN <= mangledName.size) {
            let stdPkg = MANGLE_STDPKG_MAP(mangledName.SubStr(currentIndex, MANGLE_SPECIAL_NAME_LEN))
            if (!stdPkg.isEmpty()) {
                pkg = stdPkg.WithArena(mangledName.arena)
                currentIndex += MANGLE_SPECIAL_NAME_LEN
            } else if (!IsCurrentCharDigit(mangledName[currentIndex])) {
                Reject(RtLit(172))
                return DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.COMMON_DECL)
            }
        } else if (!IsCurrentCharDigit(mangledName[currentIndex])) {
            Reject(RtLit(172))
            return DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.COMMON_DECL)
        }
        if (mangledName[currentIndex] == b'0') {
            currentIndex++
            return DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.COMMON_DECL)
        }
        var di = DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.COMMON_DECL)
        if (pkg.isEmpty()) {
            pkg = DemangleStringName()
            let pos = pkg.Find(RtLit(28))
            if (pos >= 0) {
                if (pkg.size - pos > 1) {
                    pkg = pkg.SubStr(0, pos) + RtLit(28) + pkg.SubStr(pos)
                }
            }
        }
        if (IsFileName()) {
            di.isPrivateDeclaration = true
            DemangleFileName()
        }
        di.pkgName = ReplaceString(pkg, MANGLE_MODULE_SPLIT(), MODULE_SPLIT())
        return di
    }

    private mut func DemangleStringName(): RtString {
        let identifyLength = DemangleLength()
        if (identifyLength == 0) {
            Reject(RtLit(170))
            return RtEmpty(mangledName.arena)
        }
        if (identifyLength > mangledName.size - currentIndex) {
            Reject(RtLit(169))
            return RtEmpty(mangledName.arena)
        }
        let name = mangledName.SubStr(currentIndex, identifyLength)
        currentIndex += identifyLength
        return name
    }

    private mut func DemangleProp(): RtString {
        var `prop` = RtEmpty(mangledName.arena)
        if (mangledName.SubStr(currentIndex, MANGLE_SPECIAL_NAME_LEN) == MANGLE_SET_PREFIX()) {
            `prop` = RtLit(33)
        } else {
            `prop` = RtLit(31)
        }
        currentIndex += MANGLE_SPECIAL_NAME_LEN
        return `prop`
    }

    private mut func SkipPrivateTopLevelDeclHash(): Unit {
        if (currentIndex >= mangledName.size || !IsCurrentCharDigit(mangledName[currentIndex]) ||
            mangledName[currentIndex] == b'0') {
            return
        }
        let oldIdx = currentIndex
        let hashLen = DemangleLength()
        if (currentIndex + hashLen >= mangledName.size || mangledName[currentIndex] != b'$') {
            currentIndex = oldIdx
            return
        }
        let isBoxedDecl = mangledName.Find(BOX_DECL_PREFIX(), currentIndex) == currentIndex &&
            !EndsWith(mangledName.SubStr(currentIndex, hashLen), CJ_FILE_EXT())
        if (isBoxedDecl) {
            currentIndex = oldIdx
            return
        }
        currentIndex += hashLen
    }

    private mut func DemangleManglingNumber(): Int64 {
        var content = RtEmpty(mangledName.arena)
        while (true) {
            let c = GetChar()
            if (c != 0u8) {
                if (c == b'_') {
                    break
                } else {
                    content += RtByte(mangledName.arena, c)
                }
            } else {
                Reject(RtLit(166))
                return 0
            }
        }
        if (content == RtEmpty(mangledName.arena)) {
            return 0
        }
        var value: Int64 = 0
        var power: Int64 = 1
        var index = content.size - 1
        while (true) {
            var matched = false
            var i: Int64 = 0
            while (i < BASE62_CHARS_SIZE) {
                if (content[index] == BASE62_CHARS()[i]) {
                    value += i * power
                    power *= BASE62_CHARS_SIZE
                    matched = true
                    break
                }
                i++
            }
            if (!matched) {
                Reject(RtLit(165))
                return 0
            }
            if (index == 0) {
                break
            }
            index--
        }
        return value + 1
    }

    private mut func DemangleFileNameNumber(): Unit {
        var content = RtEmpty(mangledName.arena)
        while (true) {
            if (content.size == FILE_HASH_LEN) {
                break
            } else {
                let c = GetChar()
                if (c != 0u8) {
                if (c == b'$') {
                    return
                } else {
                    content += RtByte(mangledName.arena, c)
                }
                } else {
                    Reject(RtLit(166))
                    return
                }
            }
        }

        var index = content.size - 1
        while (true) {
            var matched = false
            var i: Int64 = 0
            while (i < BASE62_CHARS_SIZE) {
                if (content[index] == BASE62_CHARS()[i]) {
                    matched = true
                    break
                }
                i++
            }
            if (!matched) {
                Reject(RtLit(165))
                return
            }
            if (index == 0) {
                break
            }
            index--
        }
    }

    private mut func IsFileName(): Bool {
        return PeekChar() == b'U'
    }

    private mut func DemangleFileName(): Unit {
        SkipChar(b'U')
        DemangleFileNameNumber()
    }

    private mut func SkipLocalCounter(): Unit {
        if (PeekChar() != b'K') {
            return
        }
        SkipChar(b'K')
        DemangleManglingNumber()
    }

    private mut func DemangleArgTypes(delimiter: RtString, size!: Int64 = UINT32_MAX_AS_INT64): RtString {
        if (currentIndex == mangledName.size - 1 && mangledName[currentIndex] == b'v') {
            SkipChar(b'v')
            return RtEmpty(mangledName.arena)
        }
        var i: Int64 = 0
        var result = RtEmpty(mangledName.arena)
        var hasTrailingDelimiter = false
        let argsArr = RtStringSlots(mangledName.arena)
        if (argsArr.isNull()) {
            return RtEmpty(mangledName.arena)
        }
        while (IsNotEndOfMangledName() && i < size) {
            if (mangledName[currentIndex] == b'_') {
                SkipChar(b'_')
            }
            if (IsMaybeDefaultFuncParamFunction()) {
                break
            }
            let curDi = DemangleNextUnit(RtLit(158))
            if (!isValid) {
                return RtEmpty(mangledName.arena)
            }
            let j = i & 15
            if (j == 0 && i != 0) {
                var flushIndex: Int64 = 0
                while (flushIndex < MAX_ARGS_SIZE) {
                    result += RtStringSlotGet(argsArr, flushIndex) + delimiter
                    flushIndex++
                }
                var resetIdx: Int64 = 0
                while (resetIdx < MAX_ARGS_SIZE) {
                    RtStringSlotSet(argsArr, resetIdx, RtEmpty(mangledName.arena))
                    resetIdx++
                }
                hasTrailingDelimiter = true
            }
            i++
            RtStringSlotSet(argsArr, j, curDi.GetFullName(scopeResolution))
        }
        if (i == 0) {
            return result
        }
        let remainingLength = ((i - 1) & 15) + 1
        if (remainingLength == 0 && hasTrailingDelimiter) {
            result = result.SubStr(0, result.size - delimiter.size)
        }
        result += GetArgTypesFullName(argsArr, remainingLength, delimiter)
        return result
    }

    private mut func DemangleNestedDecls(isClass!: Bool = false, isParamInit!: Bool = false): DemangleInfo {
        let delimiter = scopeResolution
        var i: Int64 = 0
        var result = RtEmpty(mangledName.arena)
        let argsArr = RtStringSlots(mangledName.arena)
        if (argsArr.isNull()) {
            return Reject(RtLit(164))
        }
        var typeKind = DemanglerTypeKind.COMMON_DECL
        var lastElement = DemangleInfo()
        while (IsNotEndOfMangledName()) {
            typeKind = DemanglerTypeKind.COMMON_DECL
            if (mangledName[currentIndex] == b'L') {
                currentIndex++
                let lambdaIDString = UIntToString(DemangleManglingNumber())
                let j = i & 15
                i++
                RtStringSlotSet(argsArr, j, RtLit(163) + lambdaIDString)
                typeKind = DemanglerTypeKind.LAMBDA_FUNCTION
                continue
            }
            if (mangledName[currentIndex] == b'X') {
                currentIndex++
                if (!IsQualifiedType()) {
                    return Reject(RtLit(161))
                }
                let curDi = DemangleNextUnit(RtLit(161))
                let j = i & 15
                i++
                RtStringSlotSet(argsArr, j, curDi.GetIdentifier())
                if (IsFileName()) {
                    DemangleFileName()
                }
                SkipLocalCounter()
                continue
            }
            var curDi: DemangleInfo
            if (IsOperatorName()) {
                curDi = DemangleInfo(GetOperatorNameMap(mangledName.SubStr(currentIndex, MANGLE_SPECIAL_NAME_LEN)),
                    DemanglerTypeKind.NAME, isValid)
                currentIndex += MANGLE_SPECIAL_NAME_LEN
            } else {
                curDi = DemangleInfo(DemangleStringName(), DemanglerTypeKind.NAME, isValid)
                if (IsProp()) {
                    curDi.demangled += DemangleProp()
                }
            }
            if (currentIndex >= mangledName.size) {
                let j = i & 15
                i++
                RtStringSlotSet(argsArr, j, curDi.GetFullName(scopeResolution))
                break
            }
            SkipLocalCounter()
            if (!isValid) {
                return Reject(RtLit(164))
            }
            if (IsGeneric(mangledName[currentIndex])) {
                SkipChar(b'I')
                let generic = DemangleGenericTypes().GetFullName(scopeResolution)
                curDi.genericTypes = RtFilterGeneric(generic)
                if (!isClass) {
                    SkipOptionalChar(b'E')
                }
            }
            let ch = PeekChar()
            if (ch != 0u8 && IsFunction(ch)) {
                    SkipChar(b'H')
                    typeKind = DemanglerTypeKind.FUNCTION_DECL
                    let funcTys = DemangleFunctionParameterTypes().args
                    curDi.functionParameterTypes = funcTys
                    SkipOptionalChar(b'E')
            }
            let j = i & 15
            if (j == 0 && i != 0) {
                var flushIndex: Int64 = 0
                while (flushIndex < MAX_ARGS_SIZE) {
                    result += RtStringSlotGet(argsArr, flushIndex) + delimiter
                    flushIndex++
                }
                result = result.SubStr(0, result.size - delimiter.size)
            }
            i++
            if (isParamInit && IsNotEndOfMangledName() && curDi.functionParameterTypes.size > 0) {
                RtStringSlotSet(argsArr, j, curDi.GetFullName(scopeResolution) + LEFT_BRACKET() +
                    curDi.functionParameterTypes + RIGHT_BRACKET())
            } else {
                RtStringSlotSet(argsArr, j, curDi.GetFullName(scopeResolution))
            }
            lastElement = curDi
        }
        let remainingLength = if (i == 0) { 0 } else { ((i - 1) & 15) + 1 }
        result += GetArgTypesFullName(argsArr, remainingLength, delimiter)
        var resDi = DemangleInfo(result, typeKind, isValid)
        resDi.functionParameterTypes = lastElement.functionParameterTypes
        return resDi
    }

    private mut func DemangleClass(typeKind: DemanglerTypeKind): DemangleInfo {
        currentIndex++
        var di = DemangleCommonDecl(isClass: true)
        di.`type` = typeKind
        if (PeekChar() == b'E') {
            SkipChar(b'E')
        }
        return di
    }

    private mut func DemangleCFuncType(): DemangleInfo {
        SkipString(MANGLE_C_FUNCTY_PREFIX())
        var di = DemangleInfo(DemangleNextUnit().GetFullName(scopeResolution), DemanglerTypeKind.FUNCTION)
        di.args = DemangleArgTypes(ARGS_DELIMITER())
        SkipChar(b'E')
        return di
    }

    private mut func DemangleFunction(): DemangleInfo {
        SkipString(MANGLE_FUNCTY_PREFIX())
        var di = DemangleInfo(DemangleNextUnit().GetFullName(scopeResolution), DemanglerTypeKind.FUNCTION)
        di.args = DemangleArgTypes(ARGS_DELIMITER())
        SkipChar(b'E')
        return di
    }

    private mut func DemangleTuple(): DemangleInfo {
        var di = DemangleInfo(MANGLE_TUPLE_STR().WithArena(mangledName.arena), DemanglerTypeKind.TUPLE)
        SkipChar(b'T')
        DemangleManglingNumber()
        let generic = DemangleGenericTypes().GetFullName(scopeResolution)
        di.genericTypes = RtFilterGeneric(generic)
        SkipChar(b'E')
        return di
    }

    private mut func DemangleRawArray(): DemangleInfo {
        var di = DemangleInfo(MANGLE_ARRAY_STR().WithArena(mangledName.arena), DemanglerTypeKind.RAW_ARRAY)
        SkipChar(b'A')
        var dim = DemangleManglingNumber()
        while (dim > 0) {
            di.genericConstraints += RtLit(74).WithArena(mangledName.arena)
            dim--
        }
        di.args = DemangleNextUnit().GetFullName(scopeResolution)
        return di
    }

    private mut func DemangleVArray(): DemangleInfo {
        var di = DemangleInfo(MANGLE_VARRAY_STR().WithArena(mangledName.arena), DemanglerTypeKind.TUPLE)
        SkipChar(b'V')
        let num = DemangleManglingNumber()
        di.genericTypes = DemangleGenericTypes().GetFullName(scopeResolution, num)
        return di
    }

    private mut func DemangleCPointer(): DemangleInfo {
        var di = DemangleInfo(MANGLE_PTR_STR().WithArena(mangledName.arena), DemanglerTypeKind.CPOINTER)
        SkipChar(b'P')
        let generic = DemangleType().GetFullName(scopeResolution)
        di.genericTypes = RtFilterGeneric(generic)
        return di
    }

    private mut func DemangleCommonDecl(isClass!: Bool = false): DemangleInfo {
        var isGlobalVariableInitPrefix = false
        if (mangledName[currentIndex] == b'N') {
            SkipString(MANGLE_NESTED_PREFIX())
        } else {
            SkipString(GLOBAL_VARIABLE_INIT_PREFIX())
            isGlobalVariableInitPrefix = true
        }
        if (!isValid) {
            return Reject()
        }
        var di = DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.COMMON_DECL)
        let pkgDi = DemanglePackageName()
        di.pkgName = pkgDi.pkgName
        di.isPrivateDeclaration = pkgDi.isPrivateDeclaration
        let nestedDi = DemangleNestedDecls(isClass: isClass)
        di.demangled = nestedDi.demangled
        di.`type` = nestedDi.`type`
        di.args = nestedDi.args
        if (!isValid || di.demangled.isEmpty()) {
            return Reject()
        }
        if (di.`type` == DemanglerTypeKind.FUNCTION_DECL) {
            di.args = nestedDi.functionParameterTypes
        }
        if (isGlobalVariableInitPrefix) {
            di.`type` = DemanglerTypeKind.COMMON_DECL
        }
        return di
    }

    private mut func DemangleDecl(): DemangleInfo {
        SkipString(MANGLE_CANGJIE_PREFIX())
        if (!isValid) {
            return Reject()
        }
        var di = DemangleCommonDecl()
        if (di.`type` == DemanglerTypeKind.LAMBDA_FUNCTION) {
            return di
        }
        if (!isValid || currentIndex >= mangledName.size) {
            return di
        }
        if (mangledName[currentIndex] == b'E') {
            return di
        }
        di.`type` = DemanglerTypeKind.FUNCTION_DECL
        di.args = DemangleArgTypes(ARGS_DELIMITER())
        if (!isValid) {
            return Reject()
        }
        if (IsMaybeDefaultFuncParamFunction()) {
            let dpf = DemangleDefaultParamFunction()
            if (!isValid) {
                return Reject()
            }
            di.demangled = di.GetFullName(scopeResolution) + scopeResolution + dpf.demangled
            di.args = dpf.args
        }
        return di
    }

    private mut func DemanglePrimitive(): DemangleInfo {
        if (currentIndex >= mangledName.size) {
            return Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH())
        }
        let ch = mangledName[currentIndex]
        if (MatchForward(MANGLE_FLOAT16_PREFIX(), MANGLE_FLOAT16_PREFIX().size)) {
            SkipString(MANGLE_FLOAT16_PREFIX())
        } else {
            SkipChar(ch)
        }
        return DemangleInfo(GetPrimitiveDemangleMap(ch).WithArena(mangledName.arena), DemanglerTypeKind.PRIMITIVE)
    }

    private mut func DemangleCStringType(): DemangleInfo {
        SkipChar(b'k')
        return DemangleInfo(MANGLE_CSTRING_STR().WithArena(mangledName.arena), DemanglerTypeKind.CSTRING, isValid)
    }

    private mut func DemangleGenericType(): DemangleInfo {
        SkipChar(b'G')
        let gNumber = DemangleManglingNumber()
        let name = RtLit(64) + UIntToString(gNumber)
        return DemangleInfo(name, DemanglerTypeKind.GENERIC_TYPES, isValid)
    }

    private mut func DemangleType(): DemangleInfo {
        var di = DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.GENERIC_TYPES)
        if (IsQualifiedType()) {
            let curDi = DemangleNextUnit()
            if (isValid) {
                di.args = curDi.GetFullName(scopeResolution)
                return di
            }
        }
        isValid = false
        return di
    }

    private mut func DemangleGenericTypes(): DemangleInfo {
        var di = DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.GENERIC_TYPES)
        var firstIteration = true
        var argTypesFullName = RtEmpty(mangledName.arena)
        while (IsNotEndOfMangledName() && !IsCurrentCharDigit(mangledName[currentIndex]) &&
            !IsFunction(mangledName[currentIndex]) && !IsOperatorName()) {
            let curDi = DemangleNextUnit()
            if (!isValid) {
                break
            }
            if (!firstIteration) {
                argTypesFullName += ARGS_DELIMITER_TYPE()
            }
            argTypesFullName += curDi.GetFullName(scopeResolution)
            firstIteration = false
        }
        di.args = argTypesFullName
        return di
    }

    private mut func DemangleFunctionParameterTypes(): DemangleInfo {
        var di = DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.FUNCTION_PARAMETER_TYPES)
        var firstIteration = true
        var argTypesFullName = RtEmpty(mangledName.arena)
        if (IsNotEndOfMangledName() && mangledName[currentIndex] == b'v') {
            currentIndex += MANGLE_CHAR_LEN
        } else {
            while (IsNotEndOfMangledName() && !IsCurrentCharDigit(mangledName[currentIndex])) {
                let curDi = DemangleNextUnit()
                if (!isValid) {
                    break
                }
                if (!firstIteration) {
                    argTypesFullName += ARGS_DELIMITER()
                }
                argTypesFullName += curDi.GetFullName(scopeResolution)
                firstIteration = false
            }
        }
        di.args = argTypesFullName
        return di
    }

    private mut func DemangleDefaultParamFunction(): DemangleInfo {
        let pos = mangledName.Find(MANGLE_WILDCARD_PREFIX(), currentIndex)
        if (pos == -1 || pos == mangledName.size - 1 || !IsCurrentCharDigit(mangledName[pos + MANGLE_CHAR_LEN])) {
            return Reject(RtLit(159))
        }
        SkipChar(b'$')
        let identifier = mangledName.SubStr(currentIndex, pos - currentIndex)
        var di = DemangleInfo(identifier, DemanglerTypeKind.FUNCTION_DECL)
        SkipString(identifier)
        SkipChar(b'_')
        DemangleLength()
        if (!IsNotEndOfMangledName()) {
            return Reject(RtLit(159))
        }
        di.args = DemangleArgTypes(ARGS_DELIMITER())
        return di
    }

    private mut func DemangleInnerFunction(): DemangleInfo {
        var di = DemangleInfo(RtEmpty(mangledName.arena), DemanglerTypeKind.LAMBDA_FUNCTION)
        var prefixIndex = mangledName.Find(MANGLE_INNER_FUNCTION_PREFIX())
        if (prefixIndex < 0) {
            prefixIndex = 0
        }
        if (!isValid) {
            return Reject()
        }
        let pkgName = mangledName.SubStr(currentIndex, prefixIndex - currentIndex)
        di.pkgName = pkgName
        let funcName = mangledName.SubStr(prefixIndex + MANGLE_CHAR_LEN)
        di.demangled = funcName
        currentIndex = mangledName.size
        return di
    }

    private mut func DemangleWrappedFunction(): DemangleInfo {
        var endIndex = mangledName.Find(MANGLE_DOLLAR_PREFIX(), currentIndex)
        if (endIndex < 0) {
            endIndex = mangledName.size
        }
        let prefixIndex = currentIndex + MANGLE_WRAPPED_FUNCTION_PREFIX().size
        mangledName = MANGLE_CANGJIE_PREFIX() + mangledName.SubStr(prefixIndex, endIndex - prefixIndex)
        var di = DemangleDecl()
        di.demangled += WRAPPED_FUNCTION_SUFFIX_INFO()
        di.`type` = DemanglerTypeKind.WRAPPED_FUNCTION
        return di
    }

    private mut func Reject(): DemangleInfo {
        return Reject(RtEmpty(mangledName.arena))
    }

    private mut func Reject(reason: RtString): DemangleInfo {
        if (currentIndex == mangledName.size && !isValid) {
            return dumpDi
        }
        ErrorLog(reason)
        isValid = false
        currentIndex = mangledName.size
        return dumpDi
    }

    private mut func DemangleNextUnit(): DemangleInfo {
        return DemangleNextUnit(RtEmpty(mangledName.arena))
    }

    private mut func DemangleNextUnit(message: RtString): DemangleInfo {
        let di = DemangleByPrefix()
        if (!isValid) {
            return Reject(RtLit(45) + message)
        }
        return di
    }

    private mut func DemangleByPrefix(): DemangleInfo {
        if (currentIndex >= mangledName.size) {
            return Reject(ERROR_EXCEED_THE_INPUT_STRING_LENGTH())
        }
        let ch = mangledName[currentIndex]
        match (ch) {
            case b'C' => return DemangleClass(DemanglerTypeKind.CLASS)
            case b'R' => return DemangleClass(DemanglerTypeKind.STRUCT)
            case b'F' =>
                if (currentIndex + MANGLE_CHAR_LEN < mangledName.size) {
                    if (mangledName[currentIndex + MANGLE_CHAR_LEN] == b'0') {
                        return DemangleFunction()
                    } else if (mangledName[currentIndex + MANGLE_CHAR_LEN] == b'C') {
                        return DemangleCFuncType()
                    }
                }
            case b'N' => return DemangleClass(DemanglerTypeKind.ENUM)
            case b'T' => return DemangleTuple()
            case b'P' => return DemangleCPointer()
            case b'_' => ()
            case b'A' => return DemangleRawArray()
            case b'V' => return DemangleVArray()
            case b'k' => return DemangleCStringType()
            case b'G' => return DemangleGenericType()
            case _ =>
                if (IsCurrentCharDigit(ch)) {
                    return DemangleInfo(DemangleStringName(), DemanglerTypeKind.NAME, isValid)
                } else if (IsPrimitive(ch)) {
                    return DemanglePrimitive()
                } else if (IsOperatorName()) {
                    var di = DemangleInfo(GetOperatorNameMap(mangledName.SubStr(currentIndex, MANGLE_SPECIAL_NAME_LEN))
                            .WithArena(mangledName.arena),
                        DemanglerTypeKind.NAME, isValid)
                    currentIndex += MANGLE_SPECIAL_NAME_LEN
                    return di
                }
        }
        return Reject(RtLit(238))
    }
}
