// Behavior-equivalent port of runtime/src/Demangler/DeCompression.cpp.
// Parser strings, mutable references, and the tree-id map are backed only by
// the request arena; no managed String or collection is used.
package rt.demangle

@C
struct TreePos {
    let start: Int64
    let length: Int64

    init(start: Int64, length: Int64) {
        this.start = start
        this.length = length
    }

    operator func [](index: Int64): Int64 {
        return if (index == 0) { start } else { length }
    }
}

@C
struct TreeMapState {
    let entries: CPointer<TreePos>
    var size: Int64
    let capacity: Int64

    init(entries: CPointer<TreePos>, size: Int64, capacity: Int64) {
        this.entries = entries
        this.size = size
        this.capacity = capacity
    }
}

// A symbol of N bytes cannot contribute more than N grammar nodes.  The map
// is therefore a single arena allocation with an input-derived hard bound.
struct TreeIdMap {
    private let state: CPointer<TreeMapState>

    init(arena: CPointer<RtArena>, capacity: Int64) {
        let entries = CPointer<TreePos>(RtArenaAlloc(arena, capacity * 16))
        let rawState = RtArenaAlloc(arena, 24)
        state = CPointer<TreeMapState>(rawState)
        if (!state.isNull()) {
            unsafe { state.write(0, TreeMapState(entries, 0, capacity)) }
        }
    }

    prop size: Int64 {
        get() { return if (state.isNull()) { 0 } else { unsafe { state.read().size } } }
    }

    func isEmpty(): Bool { return size == 0 }

    operator func [](index: Int64): TreePos {
        if (state.isNull() || index < 0 || index >= size) { return TreePos(0, 0) }
        return unsafe { state.read().entries.read(index) }
    }

    func Set(index: Int64, value: TreePos): Unit {
        if (!state.isNull() && index >= 0 && index < size) {
            unsafe { state.read().entries.write(index, value) }
        }
    }

    func add(value: TreePos): Bool {
        if (state.isNull()) { return false }
        let current = unsafe { state.read() }
        if (current.entries.isNull() || current.size >= current.capacity) { return false }
        unsafe {
            current.entries.write(current.size, value)
            state.write(0, TreeMapState(current.entries, current.size + 1, current.capacity))
        }
        return true
    }

    func removeAt(index: Int64): Unit {
        if (state.isNull() || index < 0 || index >= size) { return }
        let current = unsafe { state.read() }
        var cursor = index
        unsafe {
            while (cursor + 1 < current.size) {
                current.entries.write(cursor, current.entries.read(cursor + 1))
                cursor++
            }
            state.write(0, TreeMapState(current.entries, current.size - 1, current.capacity))
        }
    }
}

struct RtStringRef {
    private let cell: CPointer<RtString>

    init(value: RtString) {
        cell = CPointer<RtString>(RtArenaAlloc(value.arena, 40))
        if (!cell.isNull()) { unsafe { cell.write(0, value) } }
    }

    func Get(): RtString {
        return if (cell.isNull()) { RtLit(0) } else { unsafe { cell.read() } }
    }

    func Set(value: RtString): Unit {
        if (!cell.isNull()) { unsafe { cell.write(0, value) } }
    }
}

struct IntRef {
    private let cell: CPointer<Int64>

    init(arena: CPointer<RtArena>, value: Int64) {
        cell = CPointer<Int64>(RtArenaAlloc(arena, 8))
        if (!cell.isNull()) { unsafe { cell.write(0, value) } }
    }

    func Get(): Int64 { return if (cell.isNull()) { 0 } else { unsafe { cell.read() } } }
    func Set(value: Int64): Unit { if (!cell.isNull()) { unsafe { cell.write(0, value) } } }
}

struct CompressionUpdate {
    let change: Int64
    let nextIndex: Int64
    let value: RtString

    init(change: Int64, nextIndex: Int64, value: RtString) {
        this.change = change
        this.nextIndex = nextIndex
        this.value = value
    }
}


private let NPOS: Int64 = -1
private let MANGLE_COMPRESS_PREFIX: Byte = b'Y'
private let MANGLE_ANONYMOUS_PREFIX: Byte = b'0'
private let PREFIX_LEN: Int64 = 2
private let MANGLE_CHAR_LEN: Int64 = 1
private let MANGLE_SPECIAL_NAME_LEN: Int64 = 2
private let FILE_HASH_LEN: Int64 = 13

// Keep in lockstep with cangjie_compiler/demangler/Utils.h:54.
private class OperatorKind {
    public static let AN: Int64 = 13
    public static let CL: Int64 = 75
    public static let DV: Int64 = 117
    public static let EO: Int64 = 142
    public static let EQ: Int64 = 144
    public static let GE: Int64 = 196
    public static let GT: Int64 = 211
    public static let IX: Int64 = 279
    public static let LE: Int64 = 356
    public static let LS: Int64 = 370
    public static let LT: Int64 = 371
    public static let ML: Int64 = 395
    public static let NE: Int64 = 420
    public static let NG: Int64 = 422
    public static let NT: Int64 = 435
    public static let OR: Int64 = 465
    public static let PL: Int64 = 491
    public static let PW: Int64 = 502
    public static let RM: Int64 = 556
    public static let RS: Int64 = 562

    private init() {}
}

private func PrimitivePrefixSet(): RtString { return RtLit(167) }

private func StripCangjieAt(identifier: RtString, idx: Int64): Int64 {
    if (idx < identifier.size && identifier[idx] == b'@') {
        return idx + MANGLE_CHAR_LEN
    }
    return idx
}

private func StripCangjiePrefix(identifier: RtString, idx: Int64): Int64 {
    if (idx + MANGLE_CHAR_LEN < identifier.size && identifier[idx] == b'_' &&
        identifier[idx + MANGLE_CHAR_LEN] == b'C') {
        if (idx + MANGLE_CHAR_LEN * 2 < identifier.size && identifier[idx + MANGLE_CHAR_LEN * 2] == b'V') {
            return idx + PREFIX_LEN + MANGLE_CHAR_LEN
        } else {
            return idx + PREFIX_LEN
        }
    }
    return idx
}

private func GetNumber(base62: RtString): Int64 {
    let base62Chars = RtLit(27)
    let n: Int64 = 62
    if (base62 == RtLit(76)) {
        return 0
    }
    let newBase62 = base62.SubStr(0, base62.size - 1)
    var decimal: Int64 = 0
    var power: Int64 = 1
    var i = newBase62.size - 1
    while (i != NPOS) {
        var baseIndex: Int64 = 0
        while (baseIndex < base62Chars.size) {
            if (base62Chars[baseIndex] == newBase62[i]) {
                decimal += baseIndex * power
                break
            }
            baseIndex++
        }
        power *= n
        i--
    }
    return decimal + 1
}

private func IsStdPkgName(mangled: RtString, idx: Int64): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    return !MANGLE_STDPKG_MAP(mangled.SubStr(idx, MANGLE_SPECIAL_NAME_LEN)).isEmpty()
}

private func IsOperatorName(mangled: RtString, idx: Int64): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    if (!((mangled[idx] >= b'a' && mangled[idx] <= b'z') &&
        (mangled[idx + MANGLE_CHAR_LEN] >= b'a' && mangled[idx + MANGLE_CHAR_LEN] <= b'z'))) {
        return false
    }
    let operatorIndex = ((Int64(mangled[idx]) - Int64(b'a')) << 5) +
        Int64(mangled[idx + MANGLE_CHAR_LEN]) - Int64(b'a')
    return operatorIndex == OperatorKind.IX || operatorIndex == OperatorKind.NT ||
        operatorIndex == OperatorKind.NG || operatorIndex == OperatorKind.PW ||
        operatorIndex == OperatorKind.ML || operatorIndex == OperatorKind.DV ||
        operatorIndex == OperatorKind.RM || operatorIndex == OperatorKind.PL ||
        operatorIndex == OperatorKind.LS || operatorIndex == OperatorKind.RS ||
        operatorIndex == OperatorKind.LT || operatorIndex == OperatorKind.GT ||
        operatorIndex == OperatorKind.LE || operatorIndex == OperatorKind.GE ||
        operatorIndex == OperatorKind.EQ || operatorIndex == OperatorKind.NE ||
        operatorIndex == OperatorKind.AN || operatorIndex == OperatorKind.EO ||
        operatorIndex == OperatorKind.OR || operatorIndex == OperatorKind.CL
}

private func IsPrimitiveType(ch: Byte): Bool {
    var i: Int64 = 0
    while (i < PrimitivePrefixSet().size) {
        if (ch == PrimitivePrefixSet()[i]) {
            return true
        }
        i++
    }
    return false
}

private func IsPropName(mangled: RtString, idx: Int64): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    if (mangled[idx] == b'p' && (mangled[idx + MANGLE_CHAR_LEN] == b's' ||
        mangled[idx + MANGLE_CHAR_LEN] == b'g')) {
        return true
    }
    return false
}

private func ForwardPrimitiveType(mangled: RtString, idx: Int64): Int64 {
    if (mangled[idx] != b'D' && IsPrimitiveType(mangled[idx])) {
        return idx + MANGLE_CHAR_LEN
    }
    if (idx + MANGLE_CHAR_LEN < mangled.size && mangled[idx] == b'D' &&
        mangled[idx + MANGLE_CHAR_LEN] == b'h') {
        return idx + MANGLE_SPECIAL_NAME_LEN
    }
    return idx
}

private func ForwardFileNameNumber(mangled: RtString, idx: Int64): Int64 {
    var curIdx = idx
    var isValid = false
    while (true) {
        if (curIdx >= mangled.size) {
            return idx
        }
        if (mangled[curIdx] == b'$') {
            return curIdx + 1
        }
        if (curIdx + 1 - idx == FILE_HASH_LEN) {
            isValid = true
            break
        }
        curIdx++
    }
    if (isValid) {
        var i = idx
        while (i <= curIdx) {
            if (!IsAlnum(mangled[i])) {
                return idx
            }
            i++
        }
        return curIdx + 1
    }
    return idx
}

struct DeCompression {
    private var pid: Int64 = 0
    private var isRecord: Bool
    private var mangledName: RtString
    private var currentIndex: Int64 = 0
    private var decompressed: RtString
    private let treeIdMap: TreeIdMap

    init(mangled: RtString) {
        isRecord = false
        mangledName = mangled
        decompressed = RtEmpty(mangled.arena)
        treeIdMap = TreeIdMap(mangled.arena, mangled.size + 1)
    }

    mut func IsGlobalEncode(mangled: RtStringRef): Bool {
        if (IsSamePrefix(mangled, RtLit(54), 0) || IsSamePrefix(mangled, RtLit(53), 0) ||
            IsSamePrefix(mangled, RtLit(52), 0)) {
            return true
        }
        return false
    }

    mut func IsSamePrefix(first: RtStringRef, second: RtString, idx: Int64): Bool {
        var i = idx
        while (i < idx + PREFIX_LEN) {
            if (i < first.Get().size && i < second.size && first.Get()[i] != second[i]) {
                return false
            }
            i++
        }
        return true
    }

    mut func IsVarDeclEncode(mangled: RtStringRef): Bool {
        this.isRecord = false
        let n = mangled.Get().size
        if (n == 0) {
            return false
        }
        var idx: Int64 = 0
        if (mangled.Get()[0] == b'E') {
            return true
        } else if (mangled.Get()[0] == MANGLE_COMPRESS_PREFIX) {
            idx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
            if (idx < n && mangled.Get()[idx] == b'E') {
                return true
            }
        } else if (IsDigit(mangled.Get()[0])) {
            idx = ForwardName(mangled, idx: 0)
            if (idx < n && mangled.Get()[idx] == b'K') {
                idx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
                if (idx < n && mangled.Get()[idx] == b'E') {
                    return true
                } else {
                    return false
                }
            } else if (idx < n && mangled.Get()[idx] == b'E') {
                return true
            }
        } else if (mangled.Get()[0] == b'K') {
            idx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
            if (idx < n && mangled.Get()[idx] == b'E') {
                return true
            }
        }
        return false
    }

    mut func IsDefaultParamFuncEncode(mangled: RtStringRef): Bool {
        if (IsSamePrefix(mangled, RtLit(61), 0)) {
            return true
        }
        return false
    }

    mut func HasDuplicates(mangled: RtStringRef, pos: TreePos): Bool {
        let posStr = mangled.Get().SubStr(pos[0], pos[1])
        var tid: Int64 = 0
        while (tid < treeIdMap.size) {
            let item = treeIdMap[tid]
            let itStr = mangled.Get().SubStr(item[0], item[1])
            if (itStr.isEmpty()) {
                tid++
                continue
            }
            if (itStr == posStr) {
                return true
            }
            tid++
        }
        return false
    }

    mut func HasDuplicates(mangled: RtStringRef, mid: Int64): Bool {
        if (mid >= treeIdMap.size) {
            return false
        }
        let cur = treeIdMap[mid]
        let curStr = mangled.Get().SubStr(cur[0], cur[1])
        var tid: Int64 = 0
        while (tid < treeIdMap.size) {
            let item = treeIdMap[tid]
            if (tid == mid) {
                tid++
                continue
            }
            let itStr = mangled.Get().SubStr(item[0], item[1])
            if (itStr.isEmpty()) {
                tid++
                continue
            }
            if (itStr == curStr) {
                return true
            }
            tid++
        }
        return false
    }

    mut func ForwardPackageName(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        var curIdx = idx
        if (IsStdPkgName(mangled.Get(), curIdx)) {
            curIdx += MANGLE_SPECIAL_NAME_LEN
        } else {
            curIdx = ForwardName(mangled, idx: idx)
        }
        if (this.isRecord && curIdx != idx) {
            let pos = TreePos(idx, curIdx - idx)
            let isPush = TreeIdMapPushBack(mangled, pos)
            cnt.Set(if (isPush) { cnt.Get() + 1 } else { cnt.Get() })
        }
        if (curIdx < mangled.Get().size && mangled.Get()[curIdx] == b'U') {
            let fid = ForwardFileNameNumber(mangled.Get(), curIdx + MANGLE_CHAR_LEN)
            if (this.isRecord && fid != curIdx + MANGLE_CHAR_LEN) {
                let pos = TreePos(curIdx, fid - curIdx)
                let isPush = TreeIdMapPushBack(mangled, pos)
                cnt.Set(if (isPush) { cnt.Get() + 1 } else { cnt.Get() })
            }
            curIdx = fid
        }
        return curIdx
    }

    mut func ForwardGenericTypes(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        let curCnt = cnt.Get()
        let curIdx = ForwardTypes(mangled, cnt, startId: idx + MANGLE_CHAR_LEN)
        if (curIdx < mangled.Get().size && mangled.Get()[curIdx] == b'E') {
            return curIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    mut func ForwardClassType(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        var curIdx = idx
        let curCnt = cnt.Get()
        if (idx + PREFIX_LEN < mangled.Get().size &&
            (mangled.Get()[idx] == b'C' || mangled.Get()[idx] == b'R' || mangled.Get()[idx] == b'N') &&
            mangled.Get()[idx + MANGLE_CHAR_LEN] == b'N') {
            curIdx += PREFIX_LEN
        } else {
            return idx
        }
        UpdateCompressedName(mangled, curIdx)
        curIdx = ForwardPackageName(mangled, cnt, curIdx)
        let fid = curIdx
        UpdateCompressedName(mangled, fid)
        curIdx = ForwardName(mangled, idx: fid)
        if (this.isRecord && curIdx != fid) {
            let pos = TreePos(fid, curIdx - fid)
            let isPush = TreeIdMapPushBack(mangled, pos)
            cnt.Set(if (isPush) { cnt.Get() + 1 } else { cnt.Get() })
        }
        if (curIdx < mangled.Get().size && mangled.Get()[curIdx] == b'I') {
            let genericIdx = ForwardGenericTypes(mangled, cnt, curIdx)
            if (curIdx != genericIdx) {
                return genericIdx
            }
        } else if (curIdx < mangled.Get().size && mangled.Get()[curIdx] == b'E') {
            return curIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    mut func ForwardFunctionType(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        let curCnt = cnt.Get()
        var curIdx = ForwardType(mangled, cnt, idx: idx + PREFIX_LEN)
        curIdx = ForwardTypes(mangled, cnt, startId: curIdx)
        if (curIdx < mangled.Get().size && mangled.Get()[curIdx] == b'E') {
            return curIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    mut func ForwardTupleType(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        let curIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
        if (curIdx == idx + MANGLE_CHAR_LEN || curIdx >= mangled.Get().size ||
            idx + MANGLE_CHAR_LEN >= mangled.Get().size) {
            return idx
        }
        let curCnt = cnt.Get()
        var tyCnt = GetNumber(mangled.Get().SubStr(idx + MANGLE_CHAR_LEN, curIdx - idx - MANGLE_CHAR_LEN))
        var endIdx = curIdx
        while (endIdx < mangled.Get().size && mangled.Get()[endIdx] != b'E' && tyCnt != 0) {
            let tyIdx = ForwardType(mangled, cnt, idx: endIdx)
            if (tyIdx == endIdx) {
                break
            }
            endIdx = tyIdx
            tyCnt--
        }
        if (curIdx != endIdx && endIdx < mangled.Get().size && mangled.Get()[endIdx] == b'E') {
            return endIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    mut func ForwardCPointer(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        return ForwardType(mangled, cnt, idx: idx + MANGLE_CHAR_LEN)
    }

    mut func ForwardArrayType(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        let curCnt = cnt.Get()
        var curIdx = idx + MANGLE_CHAR_LEN
        if (curIdx < mangled.Get().size) {
            curIdx = ForwardNumber(mangled, curIdx)
            if (curIdx < mangled.Get().size) {
                let endIdx = ForwardType(mangled, cnt, idx: curIdx)
                if (endIdx != curIdx) {
                    return endIdx
                }
            }
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    mut func ForwardGenericType(mangled: RtStringRef, cnt: IntRef, idx: Int64): Int64 {
        let nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
        if (nextIdx != idx + MANGLE_CHAR_LEN) {
            return nextIdx
        }
        return idx
    }

    mut func ForwardNumber(mangled: RtStringRef, idx: Int64): Int64 {
        var curIdx = idx
        while (curIdx < mangled.Get().size && IsAlnum(mangled.Get()[curIdx])) {
            curIdx++
        }
        if (curIdx < mangled.Get().size && mangled.Get()[curIdx] == b'_') {
            return curIdx + MANGLE_CHAR_LEN
        }
        return idx
    }

    mut func ForwardName(mangled: RtStringRef, idx!: Int64 = 0): Int64 {
        if (idx >= mangled.Get().size) {
            return idx
        }
        if (IsOperatorName(mangled.Get(), idx) || IsPropName(mangled.Get(), idx)) {
            return idx + MANGLE_SPECIAL_NAME_LEN
        }
        if (!IsDigit(mangled.Get()[idx])) {
            return idx
        }
        if (mangled.Get()[idx] == MANGLE_ANONYMOUS_PREFIX) {
            return idx + MANGLE_CHAR_LEN
        }
        var numberLen: Int64 = 0
        while (idx + numberLen < mangled.Get().size && IsDigit(mangled.Get()[idx + numberLen])) {
            numberLen++
        }
        var number: Int64 = 0
        var numberIdx: Int64 = 0
        while (numberIdx < numberLen) {
            number = number * 10 + Int64(mangled.Get()[idx + numberIdx] - b'0')
            if (number > 4294967295) {
                return idx
            }
            numberIdx++
        }
        if (idx + numberLen + number > mangled.Get().size) {
            return idx
        }
        return idx + numberLen + number
    }

    mut func TreeIdMapPop(from: IntRef, to: Int64): Unit {
        while (from.Get() > to) {
            treeIdMap.removeAt(treeIdMap.size - 1)
            from.Set(from.Get() - 1)
        }
    }

    mut func TreeIdMapErase(mangled: RtStringRef, cnt: IntRef, entityId: Int64, sid: Int64): RtString {
        treeIdMap.removeAt(entityId)
        UpdateCompressedName(mangled, sid, mangled.Get().size)
        cnt.Set(cnt.Get() - 1)
        return mangled.Get()
    }

    mut func TreeIdMapPushBack(mangled: RtStringRef, pos: TreePos): Bool {
        if (pos[1] == 0) {
            return treeIdMap.add(pos)
        } else if (pos[1] != 0 && !HasDuplicates(mangled, pos)) {
            return treeIdMap.add(pos)
        }
        return false
    }

    mut func TreeIdMapAssign(mangled: RtStringRef, mangledCopy: RtString, mapId: Int64, cnt: IntRef,
        eleInfo: TreePos): Unit {
        let idx = eleInfo[0]
        let nextIdx = eleInfo[1]
        if (mapId >= treeIdMap.size) {
            return
        }
        let old = treeIdMap[mapId]
        treeIdMap.Set(mapId, TreePos(old[0], nextIdx - idx))
        if (HasDuplicates(mangled, mapId)) {
            let copyRef = RtStringRef(mangledCopy)
            TreeIdMapErase(copyRef, cnt, mapId, idx)
            mangled.Set(copyRef.Get())
        }
    }

    mut func ForwardType(mangled: RtStringRef, cnt: IntRef, idx!: Int64 = 0): Int64 {
        if (idx >= mangled.Get().size) {
            return idx
        }
        let ch = mangled.Get()[idx]
        var nextIdx = idx
        let curCnt = cnt.Get()
        let mangledCopy = mangled.Get()
        let mapId = treeIdMap.size
        if (this.isRecord) {
            let pos = TreePos(idx, 0)
            let isPush = TreeIdMapPushBack(mangled, pos)
            cnt.Set(if (isPush) { cnt.Get() + 1 } else { cnt.Get() })
        }
        match (ch) {
            case b'C' =>
                nextIdx = ForwardClassType(mangled, cnt, idx)
            case b'R' =>
                nextIdx = ForwardClassType(mangled, cnt, idx)
            case b'N' =>
                nextIdx = ForwardClassType(mangled, cnt, idx)
            case b'F' =>
                if (idx + MANGLE_CHAR_LEN < mangled.Get().size &&
                    (mangled.Get()[idx + MANGLE_CHAR_LEN] == b'0' ||
                    mangled.Get()[idx + MANGLE_CHAR_LEN] == b'C')) {
                    nextIdx = ForwardFunctionType(mangled, cnt, idx)
                } else {
                    nextIdx = idx
                }
            case b'T' =>
                nextIdx = ForwardTupleType(mangled, cnt, idx)
            case b'P' =>
                nextIdx = ForwardCPointer(mangled, cnt, idx)
            case b'A' =>
                nextIdx = ForwardArrayType(mangled, cnt, idx)
            case b'V' =>
                nextIdx = ForwardArrayType(mangled, cnt, idx)
            case b'k' =>
                nextIdx = idx + MANGLE_CHAR_LEN
                if (this.isRecord) {
                    TreeIdMapPop(cnt, curCnt)
                }
                return nextIdx
            case b'G' =>
                nextIdx = ForwardGenericType(mangled, cnt, idx)
            case b'Y' =>
                nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
                var updateRes = CompressionUpdate(0, nextIdx, mangled.Get())
                if (nextIdx != idx) {
                    updateRes = UpdateCompressedName(mangled, idx)
                }
                if (this.isRecord) {
                    TreeIdMapPop(cnt, curCnt)
                }
                return if (updateRes.change == 0) { idx } else { updateRes.nextIndex }
            case _ =>
                if (IsPrimitiveType(ch)) {
                    nextIdx = ForwardPrimitiveType(mangled.Get(), idx)
                    if (this.isRecord) {
                        TreeIdMapPop(cnt, curCnt)
                    }
                    return nextIdx
                } else {
                    nextIdx = idx
                }
        }
        if (this.isRecord && nextIdx != idx) {
            let eleInfo = TreePos(idx, nextIdx)
            TreeIdMapAssign(mangled, mangledCopy, mapId, cnt, eleInfo)
        } else if (this.isRecord && nextIdx == idx) {
            TreeIdMapPop(cnt, curCnt)
        }
        return nextIdx
    }

    mut func ForwardTypes(mangled: RtStringRef, cnt: IntRef, startId!: Int64 = 0): Int64 {
        var idx = startId
        while (idx < mangled.Get().size && mangled.Get()[idx] != b'E') {
            let curIdx = ForwardType(mangled, cnt, idx: idx)
            if (curIdx == idx) {
                return curIdx
            }
            idx = curIdx
        }
        return idx
    }

    mut func IsCompressed(mangled: RtStringRef): Bool {
        if (mangled.Get().isEmpty()) {
            return false
        }
        var pos: Int64 = 0
        var found = mangled.Get().Find(RtLit(73), pos)
        while (found >= 0) {
            pos = found
            let nextIdx = ForwardNumber(mangled, pos + MANGLE_CHAR_LEN)
            if (nextIdx != pos + MANGLE_CHAR_LEN) {
                return true
            } else {
                pos += 1
            }
            found = mangled.Get().Find(RtLit(73), pos)
        }
        return false
    }

    mut func SpanningVarDeclTree(): Unit {
        this.isRecord = true
        var idx = this.currentIndex
        let updateRes = UpdateCompressedName(RtStringRef(this.decompressed), idx)
        this.decompressed = updateRes.value
        let change = updateRes.change
        if (this.decompressed.size > 0 && IsDigit(this.decompressed[idx])) {
            let decompressedRef = RtStringRef(this.decompressed)
            idx = ForwardName(decompressedRef, idx: idx)
            this.decompressed = decompressedRef.Get()
            if (idx != this.currentIndex && change == 0) {
                let pos = TreePos(this.currentIndex, idx - this.currentIndex)
                TreeIdMapPushBack(RtStringRef(this.decompressed), pos)
            }
        }
        this.isRecord = false
    }

    mut func SpanningFuncDeclTree(): Unit {
        var idx = this.currentIndex
        if (this.decompressed.size == 0 || (this.decompressed.size > 0 && this.decompressed[idx] == b'L')) {
            return
        }
        this.isRecord = true
        var decompressedRef = RtStringRef(this.decompressed)
        var updateRes = UpdateCompressedName(decompressedRef, idx)
        this.decompressed = decompressedRef.Get()
        var change = updateRes.change
        decompressedRef = RtStringRef(this.decompressed)
        if (IsDigit(this.decompressed[idx]) || IsOperatorName(this.decompressed, idx) || IsPropName(this.decompressed, idx)) {
            idx = ForwardName(decompressedRef, idx: idx)
            this.decompressed = decompressedRef.Get()
            if (idx != this.currentIndex && change == 0) {
                let funcPos = TreePos(this.currentIndex, this.decompressed.size - this.currentIndex)
                TreeIdMapPushBack(RtStringRef(this.decompressed), funcPos)
                let pos = TreePos(this.currentIndex, idx - this.currentIndex)
                TreeIdMapPushBack(RtStringRef(this.decompressed), pos)
            }
        }
        decompressedRef = RtStringRef(this.decompressed)
        updateRes = UpdateCompressedName(decompressedRef, idx)
        this.decompressed = decompressedRef.Get()
        change = updateRes.change
        if (idx < this.decompressed.size && this.decompressed[idx] == b'K') {
            let nextIdx = ForwardNumber(RtStringRef(this.decompressed), idx + MANGLE_CHAR_LEN)
            if (nextIdx != idx + MANGLE_CHAR_LEN && change == 0) {
                let pos = TreePos(idx, nextIdx - idx)
                TreeIdMapPushBack(RtStringRef(this.decompressed), pos)
                idx = nextIdx
            }
        }
        if (idx < this.decompressed.size && this.decompressed[idx] == b'I') {
            let cnt = IntRef(this.decompressed.arena, 0)
            let nextIdx = ForwardTypes(RtStringRef(this.decompressed), cnt, startId: idx + MANGLE_CHAR_LEN)
            if (nextIdx != idx + MANGLE_CHAR_LEN) {
                idx = nextIdx
            }
        }
        if (idx < this.decompressed.size && this.decompressed[idx] == b'H') {
            let cnt = IntRef(this.decompressed.arena, 0)
            let nextIdx = ForwardTypes(RtStringRef(this.decompressed), cnt, startId: idx + MANGLE_CHAR_LEN)
            if (nextIdx != idx + MANGLE_CHAR_LEN) {
                idx = nextIdx
            }
        }
        this.isRecord = false
    }

    mut func CJMangledDeCompression(isType!: Bool = false): RtString {
        if (!IsCompressed(RtStringRef(this.mangledName)) || this.mangledName.isEmpty()) {
            return this.mangledName
        }
        this.pid = 0
        var demangled = this.mangledName.SubStr(0)
        this.pid = StripCangjieAt(demangled, this.pid)
        if (demangled.isEmpty() || isType || !IsSamePrefix(RtStringRef(demangled), RtLit(240), this.pid)) {
            return this.mangledName
        }
        this.pid = StripCangjiePrefix(demangled, this.pid)
        demangled = this.mangledName.SubStr(this.pid)
        if (IsGlobalEncode(RtStringRef(demangled))) {
            return this.mangledName
        }

        if (IsDefaultParamFuncEncode(RtStringRef(demangled))) {
            this.pid += PREFIX_LEN
            demangled = demangled.SubStr(PREFIX_LEN)
            this.currentIndex = TryParsePath(demangled)
            if (IsCompressed(RtStringRef(this.decompressed))) {
                SpanningFuncDeclTree()
            }
            return if (this.pid == 0) { this.decompressed } else {
                this.mangledName.SubStr(0, this.pid) + this.decompressed
            }
        }
        if (!demangled.isEmpty() && demangled[0] == b'N') {
            this.pid += MANGLE_CHAR_LEN
            demangled = demangled.SubStr(MANGLE_CHAR_LEN)
            this.currentIndex = TryParsePath(demangled)
            let rest = if (this.currentIndex >= decompressed.size) { RtEmpty(decompressed.arena) } else {
                this.decompressed.SubStr(this.currentIndex)
            }
            if (!IsCompressed(RtStringRef(rest))) {
                return if (this.pid == 0) { this.decompressed } else {
                    this.mangledName.SubStr(0, this.pid) + this.decompressed
                }
            }
            if (IsVarDeclEncode(RtStringRef(rest))) {
                SpanningVarDeclTree()
            } else {
                SpanningFuncDeclTree()
            }
            return if (this.pid == 0) { this.decompressed } else {
                this.mangledName.SubStr(0, this.pid) + this.decompressed
            }
        }
        return demangled
    }

    mut func UpdateCompressedName(compressed: RtStringRef, idx: Int64): CompressionUpdate {
        var change: Int64 = 0
        var curScanIdx = idx
        if (curScanIdx >= compressed.Get().size) {
            return CompressionUpdate(change, curScanIdx, compressed.Get())
        }
        var ch = compressed.Get()[curScanIdx]
        while (ch == MANGLE_COMPRESS_PREFIX && !this.treeIdMap.isEmpty()) {
            let curIdx = ForwardNumber(compressed, curScanIdx + MANGLE_CHAR_LEN)
            if (curIdx != curScanIdx + MANGLE_CHAR_LEN) {
                let numberStr = compressed.Get().SubStr(curScanIdx + MANGLE_CHAR_LEN,
                    curIdx - curScanIdx - MANGLE_CHAR_LEN)
                let mapIdx = GetNumber(numberStr)
                if (mapIdx >= this.treeIdMap.size || this.treeIdMap[mapIdx][1] == 0) {
                    break
                }
                let curRest = if (curIdx < compressed.Get().size) { compressed.Get().SubStr(curIdx) } else {
                    RtEmpty(compressed.Get().arena)
                }
                let mapped = this.treeIdMap[mapIdx]
                compressed.Set(compressed.Get().SubStr(0, curScanIdx) +
                    compressed.Get().SubStr(mapped[0], mapped[1]) + curRest)
                change++
                curScanIdx += mapped[1]
                if (curScanIdx >= compressed.Get().size) {
                    break
                }
                ch = compressed.Get()[curScanIdx]
            } else {
                break
            }
        }
        return CompressionUpdate(change, curScanIdx, compressed.Get())
    }

    mut func UpdateCompressedName(compressed: RtStringRef, sid: Int64, eid: Int64): Int64 {
        var idx = sid
        var endId = eid
        while (idx < endId) {
            if (idx >= compressed.Get().size) {
                break
            }
            if (compressed.Get()[idx] == MANGLE_COMPRESS_PREFIX && !this.treeIdMap.isEmpty() &&
                idx + MANGLE_CHAR_LEN < compressed.Get().size) {
                let curIdx = ForwardNumber(compressed, idx + MANGLE_CHAR_LEN)
                if (curIdx == idx + MANGLE_CHAR_LEN) {
                    idx++
                    continue
                }
                let numberStr = compressed.Get().SubStr(idx + MANGLE_CHAR_LEN,
                    curIdx - idx - MANGLE_CHAR_LEN)
                let mapIdx = GetNumber(numberStr)
                if (mapIdx >= this.treeIdMap.size) {
                    return 0
                }
                if (this.treeIdMap[mapIdx][1] == 0) {
                    idx++
                    continue
                }
                let curRest = if (curIdx < compressed.Get().size) { compressed.Get().SubStr(curIdx) } else {
                    RtEmpty(compressed.Get().arena)
                }
                let mapped = this.treeIdMap[mapIdx]
                compressed.Set(compressed.Get().SubStr(0, idx) +
                    compressed.Get().SubStr(mapped[0], mapped[1]) + curRest)
                endId = compressed.Get().size
                idx += mapped[1]
            } else {
                idx++
            }
        }
        return 0
    }

    mut func TryExtendPath(mangled: RtStringRef, count: IntRef, idx: Int64, entityId: Int64, curMangled: RtString): Int64 {
        var isPush = false
        let mangledCopy = mangled.Get()
        var nextIdx = ForwardType(mangled, count, idx: idx + MANGLE_CHAR_LEN)
        var change = UpdateCompressedName(mangled, nextIdx).change
        let tyId = nextIdx
        if (nextIdx < mangled.Get().size && mangled.Get()[nextIdx] == b'U') {
            let fid = nextIdx
            nextIdx = ForwardFileNameNumber(mangled.Get(), fid + MANGLE_CHAR_LEN)
            if (nextIdx != fid + MANGLE_CHAR_LEN && change == 0) {
                let pos = TreePos(fid, nextIdx - fid)
                isPush = TreeIdMapPushBack(mangled, pos)
                count.Set(if (isPush) { count.Get() + 1 } else { count.Get() })
            }
            change = UpdateCompressedName(mangled, nextIdx).change
            if (nextIdx < mangled.Get().size && mangled.Get()[nextIdx] == b'K') {
                let lid = nextIdx
                nextIdx = ForwardNumber(mangled, nextIdx + MANGLE_CHAR_LEN)
                let eleInfo = TreePos(idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                if (nextIdx != lid + MANGLE_CHAR_LEN && change == 0) {
                    let pos = TreePos(lid, nextIdx - lid)
                    isPush = TreeIdMapPushBack(mangled, pos)
                    count.Set(if (isPush) { count.Get() + 1 } else { count.Get() })
                }
            } else {
                nextIdx = idx
            }
        } else {
            nextIdx = tyId
        }
        return nextIdx
    }

    mut func TryLambdaPath(mangled: RtStringRef, count: IntRef, idx: Int64, entityId: Int64, change: Int64): Int64 {
        let mangledCopy = mangled.Get()
        var nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
        if (nextIdx == mangled.Get().size - 1 && mangled.Get()[nextIdx] == b'E') {
            nextIdx = idx
        } else {
            nextIdx = if (nextIdx == idx + MANGLE_CHAR_LEN) { idx } else { nextIdx }
            if (nextIdx != idx || change > 0) {
                let eleInfo = TreePos(idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
            }
        }
        return nextIdx
    }

    mut func TryGenericPrefixPath(mangled: RtStringRef, count: IntRef, curMangled: RtString,
        rParams: (Int64, Int64, Int64)): Int64 {
        let mangledCopy = mangled.Get()
        let idx = rParams[0]
        let entityId = rParams[1]
        var nextIdx = rParams[2]
        nextIdx = ForwardTypes(mangled, count, startId: nextIdx + MANGLE_CHAR_LEN)
        if (nextIdx < mangled.Get().size && mangled.Get()[nextIdx] == b'E') {
            nextIdx++
            let eleInfo = TreePos(idx, nextIdx)
            TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
        } else if (nextIdx < mangled.Get().size && mangled.Get()[nextIdx] == b'H') {
            nextIdx = ForwardTypes(mangled, count, startId: nextIdx + MANGLE_CHAR_LEN)
            if (nextIdx < mangled.Get().size && mangled.Get()[nextIdx] == b'E') {
                nextIdx++
                let eleInfo = TreePos(idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
            } else if (nextIdx == mangled.Get().size) {
                let eleInfo = TreePos(idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
            } else {
                nextIdx = idx
            }
        } else {
            nextIdx = idx
        }
        return nextIdx
    }

    mut func TryNamePrefixPath(mangled: RtStringRef, count: IntRef, curMangled: RtString,
        rParams: (Int64, Int64, Int64)): Int64 {
        let mangledCopy = mangled.Get()
        let idx = rParams[0]
        let entityId = rParams[1]
        var change = rParams[2]
        var idFlag: Int64 = 0
        var nextIdx = ForwardName(mangled, idx: idx)
        let nameIdx = nextIdx
        if (nextIdx < mangled.Get().size && mangled.Get()[nextIdx] == b'K') {
            idFlag = nextIdx
            nextIdx = ForwardNumber(mangled, nextIdx + MANGLE_CHAR_LEN)
        }
        if (nextIdx != idx && change == 0) {
            let pos = TreePos(idx, nextIdx - idx)
            let isPush = TreeIdMapPushBack(mangled, pos)
            count.Set(if (isPush) { count.Get() + 1 } else { count.Get() })
        }
        if (nextIdx < mangled.Get().size) {
            idFlag = nextIdx
            change = UpdateCompressedName(mangled, idFlag).change
            nextIdx = idFlag
            if (mangled.Get()[nextIdx] == b'U') {
                nextIdx = ForwardFileNameNumber(mangled.Get(), nameIdx + MANGLE_CHAR_LEN)
                let eleInfo = TreePos(idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                if (nextIdx != idFlag + MANGLE_CHAR_LEN && change == 0) {
                    let pos = TreePos(idFlag, nextIdx - idFlag)
                    let isPush = TreeIdMapPushBack(mangled, pos)
                    count.Set(if (isPush) { count.Get() + 1 } else { count.Get() })
                }
                nextIdx = if (nextIdx == nameIdx + 1) { nameIdx } else { nextIdx }
            } else if (mangled.Get()[nextIdx] == b'I') {
                let genericParams = (idx, entityId, nextIdx)
                nextIdx = TryGenericPrefixPath(mangled, count, curMangled, genericParams)
            } else if (mangled.Get()[nextIdx] == b'H') {
                nextIdx = ForwardTypes(mangled, count, startId: nameIdx + MANGLE_CHAR_LEN)
                if (nextIdx < mangled.Get().size && mangled.Get()[nextIdx] == b'E') {
                    nextIdx++
                    let eleInfo = TreePos(idx, nextIdx)
                    TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                } else if (nextIdx == mangled.Get().size) {
                    let eleInfo = TreePos(idx, nextIdx)
                    TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                } else {
                    nextIdx = idx
                }
            } else {
                nextIdx = nameIdx
            }
        }
        if (nextIdx == nameIdx) {
            let old = this.treeIdMap[entityId]
            this.treeIdMap.Set(entityId, TreePos(old[0], nameIdx - idx))
            TreeIdMapPop(count, 1)
        }
        return nextIdx
    }

    mut func TryParsePath(mangledValue: RtString): Int64 {
        this.isRecord = true
        let mangled = RtStringRef(mangledValue)
        var idx: Int64 = 0
        while (idx < mangled.Get().size) {
            let ch = mangled.Get()[idx]
            var nextIdx = idx
            let updateRes = UpdateCompressedName(mangled, nextIdx)
            let change = updateRes.change
            let curMangled = mangled.Get()
            let pos = TreePos(idx, 0)
            let isPush = TreeIdMapPushBack(mangled, pos)
            let count = IntRef(mangled.Get().arena, if (isPush) { 1 } else { 0 })
            let entityId = this.treeIdMap.size - 1
            if (ch == MANGLE_ANONYMOUS_PREFIX) {
                nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
                if (nextIdx != idx + MANGLE_CHAR_LEN) {
                    let eleInfo = TreePos(idx, nextIdx)
                    TreeIdMapAssign(mangled, curMangled, entityId, count, eleInfo)
                }
                if (nextIdx == idx + MANGLE_CHAR_LEN || change > 0) {
                    nextIdx = idx
                }
            } else if (IsDigit(ch) || IsOperatorName(mangled.Get(), idx) || IsPropName(mangled.Get(), idx)) {
                let rParams = (idx, entityId, change)
                nextIdx = TryNamePrefixPath(mangled, count, curMangled, rParams)
            } else if (ch == b'X') {
                nextIdx = TryExtendPath(mangled, count, idx, entityId, curMangled)
            } else if (ch == b'L') {
                nextIdx = TryLambdaPath(mangled, count, idx, entityId, change)
            } else if (IsStdPkgName(mangled.Get(), idx)) {
                nextIdx = ForwardPackageName(mangled, count, idx)
                if (nextIdx != idx || change == 0) {
                    let eleInfo = TreePos(idx, nextIdx)
                    TreeIdMapAssign(mangled, curMangled, entityId, count, eleInfo)
                }
            }
            if (nextIdx != idx) {
                idx = nextIdx
            } else {
                TreeIdMapPop(count, 0)
                break
            }
        }
        this.decompressed = mangled.Get()
        this.isRecord = false
        return idx
    }
}
