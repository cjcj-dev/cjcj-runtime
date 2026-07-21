package rt.stackmap

// Canonical event kinds emitted by CJRT_StackMapDecode.
public let STACKMAP_EVENT_HEADER: UInt32 = 1u32
public let STACKMAP_EVENT_PROLOGUE: UInt32 = 2u32
public let STACKMAP_EVENT_ROW: UInt32 = 3u32
public let STACKMAP_EVENT_REG_ROOT: UInt32 = 4u32
public let STACKMAP_EVENT_SLOT_ROOT: UInt32 = 5u32
public let STACKMAP_EVENT_DERIVED_REG_ROOT: UInt32 = 6u32
public let STACKMAP_EVENT_DERIVED_SLOT_ROOT: UInt32 = 7u32
public let STACKMAP_EVENT_STACK_REG_ROOT: UInt32 = 8u32
public let STACKMAP_EVENT_STACK_SLOT_ROOT: UInt32 = 9u32

public let STACKMAP_OK: Int32 = 0
public let STACKMAP_INVALID_ARGUMENT: Int32 = 1
public let STACKMAP_TRUNCATED: Int32 = 2
public let STACKMAP_MALFORMED: Int32 = 3
public let STACKMAP_NO_SPACE: Int32 = 4

private let PURE_COMPRESSED_STACKMAP: UInt32 = 0u32
private let X86_UNIVERSAL_REG_COUNT: UInt32 = 16u32
private let X86_RIP_GAP: UInt32 = 1u32

@When[arch == "arm"]
private let SLOT_BYTES: Int64 = -4

@When[arch != "arm"]
private let SLOT_BYTES: Int64 = -8

@When[arch == "x86_64"]
private func registerNumber(bit: UInt32): UInt32 {
    return if (bit < X86_UNIVERSAL_REG_COUNT) { bit } else { bit + X86_RIP_GAP }
}

@When[arch != "x86_64"]
private func registerNumber(bit: UInt32): UInt32 {
    return bit
}

@When[arch == "x86_64"]
private func registerSlotCount(bit: UInt32): UInt32 {
    return if (bit < X86_UNIVERSAL_REG_COUNT) { 1u32 } else { 2u32 }
}

@When[arch != "x86_64"]
private func registerSlotCount(_: UInt32): UInt32 {
    return 1u32
}

@When[arch == "x86_64"]
private func isBaseRegister(bit: UInt32): Bool {
    return bit < X86_UNIVERSAL_REG_COUNT
}

@When[arch != "x86_64"]
private func isBaseRegister(_: UInt32): Bool {
    return true
}

@C
public struct StackMapEvent {
    public let kind: UInt32
    public let row: UInt32
    public let value0: Int64
    public let value1: Int64

    public init(kind: UInt32, row: UInt32, value0: Int64, value1: Int64) {
        this.kind = kind
        this.row = row
        this.value0 = value0
        this.value1 = value1
    }
}

private struct WordResult {
    let code: Int32
    let value: UInt32
    let nextBit: UInt64

    init(code: Int32, value: UInt32, nextBit: UInt64) {
        this.code = code
        this.value = value
        this.nextBit = nextBit
    }
}

private struct RootResult {
    let code: Int32
    let nextEvent: UInt64
    let baseRoots: UInt64

    init(code: Int32, nextEvent: UInt64, baseRoots: UInt64) {
        this.code = code
        this.nextEvent = nextEvent
        this.baseRoots = baseRoots
    }
}

private struct IndexSet {
    let reg: UInt32
    let slot: UInt32
    let line: UInt32
    let derived: UInt32
    let stackReg: UInt32
    let stackSlot: UInt32

    init(reg: UInt32, slot: UInt32, line: UInt32, derived: UInt32, stackReg: UInt32, stackSlot: UInt32) {
        this.reg = reg
        this.slot = slot
        this.line = line
        this.derived = derived
        this.stackReg = stackReg
        this.stackSlot = stackSlot
    }
}

private struct Layout {
    var stackMapData: UInt64
    var stackMapRecords: UInt32
    var stackMapRowBits: UInt32
    var regIndexBits: UInt32
    var slotIndexBits: UInt32
    var lineIndexBits: UInt32
    var derivedIndexBits: UInt32
    var stackRegIndexBits: UInt32
    var stackSlotIndexBits: UInt32
    var regData: UInt64
    var regRecords: UInt32
    var regBits: UInt32
    var slotData: UInt64
    var slotRecords: UInt32
    var slotBaseBits: UInt32
    var slotBitmapBits: UInt32
    var lineData: UInt64
    var lineRecords: UInt32
    var lineBits: UInt32
    var derivedData: UInt64
    var derivedRecords: UInt32

    init() {
        stackMapData = 0u64
        stackMapRecords = 0u32
        stackMapRowBits = 0u32
        regIndexBits = 0u32
        slotIndexBits = 0u32
        lineIndexBits = 0u32
        derivedIndexBits = 0u32
        stackRegIndexBits = 0u32
        stackSlotIndexBits = 0u32
        regData = 0u64
        regRecords = 0u32
        regBits = 0u32
        slotData = 0u64
        slotRecords = 0u32
        slotBaseBits = 0u32
        slotBitmapBits = 0u32
        lineData = 0u64
        lineRecords = 0u32
        lineBits = 0u32
        derivedData = 0u64
        derivedRecords = 0u32
    }
}

private func readBits(data: CPointer<UInt8>, size: UInt64, bit: UInt64, bitLen: UInt32): WordResult {
    if (bitLen > 32u32 || size > 0x1fffffffffffffffu64) {
        return WordResult(STACKMAP_MALFORMED, 0u32, bit)
    }
    let totalBits = size * 8u64
    if (bit > totalBits || UInt64(bitLen) > totalBits - bit) {
        return WordResult(STACKMAP_TRUNCATED, 0u32, bit)
    }

    var value = 0u32
    var i = 0u32
    while (i < bitLen) {
        let absolute = bit + UInt64(i)
        let byteValue = unsafe { (data + Int64(absolute >> 3u64)).read() }
        let oneBit = (UInt32(byteValue) >> UInt32(absolute & 7u64)) & 1u32
        value = value | (oneBit << i)
        i++
    }
    return WordResult(STACKMAP_OK, value, bit + UInt64(bitLen))
}

private func readVarInt(data: CPointer<UInt8>, size: UInt64, bit: UInt64): WordResult {
    let tag = readBits(data, size, bit, 4u32)
    if (tag.code != STACKMAP_OK) {
        return tag
    }
    if (tag.value <= 11u32) {
        return tag
    }

    let payloadBits = if (tag.value == 12u32) {
        8u32
    } else if (tag.value == 13u32) {
        16u32
    } else if (tag.value == 14u32) {
        24u32
    } else {
        32u32
    }
    return readBits(data, size, tag.nextBit, payloadBits)
}

private func emitEvent(events: CPointer<StackMapEvent>, capacity: UInt64, eventIndex: UInt64,
    kind: UInt32, row: UInt32, value0: Int64, value1: Int64): RootResult {
    if (!events.isNull()) {
        if (eventIndex >= capacity || eventIndex > UInt64(Int64.Max)) {
            return RootResult(STACKMAP_NO_SPACE, eventIndex, 0u64)
        }
        unsafe { (events + Int64(eventIndex)).write(StackMapEvent(kind, row, value0, value1)) }
    }
    return RootResult(STACKMAP_OK, eventIndex + 1u64, 0u64)
}

private func checkedEnd(start: UInt64, rows: UInt32, rowBits: UInt32, size: UInt64): WordResult {
    if (size > 0x1fffffffffffffffu64) {
        return WordResult(STACKMAP_MALFORMED, 0u32, start)
    }
    let totalBits = size * 8u64
    let span = UInt64(rows) * UInt64(rowBits)
    if (start > totalBits || span > totalBits - start) {
        return WordResult(STACKMAP_TRUNCATED, 0u32, start)
    }
    return WordResult(STACKMAP_OK, 0u32, start + span)
}

private func parseLayout(data: CPointer<UInt8>, size: UInt64, bitStart: UInt64,
    stackGrow: Bool): (Int32, Layout) {
    var layout = Layout()
    var cursor = bitStart

    let smRecords = readVarInt(data, size, cursor)
    if (smRecords.code != STACKMAP_OK) { return (smRecords.code, layout) }
    cursor = smRecords.nextBit
    layout.stackMapRecords = smRecords.value
    if (smRecords.value == 0u32) {
        return (STACKMAP_OK, layout)
    }
    let regIndexBits = readVarInt(data, size, cursor)
    if (regIndexBits.code != STACKMAP_OK) { return (regIndexBits.code, layout) }
    cursor = regIndexBits.nextBit
    let slotIndexBits = readVarInt(data, size, cursor)
    if (slotIndexBits.code != STACKMAP_OK) { return (slotIndexBits.code, layout) }
    cursor = slotIndexBits.nextBit
    let lineIndexBits = readVarInt(data, size, cursor)
    if (lineIndexBits.code != STACKMAP_OK) { return (lineIndexBits.code, layout) }
    cursor = lineIndexBits.nextBit
    let derivedIndexBits = readVarInt(data, size, cursor)
    if (derivedIndexBits.code != STACKMAP_OK) { return (derivedIndexBits.code, layout) }
    cursor = derivedIndexBits.nextBit

    var stackRegBits = 0u32
    var stackSlotBits = 0u32
    var padding: WordResult
    if (stackGrow) {
        let stackReg = readVarInt(data, size, cursor)
        if (stackReg.code != STACKMAP_OK) { return (stackReg.code, layout) }
        stackRegBits = stackReg.value
        cursor = stackReg.nextBit
        let stackSlot = readVarInt(data, size, cursor)
        if (stackSlot.code != STACKMAP_OK) { return (stackSlot.code, layout) }
        stackSlotBits = stackSlot.value
        cursor = stackSlot.nextBit
        padding = readVarInt(data, size, cursor)
    } else {
        padding = readVarInt(data, size, cursor)
    }
    if (padding.code != STACKMAP_OK) { return (padding.code, layout) }
    cursor = padding.nextBit

    if (regIndexBits.value > 32u32 || slotIndexBits.value > 32u32 || lineIndexBits.value > 32u32 ||
        derivedIndexBits.value > 32u32 || stackRegBits > 32u32 || stackSlotBits > 32u32) {
        return (STACKMAP_MALFORMED, layout)
    }
    let smRowBits64 = 32u64 + UInt64(regIndexBits.value) + UInt64(slotIndexBits.value) +
        UInt64(lineIndexBits.value) + UInt64(derivedIndexBits.value) + UInt64(stackRegBits) + UInt64(stackSlotBits)
    if (smRowBits64 > 0xffffffffu64) { return (STACKMAP_MALFORMED, layout) }
    let smData = cursor + UInt64(padding.value)
    if (smData < cursor) { return (STACKMAP_MALFORMED, layout) }
    let smEnd = checkedEnd(smData, smRecords.value, UInt32(smRowBits64), size)
    if (smEnd.code != STACKMAP_OK) { return (smEnd.code, layout) }

    layout.stackMapData = smData
    layout.stackMapRecords = smRecords.value
    layout.stackMapRowBits = UInt32(smRowBits64)
    layout.regIndexBits = regIndexBits.value
    layout.slotIndexBits = slotIndexBits.value
    layout.lineIndexBits = lineIndexBits.value
    layout.derivedIndexBits = derivedIndexBits.value
    layout.stackRegIndexBits = stackRegBits
    layout.stackSlotIndexBits = stackSlotBits

    cursor = smEnd.nextBit
    let regRecords = readVarInt(data, size, cursor)
    if (regRecords.code != STACKMAP_OK) { return (regRecords.code, layout) }
    cursor = regRecords.nextBit
    let regBits = readVarInt(data, size, cursor)
    if (regBits.code != STACKMAP_OK) { return (regBits.code, layout) }
    cursor = regBits.nextBit
    if (regBits.value > 32u32) { return (STACKMAP_MALFORMED, layout) }
    let regEnd = checkedEnd(cursor, regRecords.value, regBits.value, size)
    if (regEnd.code != STACKMAP_OK) { return (regEnd.code, layout) }
    layout.regData = cursor
    layout.regRecords = regRecords.value
    layout.regBits = regBits.value

    cursor = regEnd.nextBit
    let slotRecords = readVarInt(data, size, cursor)
    if (slotRecords.code != STACKMAP_OK) { return (slotRecords.code, layout) }
    cursor = slotRecords.nextBit
    let slotBaseBits = readVarInt(data, size, cursor)
    if (slotBaseBits.code != STACKMAP_OK) { return (slotBaseBits.code, layout) }
    cursor = slotBaseBits.nextBit
    let slotBitmapBits = readVarInt(data, size, cursor)
    if (slotBitmapBits.code != STACKMAP_OK) { return (slotBitmapBits.code, layout) }
    cursor = slotBitmapBits.nextBit
    if ((slotBaseBits.value != 8u32 && slotBaseBits.value != 16u32 && slotBaseBits.value != 32u32) ||
        slotBitmapBits.value > 0x7fffffffu32) {
        return (STACKMAP_MALFORMED, layout)
    }
    let slotRowBits64 = UInt64(slotBaseBits.value) + UInt64(slotBitmapBits.value)
    if (slotRowBits64 > 0xffffffffu64) { return (STACKMAP_MALFORMED, layout) }
    let slotEnd = checkedEnd(cursor, slotRecords.value, UInt32(slotRowBits64), size)
    if (slotEnd.code != STACKMAP_OK) { return (slotEnd.code, layout) }
    layout.slotData = cursor
    layout.slotRecords = slotRecords.value
    layout.slotBaseBits = slotBaseBits.value
    layout.slotBitmapBits = slotBitmapBits.value

    cursor = slotEnd.nextBit
    let lineRecords = readVarInt(data, size, cursor)
    if (lineRecords.code != STACKMAP_OK) { return (lineRecords.code, layout) }
    cursor = lineRecords.nextBit
    let lineBits = readVarInt(data, size, cursor)
    if (lineBits.code != STACKMAP_OK) { return (lineBits.code, layout) }
    cursor = lineBits.nextBit
    if (lineBits.value > 32u32) { return (STACKMAP_MALFORMED, layout) }
    let lineEnd = checkedEnd(cursor, lineRecords.value, lineBits.value, size)
    if (lineEnd.code != STACKMAP_OK) { return (lineEnd.code, layout) }
    layout.lineData = cursor
    layout.lineRecords = lineRecords.value
    layout.lineBits = lineBits.value

    cursor = lineEnd.nextBit
    let derivedRecords = readVarInt(data, size, cursor)
    if (derivedRecords.code != STACKMAP_OK) { return (derivedRecords.code, layout) }
    cursor = derivedRecords.nextBit
    let derivedRowBits = UInt64(regIndexBits.value) + UInt64(slotIndexBits.value)
    if (derivedRowBits > 0xffffffffu64) { return (STACKMAP_MALFORMED, layout) }
    let derivedEnd = checkedEnd(cursor, derivedRecords.value, UInt32(derivedRowBits), size)
    if (derivedEnd.code != STACKMAP_OK) { return (derivedEnd.code, layout) }
    layout.derivedData = cursor
    layout.derivedRecords = derivedRecords.value
    return (STACKMAP_OK, layout)
}

private func readIndexSet(data: CPointer<UInt8>, size: UInt64, layout: Layout, row: UInt32): (Int32, UInt32, IndexSet) {
    let empty = IndexSet(0u32, 0u32, 0u32, 0u32, 0u32, 0u32)
    var cursor = layout.stackMapData + UInt64(row) * UInt64(layout.stackMapRowBits)
    let pc = readBits(data, size, cursor, 32u32)
    if (pc.code != STACKMAP_OK) { return (pc.code, 0u32, empty) }
    cursor = pc.nextBit
    let reg = readBits(data, size, cursor, layout.regIndexBits)
    if (reg.code != STACKMAP_OK) { return (reg.code, 0u32, empty) }
    cursor = reg.nextBit
    let slot = readBits(data, size, cursor, layout.slotIndexBits)
    if (slot.code != STACKMAP_OK) { return (slot.code, 0u32, empty) }
    cursor = slot.nextBit
    let line = readBits(data, size, cursor, layout.lineIndexBits)
    if (line.code != STACKMAP_OK) { return (line.code, 0u32, empty) }
    cursor = line.nextBit
    let derived = readBits(data, size, cursor, layout.derivedIndexBits)
    if (derived.code != STACKMAP_OK) { return (derived.code, 0u32, empty) }
    cursor = derived.nextBit
    let stackReg = readBits(data, size, cursor, layout.stackRegIndexBits)
    if (stackReg.code != STACKMAP_OK) { return (stackReg.code, 0u32, empty) }
    cursor = stackReg.nextBit
    let stackSlot = readBits(data, size, cursor, layout.stackSlotIndexBits)
    if (stackSlot.code != STACKMAP_OK) { return (stackSlot.code, 0u32, empty) }
    return (STACKMAP_OK, pc.value, IndexSet(reg.value, slot.value, line.value, derived.value,
        stackReg.value, stackSlot.value))
}

private func readTableRow(data: CPointer<UInt8>, size: UInt64, tableData: UInt64,
    recordCount: UInt32, rowBits: UInt32, oneBasedIndex: UInt32): WordResult {
    if (oneBasedIndex == 0u32) {
        return WordResult(STACKMAP_OK, 0u32, tableData)
    }
    if (oneBasedIndex > recordCount) {
        return WordResult(STACKMAP_MALFORMED, 0u32, tableData)
    }
    let bit = tableData + UInt64(oneBasedIndex - 1u32) * UInt64(rowBits)
    return readBits(data, size, bit, rowBits)
}

private func decodeRegRoots(data: CPointer<UInt8>, size: UInt64, layout: Layout, regIndex: UInt32,
    kind: UInt32, stackMapRow: UInt32, derivedBase: UInt64, events: CPointer<StackMapEvent>,
    capacity: UInt64, eventStart: UInt64): RootResult {
    if (regIndex == 0u32) {
        return RootResult(STACKMAP_OK, eventStart, 0u64)
    }
    let bitsResult = readTableRow(data, size, layout.regData, layout.regRecords, layout.regBits, regIndex)
    if (bitsResult.code != STACKMAP_OK) {
        return RootResult(bitsResult.code, eventStart, 0u64)
    }

    var bitMap = bitsResult.value
    var bit = 0u32
    var eventIndex = eventStart
    var baseRoots = 0u64
    while (bitMap != 0u32 && bit < layout.regBits) {
        if ((bitMap & 1u32) != 0u32) {
            let reg = registerNumber(bit)
            let slots = registerSlotCount(bit)
            var subSlot = 0u32
            while (subSlot < slots) {
                let value0 = if (kind == STACKMAP_EVENT_DERIVED_REG_ROOT) {
                    Int64(derivedBase)
                } else {
                    Int64(reg)
                }
                let value1 = if (kind == STACKMAP_EVENT_DERIVED_REG_ROOT) {
                    Int64(reg * 2u32 + subSlot)
                } else {
                    Int64(subSlot)
                }
                let emitted = emitEvent(events, capacity, eventIndex, kind, stackMapRow, value0, value1)
                if (emitted.code != STACKMAP_OK) {
                    return RootResult(emitted.code, emitted.nextEvent, baseRoots)
                }
                eventIndex = emitted.nextEvent
                subSlot++
            }
            if (isBaseRegister(bit)) {
                baseRoots++
            }
        }
        bitMap = bitMap >> 1u32
        bit++
    }
    return RootResult(STACKMAP_OK, eventIndex, baseRoots)
}

private func signedBase(value: UInt32, bits: UInt32): Int64 {
    if (bits == 8u32 && (value & 0x80u32) != 0u32) {
        return Int64(value) - 0x100i64
    }
    if (bits == 16u32 && (value & 0x8000u32) != 0u32) {
        return Int64(value) - 0x10000i64
    }
    if (bits == 32u32 && (value & 0x80000000u32) != 0u32) {
        return Int64(value) - 0x100000000i64
    }
    return Int64(value)
}

private func emitSlot(events: CPointer<StackMapEvent>, capacity: UInt64, eventIndex: UInt64,
    kind: UInt32, row: UInt32, derivedBase: UInt64, bias: Int64): RootResult {
    let value0 = if (kind == STACKMAP_EVENT_DERIVED_SLOT_ROOT) { Int64(derivedBase) } else { bias }
    let value1 = if (kind == STACKMAP_EVENT_DERIVED_SLOT_ROOT) { bias } else { 0i64 }
    let emitted = emitEvent(events, capacity, eventIndex, kind, row, value0, value1)
    if (emitted.code != STACKMAP_OK) {
        return emitted
    }
    return RootResult(STACKMAP_OK, emitted.nextEvent, 1u64)
}

private func decodeSlotRoots(data: CPointer<UInt8>, size: UInt64, layout: Layout, slotIndex: UInt32,
    format: UInt32, kind: UInt32, stackMapRow: UInt32, derivedBase: UInt64,
    events: CPointer<StackMapEvent>, capacity: UInt64, eventStart: UInt64): RootResult {
    if (slotIndex == 0u32) {
        return RootResult(STACKMAP_OK, eventStart, 0u64)
    }
    if (slotIndex > layout.slotRecords) {
        return RootResult(STACKMAP_MALFORMED, eventStart, 0u64)
    }
    let rowStart = layout.slotData + UInt64(slotIndex - 1u32) *
        (UInt64(layout.slotBaseBits) + UInt64(layout.slotBitmapBits))
    let baseResult = readBits(data, size, rowStart, layout.slotBaseBits)
    if (baseResult.code != STACKMAP_OK) {
        return RootResult(baseResult.code, eventStart, 0u64)
    }
    var baseBias = signedBase(baseResult.value, layout.slotBaseBits)
    var cursor = baseResult.nextBit
    var remain = layout.slotBitmapBits
    var eventIndex = eventStart
    var roots = 0u64

    if (format == PURE_COMPRESSED_STACKMAP) {
        var logicalSlot = 0u64
        while (remain != 0u32) {
            let chunkBits = if (remain < 32u32) { remain } else { 32u32 }
            let chunkResult = readBits(data, size, cursor, chunkBits)
            if (chunkResult.code != STACKMAP_OK) {
                return RootResult(chunkResult.code, eventIndex, roots)
            }
            var chunk = chunkResult.value
            var bit = 0u32
            while (chunk != 0u32 && bit < chunkBits) {
                if ((chunk & 1u32) != 0u32) {
                    let bias = baseBias + Int64(logicalSlot + UInt64(bit)) * SLOT_BYTES
                    let emitted = emitSlot(events, capacity, eventIndex, kind, stackMapRow, derivedBase, bias)
                    if (emitted.code != STACKMAP_OK) { return RootResult(emitted.code, emitted.nextEvent, roots) }
                    eventIndex = emitted.nextEvent
                    roots++
                }
                chunk = chunk >> 1u32
                bit++
            }
            logicalSlot += UInt64(chunkBits)
            cursor = chunkResult.nextBit
            remain -= chunkBits
        }
        return RootResult(STACKMAP_OK, eventIndex, roots)
    }

    while (remain != 0u32) {
        let pureTag = readBits(data, size, cursor, 1u32)
        if (pureTag.code != STACKMAP_OK) { return RootResult(pureTag.code, eventIndex, roots) }
        cursor = pureTag.nextBit
        remain--
        if (pureTag.value != 0u32) {
            let pureBits = if (remain < 31u32) { remain } else { 31u32 }
            let rawResult = readBits(data, size, cursor, pureBits)
            if (rawResult.code != STACKMAP_OK) { return RootResult(rawResult.code, eventIndex, roots) }
            var raw = rawResult.value
            var bit = 0u32
            while (raw != 0u32 && bit < pureBits) {
                if ((raw & 1u32) != 0u32) {
                    let bias = baseBias + Int64(bit) * SLOT_BYTES
                    let emitted = emitSlot(events, capacity, eventIndex, kind, stackMapRow, derivedBase, bias)
                    if (emitted.code != STACKMAP_OK) { return RootResult(emitted.code, emitted.nextEvent, roots) }
                    eventIndex = emitted.nextEvent
                    roots++
                }
                raw = raw >> 1u32
                bit++
            }
            cursor = rawResult.nextBit
            remain -= pureBits
            baseBias += 31i64 * SLOT_BYTES
        } else {
            if (remain < 5u32) {
                break
            }
            let allRef = readBits(data, size, cursor, 1u32)
            if (allRef.code != STACKMAP_OK) { return RootResult(allRef.code, eventIndex, roots) }
            cursor = allRef.nextBit
            remain--
            let count = readVarInt(data, size, cursor)
            if (count.code != STACKMAP_OK) { return RootResult(count.code, eventIndex, roots) }
            let used = count.nextBit - cursor
            if (used > UInt64(remain)) { return RootResult(STACKMAP_MALFORMED, eventIndex, roots) }
            cursor = count.nextBit
            remain -= UInt32(used)
            if (count.value == 0u32) {
                break
            }
            let bitCount = UInt64(count.value) * 31u64
            if (allRef.value != 0u32) {
                var bit = 0u64
                while (bit < bitCount) {
                    let bias = baseBias + Int64(bit) * SLOT_BYTES
                    let emitted = emitSlot(events, capacity, eventIndex, kind, stackMapRow, derivedBase, bias)
                    if (emitted.code != STACKMAP_OK) { return RootResult(emitted.code, emitted.nextEvent, roots) }
                    eventIndex = emitted.nextEvent
                    roots++
                    bit++
                }
            }
            baseBias += Int64(bitCount) * SLOT_BYTES
        }
    }
    return RootResult(STACKMAP_OK, eventIndex, roots)
}

private func decodeDerived(data: CPointer<UInt8>, size: UInt64, layout: Layout, derivedIndex: UInt32,
    baseRoots: UInt64, format: UInt32, stackMapRow: UInt32, events: CPointer<StackMapEvent>,
    capacity: UInt64, eventStart: UInt64): RootResult {
    if (derivedIndex == 0u32 || baseRoots == 0u64) {
        return RootResult(STACKMAP_OK, eventStart, 0u64)
    }
    if (derivedIndex > layout.derivedRecords || baseRoots > UInt64(layout.derivedRecords - derivedIndex + 1u32)) {
        return RootResult(STACKMAP_MALFORMED, eventStart, 0u64)
    }

    var baseOrdinal = 0u64
    var eventIndex = eventStart
    let derivedRowBits = layout.regIndexBits + layout.slotIndexBits
    while (baseOrdinal < baseRoots) {
        var cursor = layout.derivedData + (UInt64(derivedIndex - 1u32) + baseOrdinal) * UInt64(derivedRowBits)
        let regIndex = readBits(data, size, cursor, layout.regIndexBits)
        if (regIndex.code != STACKMAP_OK) { return RootResult(regIndex.code, eventIndex, 0u64) }
        cursor = regIndex.nextBit
        let slotIndex = readBits(data, size, cursor, layout.slotIndexBits)
        if (slotIndex.code != STACKMAP_OK) { return RootResult(slotIndex.code, eventIndex, 0u64) }

        let regResult = decodeRegRoots(data, size, layout, regIndex.value, STACKMAP_EVENT_DERIVED_REG_ROOT,
            stackMapRow, baseOrdinal, events, capacity, eventIndex)
        if (regResult.code != STACKMAP_OK) { return regResult }
        eventIndex = regResult.nextEvent
        let slotResult = decodeSlotRoots(data, size, layout, slotIndex.value, format,
            STACKMAP_EVENT_DERIVED_SLOT_ROOT, stackMapRow, baseOrdinal, events, capacity, eventIndex)
        if (slotResult.code != STACKMAP_OK) { return slotResult }
        eventIndex = slotResult.nextEvent
        baseOrdinal++
    }
    return RootResult(STACKMAP_OK, eventIndex, 0u64)
}

private func writeCount(eventCount: CPointer<UInt64>, count: UInt64): Unit {
    unsafe { eventCount.write(count) }
}

// Decode one function's compressed stack-map byte stream. A null events pointer is a
// count-only query; otherwise capacity is measured in StackMapEvent elements.
@C
public func CJRT_StackMapDecode(data: CPointer<UInt8>, size: UInt64, stackGrowFlag: UInt32,
    events: CPointer<StackMapEvent>, capacity: UInt64, eventCount: CPointer<UInt64>): Int32 {
    if (data.isNull() || eventCount.isNull() || (stackGrowFlag != 0u32 && stackGrowFlag != 1u32)) {
        return STACKMAP_INVALID_ARGUMENT
    }
    writeCount(eventCount, 0u64)

    let stackSize = readVarInt(data, size, 0u64)
    if (stackSize.code != STACKMAP_OK) { return stackSize.code }
    let format = readVarInt(data, size, stackSize.nextBit)
    if (format.code != STACKMAP_OK) { return format.code }

    var eventIndex = 0u64
    let headerEvent = emitEvent(events, capacity, eventIndex, STACKMAP_EVENT_HEADER, 0u32,
        Int64(stackSize.value), Int64(format.value))
    if (headerEvent.code != STACKMAP_OK) { writeCount(eventCount, headerEvent.nextEvent); return headerEvent.code }
    eventIndex = headerEvent.nextEvent

    let prologueMap = readVarInt(data, size, format.nextBit)
    if (prologueMap.code != STACKMAP_OK) { writeCount(eventCount, eventIndex); return prologueMap.code }
    var prologueBits = prologueMap.value
    var prologueReg = 0u32
    var prologueCursor = prologueMap.nextBit
    while (prologueBits != 0u32) {
        if ((prologueBits & 1u32) != 0u32) {
            let offset = readVarInt(data, size, prologueCursor)
            if (offset.code != STACKMAP_OK) { writeCount(eventCount, eventIndex); return offset.code }
            prologueCursor = offset.nextBit
            let emitted = emitEvent(events, capacity, eventIndex, STACKMAP_EVENT_PROLOGUE, 0u32,
                Int64(prologueReg), Int64(offset.value))
            if (emitted.code != STACKMAP_OK) { writeCount(eventCount, emitted.nextEvent); return emitted.code }
            eventIndex = emitted.nextEvent
        }
        prologueBits = prologueBits >> 1u32
        prologueReg++
    }

    let parsed = parseLayout(data, size, prologueCursor, stackGrowFlag == 1u32)
    if (parsed[0] != STACKMAP_OK) { writeCount(eventCount, eventIndex); return parsed[0] }
    let layout = parsed[1]

    var row = 0u32
    while (row < layout.stackMapRecords) {
        let decoded = readIndexSet(data, size, layout, row)
        if (decoded[0] != STACKMAP_OK) { writeCount(eventCount, eventIndex); return decoded[0] }
        let pc = decoded[1]
        let indices = decoded[2]
        if (indices.reg == 0u32 && indices.slot == 0u32 && indices.line == 0u32 &&
            indices.stackReg == 0u32 && indices.stackSlot == 0u32) {
            row++
            continue
        }

        var lineNumber = 0u32
        if (indices.line != 0u32) {
            let lineResult = readTableRow(data, size, layout.lineData, layout.lineRecords,
                layout.lineBits, indices.line)
            if (lineResult.code != STACKMAP_OK) { writeCount(eventCount, eventIndex); return lineResult.code }
            lineNumber = lineResult.value
        }
        let rowEvent = emitEvent(events, capacity, eventIndex, STACKMAP_EVENT_ROW, pc,
            Int64(pc), Int64(lineNumber))
        if (rowEvent.code != STACKMAP_OK) { writeCount(eventCount, rowEvent.nextEvent); return rowEvent.code }
        eventIndex = rowEvent.nextEvent

        let regs = decodeRegRoots(data, size, layout, indices.reg, STACKMAP_EVENT_REG_ROOT,
            pc, 0u64, events, capacity, eventIndex)
        if (regs.code != STACKMAP_OK) { writeCount(eventCount, regs.nextEvent); return regs.code }
        eventIndex = regs.nextEvent
        let slots = decodeSlotRoots(data, size, layout, indices.slot, format.value,
            STACKMAP_EVENT_SLOT_ROOT, pc, 0u64, events, capacity, eventIndex)
        if (slots.code != STACKMAP_OK) { writeCount(eventCount, slots.nextEvent); return slots.code }
        eventIndex = slots.nextEvent

        let derived = decodeDerived(data, size, layout, indices.derived, regs.baseRoots + slots.baseRoots,
            format.value, pc, events, capacity, eventIndex)
        if (derived.code != STACKMAP_OK) { writeCount(eventCount, derived.nextEvent); return derived.code }
        eventIndex = derived.nextEvent

        let stackRegs = decodeRegRoots(data, size, layout, indices.stackReg, STACKMAP_EVENT_STACK_REG_ROOT,
            pc, 0u64, events, capacity, eventIndex)
        if (stackRegs.code != STACKMAP_OK) { writeCount(eventCount, stackRegs.nextEvent); return stackRegs.code }
        eventIndex = stackRegs.nextEvent
        let stackSlots = decodeSlotRoots(data, size, layout, indices.stackSlot, format.value,
            STACKMAP_EVENT_STACK_SLOT_ROOT, pc, 0u64, events, capacity, eventIndex)
        if (stackSlots.code != STACKMAP_OK) { writeCount(eventCount, stackSlots.nextEvent); return stackSlots.code }
        eventIndex = stackSlots.nextEvent
        row++
    }

    writeCount(eventCount, eventIndex)
    return STACKMAP_OK
}
