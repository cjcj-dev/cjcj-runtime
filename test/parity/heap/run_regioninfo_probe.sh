#!/usr/bin/env bash
# Builds the C++ layout oracle and the selfhost rt.base -> rt.sync ->
# rt.heap.allocator chain, asserts every UnitMetadata offset, and runs RegionInfo.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RT_LIB="$RUNTIME_TOOLCHAIN_RT_LIB"
export cjHeapSize=${cjHeapSize:-24GB}

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_regioninfo_probe.XXXXXX")
OUT="$IMP/regioninfo_probe"
REF="$IMP/regioninfo_layout_ref"
INIT_REF="$IMP/regioninfo_init_ref"
CPP_INIT_TRANSCRIPT="$IMP/regioninfo_init.cpp.txt"
CJ_INIT_TRANSCRIPT="$IMP/regioninfo_init.cj.txt"
STUB_OUT="$IMP/regioninfo_stub_link_probe"
ABORT_OUT="$IMP/regioninfo_abort_probe"
PROBE_SRC="$IMP/rt.heap.allocator.probe"
INIT_SRC="$IMP/rt.heap.allocator.initcheck"
NOHEAP_SRC="$IMP/rt.heap.allocator.noheap"
NOHEAP_TEMPS="$IMP/regioninfo_noheap_temps"
NOHEAP_ARCHIVE="$IMP/regioninfo_noheap.a"
NOHEAP_OUT="$IMP/regioninfo_noheap_probe"
NOHEAP_PRE_BC="$IMP/regioninfo_noheap.pre.bc"
NOHEAP_CALLGRAPH="$IMP/regioninfo_noheap.callgraph.txt"
NOHEAP_CALLS="$IMP/regioninfo_noheap.calls.tsv"
NOHEAP_SYMBOLS="$IMP/regioninfo_noheap.closure.symbols"
NOHEAP_CLOSURE_IR="$IMP/regioninfo_noheap.closure.ll"
NOHEAP_CLOSURE_OBJECT="$IMP/regioninfo_noheap.closure.objdump"
trap 'rm -rf "$IMP"' EXIT

g++ -std=c++14 -O2 "$ROOT/test/parity/heap/regioninfo_layout_ref.cpp" -o "$REF"
CPP_LAYOUT=$($REF)

CJTHREAD_INCLUDE_ARGS=()
while IFS= read -r include_dir; do
    CJTHREAD_INCLUDE_ARGS+=("-I$include_dir")
done < <(find /root/cj_build/cangjie_runtime/runtime/src/CJThread/src -type d)
g++ -std=c++14 -O2 \
    -I/root/cj_build/cangjie_runtime/runtime/src \
    -I/root/cj_build/cangjie_runtime/runtime/third_party/third_party_bounds_checking_function/include \
    "${CJTHREAD_INCLUDE_ARGS[@]}" \
    "$ROOT/test/parity/heap/regioninfo_init_ref.cpp" \
    -L"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" \
    -Wl,-rpath,"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" \
    -lcangjie-runtime -lboundscheck -lsecurec -lpthread -ldl -o "$INIT_REF"
"$INIT_REF" > "$CPP_INIT_TRANSCRIPT"
CPP_ACTUAL_LAYOUT=$(grep '^REGIONINFO_LAYOUT ' "$CPP_INIT_TRANSCRIPT")
if [[ "$CPP_ACTUAL_LAYOUT" != "$CPP_LAYOUT" ]]; then
    echo "REGIONINFO C++ ACTUAL LAYOUT ASSERT FAIL" >&2
    echo "actual: $CPP_ACTUAL_LAYOUT" >&2
    echo "oracle: $CPP_LAYOUT" >&2
    exit 1
fi

for pkg in rt.base rt.sync rt.heap.allocator; do
    (cd "$IMP" && "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$IMP" --output-dir "$IMP" -o "lib$pkg.a")
done

g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$IMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$IMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$IMP/Atomic.o"

cp -a "$ROOT/src/rt.heap.allocator" "$NOHEAP_SRC"
cp "$ROOT/test/parity/heap/regioninfo_noheap_probe.cj" "$NOHEAP_SRC/RegionInfoNoHeapProbe.cj"
mkdir -p "$NOHEAP_TEMPS"
(cd "$IMP" && "$SELFHOST_CJC" --package "$NOHEAP_SRC" --output-type=staticlib --import-path "$IMP" \
    --save-temps "$NOHEAP_TEMPS" --int-overflow wrapping -Woff unused \
    --output-dir "$IMP" -o "$(basename "$NOHEAP_ARCHIVE")")

# Derive the complete static closure from linked pre-opt BC, where calls still
# name their direct callees, then extract exactly those definitions from every
# final BC and object emitted for the dedicated package.
PRE_BC=()
for bc in "$NOHEAP_TEMPS"/[0-9]*-rt.heap.allocator.bc; do
    if [[ "$bc" != *.opt.bc ]]; then
        PRE_BC+=("$bc")
    fi
done
"$CANGJIE_HOME/third_party/llvm/bin/llvm-link" "${PRE_BC[@]}" -o "$NOHEAP_PRE_BC"
"$CANGJIE_HOME/third_party/llvm/bin/opt" -passes=print-callgraph -disable-output \
    "$NOHEAP_PRE_BC" 2> "$NOHEAP_CALLGRAPH"
awk '
/^Call graph node for function:/ {
    line = $0
    sub(/^.*function: '\''/, "", line)
    sub(/'\''.*$/, "", line)
    current = line
    next
}
/calls function '\''/ {
    line = $0
    sub(/^.*calls function '\''/, "", line)
    sub(/'\''.*$/, "", line)
    if (current != "") print current "\t" line
}
' "$NOHEAP_CALLGRAPH" > "$NOHEAP_CALLS"

ROOT_SYMBOLS=()
while IFS= read -r symbol; do
    ROOT_SYMBOLS+=("$symbol")
done < <(awk -F '\t' '$1 ~ /RegionInfoNoHeapRoot/ {print $1}' "$NOHEAP_CALLS" | sort -u)
if [[ ${#ROOT_SYMBOLS[@]} -ne 1 ]]; then
    echo "REGIONINFO_NOHEAP FAIL (expected one root symbol, got ${#ROOT_SYMBOLS[@]})" >&2
    exit 1
fi

declare -A SEEN=()
QUEUE=("${ROOT_SYMBOLS[0]}")
SEEN["${ROOT_SYMBOLS[0]}"]=1
while [[ ${#QUEUE[@]} -gt 0 ]]; do
    CURRENT=${QUEUE[0]}
    QUEUE=("${QUEUE[@]:1}")
    while IFS=$'\t' read -r _ callee; do
        if [[ -n "$callee" && -z ${SEEN["$callee"]+present} ]]; then
            SEEN["$callee"]=1
            QUEUE+=("$callee")
        fi
    done < <(awk -F '\t' -v key="$CURRENT" '$1 == key {print}' "$NOHEAP_CALLS")
done
for symbol in "${!SEEN[@]}"; do
    printf '%s\n' "$symbol"
done | sort > "$NOHEAP_SYMBOLS"

: > "$NOHEAP_CLOSURE_IR"
FINAL_BC_COUNT=0
for final_bc in "$NOHEAP_TEMPS"/[0-9]*-rt.heap.allocator.opt.bc; do
    module_ir="$IMP/$(basename "${final_bc%.bc}").ll"
    closure_ir="$module_ir.closure"
    "$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$final_bc" -o "$module_ir"
    awk -v symbols="$NOHEAP_SYMBOLS" '
    BEGIN { while ((getline symbol < symbols) > 0) keep[symbol] = 1 }
    /^define / {
        name = $0
        sub(/^[^@]*@/, "", name)
        sub(/\(.*/, "", name)
        gsub(/^"|"$/, "", name)
        emit = (name in keep)
    }
    emit { print }
    ' "$module_ir" > "$closure_ir"
    if grep -q '^define ' "$closure_ir"; then
        FINAL_BC_COUNT=$((FINAL_BC_COUNT + 1))
        cat "$closure_ir" >> "$NOHEAP_CLOSURE_IR"
    fi
done

: > "$NOHEAP_CLOSURE_OBJECT"
OBJECT_COUNT=0
for object in "$NOHEAP_TEMPS"/[0-9]*-rt.heap.allocator.o; do
    object_dump="$IMP/$(basename "$object").objdump"
    closure_dump="$object_dump.closure"
    objdump -dr "$object" > "$object_dump"
    awk -v symbols="$NOHEAP_SYMBOLS" '
    BEGIN { while ((getline symbol < symbols) > 0) keep[symbol] = 1 }
    /^[[:xdigit:]]+ <.*>:/ {
        name = $0
        sub(/^.*</, "", name)
        sub(/>.*$/, "", name)
        emit = (name in keep)
    }
    emit { print }
    ' "$object_dump" > "$closure_dump"
    if [[ -s "$closure_dump" ]]; then
        OBJECT_COUNT=$((OBJECT_COUNT + 1))
        cat "$closure_dump" >> "$NOHEAP_CLOSURE_OBJECT"
    fi
done

if [[ $FINAL_BC_COUNT -eq 0 || $OBJECT_COUNT -eq 0 || ! -s "$NOHEAP_CLOSURE_IR" ||
      ! -s "$NOHEAP_CLOSURE_OBJECT" ]]; then
    echo "REGIONINFO_NOHEAP FAIL (empty closure final BC/object coverage)" >&2
    exit 1
fi
if ! grep -q 'RegionInfoNoHeapRoot' "$NOHEAP_CLOSURE_IR" ||
   ! grep -q 'RegionInfoNoHeapRoot' "$NOHEAP_CLOSURE_OBJECT"; then
    echo "REGIONINFO_NOHEAP FAIL (root absent from closure artifacts)" >&2
    exit 1
fi

FORBIDDEN_PATTERN='llvm\.cj\.alloca\.generic|MCC_New|CJ_MCC_New|RawArrayAllocate|std\.core[:.]String|std\.core[:.]Array|ArrayList|HashMap|Create[A-Za-z]*Exception|ThrowException|closure'
FORBIDDEN_REFS=$( (grep -Eih "$FORBIDDEN_PATTERN" \
    "$NOHEAP_CLOSURE_IR" "$NOHEAP_CLOSURE_OBJECT" || true) | wc -l )
MCC_NEW_REFS=$( (grep -Eih 'MCC_New|CJ_MCC_New' \
    "$NOHEAP_CLOSURE_IR" "$NOHEAP_CLOSURE_OBJECT" || true) | wc -l )
if [[ $FORBIDDEN_REFS -ne 0 || $MCC_NEW_REFS -ne 0 ]]; then
    echo "REGIONINFO_NOHEAP FAIL (managed allocation/reference in closure artifacts)" >&2
    grep -Ein "$FORBIDDEN_PATTERN" "$NOHEAP_CLOSURE_IR" "$NOHEAP_CLOSURE_OBJECT" >&2 || true
    exit 1
fi

# Compile the deferred interface probe in the owning package so CPointer<RegionInfo>
# extension methods remain receiver-faithful. The selfhost CJO importer does not
# re-export extensions of core CPointer to a standalone package.
STUB_SRC="$IMP/rt.heap.allocator.stubcheck"
cp -a "$ROOT/src/rt.heap.allocator" "$STUB_SRC"
cat > "$STUB_SRC/RegionInfoStubProbe.cj" <<'EOF'
package rt.heap.allocator

import rt.base.REPORT

foreign { func getpid(): Int32 }

func LinkDeferredStubs(runtimeFalse: Bool): Unit {
    var regionValue = RegionInfo()
    let region = unsafe { CPointer<RegionInfo>(inout regionValue) }
    let opaque = CPointer<Unit>()
    if (runtimeFalse) {
        let _ = region.CompareExchangeRouteState(NORMAL, ROUTING)
        let _ = region.GetRouteState()
        region.SetRouteState(NORMAL)
        let _ = region.IsCompacted()
        let _ = region.IsRoutingState()
        let _ = region.TryLockRouting(NORMAL)
        let _ = region.GetPreLiveBytesInGhostRegion(0)
        let _ = region.GetLiveInfo()
        let _ = region.GetOrAllocLiveInfo()
        let _ = region.GetMarkBitmap()
        let _ = region.GetOrAllocMarkBitmap()
        let _ = region.GetResurrectBitmap()
        let _ = region.GetOrAllocResurrectBitmap()
        let _ = region.GetEnqueueBitmap()
        let _ = region.GetOrAllocEnqueueBitmap()
        region.ResetMarkBit()
        let _ = region.MarkObject(opaque)
        let _ = region.MarkObject(opaque, 1)
        let _ = region.ResurrectObject(opaque, 0)
        let _ = region.EnqueueObject(opaque, 0)
        let _ = region.IsResurrectedObject(opaque)
        let _ = region.IsResurrectedObject(UIntNative(0))
        let _ = region.IsMarkedObject(opaque)
        let _ = region.IsMarkedObject(UIntNative(0))
        let _ = region.IsSurvivedObject(0)
        let _ = region.IsEnqueuedObject(0)
        let _ = RegionInfo.InGhostFromRegion(opaque)
        let _ = RegionInfo.GetGhostFromRegionAt(0)
        let _ = region.GetGhostRegionSize()
        let _ = region.GetGhostRegionUnitCount()
        region.DumpRegionInfo(REPORT)
        let _ = region.GetTypeName()
        region.VisitAllObjects(opaque)
        let _ = region.VisitLiveObjectsUntilFalse(opaque)
        region.SetRouteInfo(0)
        let _ = region.GetRoute(opaque)
        region.PrepareForwardableRegion()
        region.ClearGhostRegionBit()
        region.DispelGhostFromRegion()
        let _ = region.IsGhostFromRegion()
        region.CheckAndClearLiveInfo(opaque)
        region.ClearLiveInfo()
    }
}

main(): Int64 {
    LinkDeferredStubs(unsafe { getpid() } < 0)
    return 0
}
EOF

(cd "$IMP" && "$SELFHOST_CJC" --package "$STUB_SRC" --import-path "$IMP" --int-overflow wrapping -Woff unused \
    "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$STUB_OUT")
"$STUB_OUT"

ABORT_SRC="$IMP/rt.heap.allocator.abortcheck"
cp -a "$ROOT/src/rt.heap.allocator" "$ABORT_SRC"
cat > "$ABORT_SRC/RegionInfoAbortProbe.cj" <<'EOF'
package rt.heap.allocator

main(): Int64 {
    var regionValue = RegionInfo()
    let region = unsafe { CPointer<RegionInfo>(inout regionValue) }
    let _ = region.MarkObject(CPointer<Unit>())
    return 99
}
EOF

(cd "$IMP" && "$SELFHOST_CJC" --package "$ABORT_SRC" --import-path "$IMP" --int-overflow wrapping -Woff unused \
    "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$ABORT_OUT")
set +e
ABORT_OUTPUT=$($ABORT_OUT 2>&1)
ABORT_RC=$?
set -e
if [[ $ABORT_RC -eq 0 ]]; then
    echo "REGIONINFO_DEFERRED_ABORT FAIL (zero exit)" >&2
    exit 1
fi
if ! grep -Fxq 'RegionInfo::MarkObject not yet ported (Collector-deferred)' <<< "$ABORT_OUTPUT"; then
    echo "REGIONINFO_DEFERRED_ABORT FAIL (message mismatch)" >&2
    printf '%s\n' "$ABORT_OUTPUT" >&2
    exit 1
fi
echo "REGIONINFO_DEFERRED_ABORT PASS rc=$ABORT_RC message=RegionInfo::MarkObject not yet ported (Collector-deferred)"

cp -a "$ROOT/src/rt.heap.allocator" "$PROBE_SRC"
cp "$ROOT/test/parity/heap/regioninfo_probe.cj" "$PROBE_SRC/RegionInfoProbe.cj"
(cd "$IMP" && "$SELFHOST_CJC" --package "$PROBE_SRC" --import-path "$IMP" --int-overflow wrapping -Woff unused \
    "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$OUT")

cp -a "$ROOT/src/rt.heap.allocator" "$INIT_SRC"
cp "$ROOT/test/parity/heap/regioninfo_noheap_probe.cj" "$INIT_SRC/RegionInfoNoHeapProbe.cj"
cat > "$INIT_SRC/RegionInfoInitDriver.cj" <<'EOF'
package rt.heap.allocator

import rt.base.RwLock

private let SENTINEL: UInt8 = 0xa5u8

private func ByteRecord(idx: UIntNative): CPointer<UInt8> {
    return CPointer<UInt8>(UnitInfo.GetUnitInfo(idx))
}

private func ReadU64(address: CPointer<UInt8>): UInt64 {
    return unsafe { CPointer<UInt64>(address).read() }
}

private func DumpCanonicalRecord(idx: UIntNative, primary: Bool,
    endIdx: UIntNative, ownerIdx: Int64): Unit {
    let bytes = ByteRecord(idx)
    var alloc = ReadU64(bytes)
    var end = unsafe { ReadU64(bytes + 8) }
    var live = unsafe { ReadU64(bytes + 32) }
    if (primary) {
        alloc = UInt64(idx)
        end = UInt64(endIdx)
    }
    if (ownerIdx >= 0) {
        live = UInt64(ownerIdx)
    }
    println("P ${idx} ${alloc} ${end} ${live}")
    for (offset in 16..32) {
        let value = unsafe { (bytes + Int64(offset)).read() }
        println("B ${idx} ${offset} ${value}")
    }
    for (offset in 40..sizeOf<UnitMetadata>()) {
        let value = unsafe { (bytes + Int64(offset)).read() }
        println("B ${idx} ${offset} ${value}")
    }
}

private func DumpUntouched(idx: UIntNative, primary: Bool, subordinate: Bool): Unit {
    let bytes = ByteRecord(idx)
    for (offset in 0..sizeOf<UnitMetadata>()) {
        var untouched = false
        if (primary) {
            untouched = (offset >= 40 && offset <= 75) || offset == 77 || offset >= 80
        } else if (subordinate) {
            untouched = !(offset >= 32 && offset <= 39) && offset != 76
        } else {
            untouched = true
        }
        if (untouched) {
            let value = unsafe { (bytes + Int64(offset)).read() }
            println("U ${idx} ${offset} ${value}")
        }
    }
}

private func DumpPrimaryFields(name: String, idx: UIntNative, endIdx: UIntNative): Unit {
    let region = RegionInfo.GetRegionInfo(UInt32(idx))
    let metadata = unsafe { region.read().metadata }
    let state = metadata.regionStateBitField.fieldVal
    println("F ${name} alloc ${idx}")
    println("F ${name} end ${endIdx}")
    println("F ${name} next ${metadata.nextRegionIdx}")
    println("F ${name} prev ${metadata.prevRegionIdx}")
    println("F ${name} liveByteCount ${metadata.liveByteCount}")
    println("F ${name} liveInfo ${if (metadata.liveInfo.isNull()) { 0 } else { 1 }}")
    println("F ${name} regionType ${region.GetRegionType()}")
    println("F ${name} unitRole ${region.GetUnitRole()}")
    println("F ${name} trace ${(state >> UInt16(TRACE_REGION_FLAG)) & 1u16}")
    println("F ${name} marked ${(state >> UInt16(MARKED_REGION_FLAG)) & 1u16}")
    println("F ${name} enqueued ${(state >> UInt16(ENQUEUED_REGION_FLAG)) & 1u16}")
    println("F ${name} resurrected ${(state >> UInt16(RESURRECTED_REGION_FLAG)) & 1u16}")
    println("F ${name} raw ${metadata.rawPointerObjectCount}")
}

private func DumpLayout(): Unit {
    var bit8 = BitFieldU8(0u8)
    var bit16 = BitFieldU16(0u16)
    var rwlock = RwLock()
    var route = RouteInfo()
    var unit = UnitInfo()
    var region = RegionInfo()
    var layout = UnitMetadata()
    let layoutBase = unsafe { CPointer<UInt8>(inout layout).toUIntNative() }
    let offsetAlloc = unsafe { CPointer<UInt8>(inout layout.allocPtr).toUIntNative() } - layoutBase
    let offsetEnd = unsafe { CPointer<UInt8>(inout layout.regionEnd).toUIntNative() } - layoutBase
    let offsetNext = unsafe { CPointer<UInt8>(inout layout.nextRegionIdx).toUIntNative() } - layoutBase
    let offsetPrev = unsafe { CPointer<UInt8>(inout layout.prevRegionIdx).toUIntNative() } - layoutBase
    let offsetLiveBytes = unsafe { CPointer<UInt8>(inout layout.liveByteCount).toUIntNative() } - layoutBase
    let offsetRaw = unsafe { CPointer<UInt8>(inout layout.rawPointerObjectCount).toUIntNative() } - layoutBase
    let offsetLive = unsafe { CPointer<UInt8>(inout layout.liveInfo).toUIntNative() } - layoutBase
    let offsetLive0 = unsafe { CPointer<UInt8>(inout layout.liveInfo0).toUIntNative() } - layoutBase
    let offsetEnd0 = unsafe { CPointer<UInt8>(inout layout.regionEnd0).toUIntNative() } - layoutBase
    let offsetRoute = unsafe { CPointer<UInt8>(inout layout.routeInfo).toUIntNative() } - layoutBase
    let offsetNext0 = unsafe { CPointer<UInt8>(inout layout.nextRegionIdx0).toUIntNative() } - layoutBase
    let offsetRole = unsafe { CPointer<UInt8>(inout layout.unitRoleBitField).toUIntNative() } - layoutBase
    let offsetState = unsafe { CPointer<UInt8>(inout layout.regionStateBitField).toUIntNative() } - layoutBase
    let offsetRouteState = unsafe { CPointer<UInt8>(inout layout.routeState).toUIntNative() } - layoutBase
    let offsetLock = unsafe { CPointer<UInt8>(inout layout.rwLock).toUIntNative() } - layoutBase
    let routeBase = unsafe { CPointer<UInt8>(inout route).toUIntNative() }
    let routeTo1 = unsafe { CPointer<UInt8>(inout route.toRegion1StartAddress).toUIntNative() } - routeBase
    let routeUsed = unsafe { CPointer<UInt8>(inout route.toRegion1UsedBytes).toUIntNative() } - routeBase
    let routeTo2 = unsafe { CPointer<UInt8>(inout route.toRegion2Idx).toUIntNative() } - routeBase
    println("REGIONINFO_ABI bit8_size=${sizeOf<BitFieldU8>()} " +
        "bit8_align=${alignOf<BitFieldU8>()} bit8_fieldVal=" +
        "${unsafe { CPointer<UInt8>(inout bit8.fieldVal).toUIntNative() - CPointer<UInt8>(inout bit8).toUIntNative() }} " +
        "bit8_value=${bit8.fieldVal} " +
        "bit16_size=${sizeOf<BitFieldU16>()} bit16_align=${alignOf<BitFieldU16>()} bit16_fieldVal=" +
        "${unsafe { CPointer<UInt8>(inout bit16.fieldVal).toUIntNative() - CPointer<UInt8>(inout bit16).toUIntNative() }} " +
        "bit16_value=${bit16.fieldVal} " +
        "rwlock_size=${sizeOf<RwLock>()} rwlock_align=${alignOf<RwLock>()} " +
        "rwlock_value=${unsafe { CPointer<Int32>(CPointer<UInt8>(inout rwlock)).read() }} " +
        "route_size=${sizeOf<RouteInfo>()} route_align=${alignOf<RouteInfo>()} " +
        "route_to1=${routeTo1} route_used=${routeUsed} route_to2=${routeTo2} " +
        "unitinfo_size=${sizeOf<UnitInfo>()} unitinfo_align=${alignOf<UnitInfo>()} unitinfo_metadata=" +
        "${unsafe { CPointer<UInt8>(inout unit.metadata).toUIntNative() - CPointer<UInt8>(inout unit).toUIntNative() }} " +
        "regioninfo_size=${sizeOf<RegionInfo>()} regioninfo_align=${alignOf<RegionInfo>()} regioninfo_metadata=" +
        "${unsafe { CPointer<UInt8>(inout region.metadata).toUIntNative() - CPointer<UInt8>(inout region).toUIntNative() }}")
    println("REGIONINFO_LAYOUT sizeof=${sizeOf<UnitMetadata>()} allocPtr=${offsetAlloc} " +
        "regionEnd=${offsetEnd} nextRegionIdx=${offsetNext} prevRegionIdx=${offsetPrev} " +
        "liveByteCount=${offsetLiveBytes} rawPointerObjectCount=${offsetRaw} liveInfo=${offsetLive} " +
        "liveInfo0=${offsetLive0} regionEnd0=${offsetEnd0} routeInfo=${offsetRoute} " +
        "nextRegionIdx0=${offsetNext0} unitRoleBitField=${offsetRole} " +
        "regionStateBitField=${offsetState} routeState=${offsetRouteState} rwLock=${offsetLock}")
}

main(): Int64 {
    DumpLayout()
    let totalUnits: UIntNative = 10
    let mappedSize = (totalUnits + 1) * RegionInfo.UNIT_SIZE
    var memMap = MemMap.MapMemory(mappedSize, mappedSize)
    let mapped = unsafe { memMap.read() }
    let heapAddress = mapped.GetBaseAddr().toUIntNative() + RegionInfo.UNIT_SIZE
    RegionInfo.Initialize(totalUnits, heapAddress)
    let metadataAddress = heapAddress - totalUnits * sizeOf<UnitInfo>()
    unsafe {
        let _ = memset(CPointer<Unit>(CPointer<UInt8>() + Int64(metadataAddress)),
            Int32(SENTINEL), totalUnits * sizeOf<UnitInfo>())
    }

    println("C free 1 3")
    println("C small 4 2")
    println("C largeAt 7 1")
    let rootResult = RegionInfoNoHeapRoot(heapAddress)

    DumpPrimaryFields("free", 1, 4)
    DumpPrimaryFields("small", 4, 6)
    DumpPrimaryFields("largeAt", 7, 8)
    let subordinate = unsafe { UnitInfo.GetUnitInfo(5).read().metadata }
    let ownerIdx = UnitInfo.GetUnitIdx(CPointer<UnitInfo>(subordinate.liveInfo))
    println("F subordinate unitRole ${UInt8(subordinate.unitRoleBitField.fieldVal & 0x0fu8)}")
    println("F subordinate owner ${ownerIdx}")
    println("S 5 ${ownerIdx} ${UInt8(subordinate.unitRoleBitField.fieldVal & 0x0fu8)}")

    for (idx in [1, 2, 3, 4, 5, 7, 9]) {
        let primary = idx == 1 || idx == 4 || idx == 7
        let isSubordinate = idx == 5
        let endIdx = if (idx == 1) { 4 } else if (idx == 4) { 6 } else { 8 }
        DumpCanonicalRecord(UIntNative(idx), primary, UIntNative(endIdx),
            if (isSubordinate) { 4 } else { -1 })
        DumpUntouched(UIntNative(idx), primary, isSubordinate)
    }

    for (idx in [1, 4, 7]) {
        let region = RegionInfo.GetRegionInfo(UInt32(idx))
        let metadata = unsafe { region.read().metadata }
        println("A ${idx} ${metadata.unitRoleBitField.fieldVal} " +
            "${metadata.regionStateBitField.fieldVal} ${region.GetUnitRole()} ${region.GetRegionType()}")
    }

    for (idx in [1, 5, 7]) {
        let address = RegionInfo.GetUnitAddress(UIntNative(idx))
        let addressIdx = (address - heapAddress) / RegionInfo.UNIT_SIZE
        let unitIdx = UnitInfo.GetUnitIdx(UnitInfo.GetUnitInfo(UIntNative(idx)))
        let regionIdx = UnitInfo.GetUnitIdx(CPointer<UnitInfo>(RegionInfo.GetRegionInfoAt(address)))
        println("M ${idx} ${addressIdx} ${unitIdx} ${regionIdx}")
    }
    println("ROOT_RESULT ${rootResult}")

    MemMap.DestroyMemMap(CPointer<CPointer<MemMap>>(inout memMap))
    return 0
}
EOF

(cd "$IMP" && "$SELFHOST_CJC" --package "$INIT_SRC" --import-path "$IMP" --int-overflow wrapping -Woff unused \
    "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$NOHEAP_OUT")
"$NOHEAP_OUT" > "$CJ_INIT_TRANSCRIPT"
cmp "$CPP_INIT_TRANSCRIPT" "$CJ_INIT_TRANSCRIPT"

if awk '$1 == "U" && $4 != 165 { exit 1 }' "$CJ_INIT_TRANSCRIPT"; then
    :
else
    echo "REGIONINFO_INIT_PARITY FAIL (untouched sentinel changed)" >&2
    exit 1
fi
CASES=$(grep -c '^C ' "$CJ_INIT_TRANSCRIPT")
FIELDS=$(grep -c '^F ' "$CJ_INIT_TRANSCRIPT")
UNTOUCHED=$(grep -c '^U ' "$CJ_INIT_TRANSCRIPT")
SUBORDINATE=$(grep -c '^S ' "$CJ_INIT_TRANSCRIPT")
EXECUTABLES=0
if [[ -x "$NOHEAP_OUT" ]]; then
    EXECUTABLES=1
fi

CJ_OUTPUT=$($OUT)
CJ_LAYOUT=$(printf '%s\n' "$CJ_OUTPUT" | grep '^REGIONINFO_LAYOUT ')
printf '%s\n' "$CPP_LAYOUT"
printf '%s\n' "$CJ_OUTPUT"

if [[ "$CJ_LAYOUT" != "$CPP_LAYOUT" ]]; then
    echo "REGIONINFO_LAYOUT ASSERT FAIL" >&2
    echo "C++: $CPP_LAYOUT" >&2
    echo "CJ : $CJ_LAYOUT" >&2
    exit 1
fi
echo "REGIONINFO_LAYOUT ASSERT PASS $CJ_LAYOUT"

if [[ $CASES -ne 3 || $FIELDS -ne 41 || $UNTOUCHED -ne 478 || $SUBORDINATE -ne 1 ||
      $EXECUTABLES -ne 1 ]] || ! grep -Fxq 'ROOT_RESULT 3' "$CJ_INIT_TRANSCRIPT"; then
    echo "REGIONINFO_INIT_PARITY FAIL (coverage/count mismatch)" >&2
    exit 1
fi
grep '^REGIONINFO_ABI ' "$CJ_INIT_TRANSCRIPT"
echo "REGIONINFO_INIT_PARITY cases=$CASES fields=$FIELDS untouched=$UNTOUCHED subordinate=$SUBORDINATE cmp=PASS"
echo "REGIONINFO_NOHEAP roots=1 objects=$OBJECT_COUNT final_bc=$FINAL_BC_COUNT "\
"executables=$EXECUTABLES mcc_new_refs=$MCC_NEW_REFS status=PASS"
echo "REGIONINFO_PLATFORM os=Linux executable=$EXECUTABLES status=PASS"

case "$CJ_OUTPUT" in
    *"REGIONINFO_PROBE PASS"*) echo "run_regioninfo_probe: PASS" ;;
    *) echo "run_regioninfo_probe: FAIL (no PASS marker)" >&2; exit 1 ;;
esac
