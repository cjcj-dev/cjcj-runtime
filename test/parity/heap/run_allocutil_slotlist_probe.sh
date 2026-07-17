#!/usr/bin/env bash
# Builds the live rt.base -> rt.sync -> rt.heap.allocator package chain, compares
# SlotList with the C++ source, and audits all reachable noheap definitions.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RUNTIME="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
SELFHOST_RUNTIME_LIB="$SELFHOST_RUNTIME/libcangjie-runtime.so"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}
LLVM_LINK="$CANGJIE_HOME/third_party/llvm/bin/llvm-link"
LLVM_OPT="$CANGJIE_HOME/third_party/llvm/bin/opt"
LLVM_DIS="$CANGJIE_HOME/third_party/llvm/bin/llvm-dis"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_allocutil_slotlist.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
CPP_OUT="$TMP/cpp.transcript"
CJ_OUT="$TMP/cj.transcript"

# The accepted canonical owner is rt.base. Parallel allocator-package ownership
# is a hard failure, and production consumers are compiled in place below.
mapfile -t ALLOCUTIL_OWNERS < <(find "$ROOT/src" -mindepth 2 -maxdepth 2 -name AllocUtil.cj -print | sort)
if [[ ${#ALLOCUTIL_OWNERS[@]} -ne 1 || ${ALLOCUTIL_OWNERS[0]} != "$ROOT/src/rt.base/AllocUtil.cj" ]]; then
    printf 'ALLOCUTIL_OWNER FAIL count=%s\n' "${#ALLOCUTIL_OWNERS[@]}" >&2
    printf '%s\n' "${ALLOCUTIL_OWNERS[@]}" >&2
    exit 1
fi

g++ -std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME \
    -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/heap/allocutil_slotlist_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -L"$SELFHOST_RUNTIME" -lsecurec -o "$TMP/cpp_probe"
"$TMP/cpp_probe" > "$CPP_OUT"

# Compile the unmodified production directories as the real dependency chain.
PACKAGE_TEMPS=()
for pkg in rt.base rt.sync rt.heap.allocator; do
    temps="$TMP/$pkg.temps"
    mkdir -p "$temps"
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --import-path "$TMP" --save-temps "$temps" --int-overflow wrapping \
        -Woff unused --output-dir "$TMP" -o "lib$pkg.a")
    PACKAGE_TEMPS+=("$temps")
done

g++ -std=c++17 -O2 -fPIC -DMRT_USE_CJTHREAD_RENAME \
    -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    -c "$ROOT/test/parity/heap/allocutil_slotlist_bridge.cpp" \
    -o "$TMP/bridge.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$TMP/Futex.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"

PROBE_SRC="$TMP/allocutil.slotlist.probe"
mkdir -p "$PROBE_SRC"
cp "$ROOT/test/parity/heap/allocutil_slotlist_probe.cj" "$PROBE_SRC/Probe.cj"
(cd "$TMP" && "$SELFHOST_CJC" --package "$PROBE_SRC" --import-path "$TMP" \
    --int-overflow wrapping -Woff unused "$TMP/librt.heap.allocator.a" \
    "$TMP/librt.sync.a" "$TMP/librt.base.a" "$TMP/bridge.o" "$TMP/Futex.o" \
    "$TMP/Panic.o" "$TMP/Atomic.o" -L"$SELFHOST_RUNTIME" -lsecurec \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/cj_probe")
"$TMP/cj_probe" > "$CJ_OUT"

diff -u "$CPP_OUT" "$CJ_OUT"
cat "$CJ_OUT"

# Three independent roots are compiled as a separate importing package. No
# production source is copied or renamed for this closure audit.
NOHEAP_SRC="$TMP/allocutil.slotlist.noheap"
NOHEAP_TEMPS="$TMP/allocutil.slotlist.noheap.temps"
mkdir -p "$NOHEAP_SRC" "$NOHEAP_TEMPS"
cp "$ROOT/test/parity/heap/allocutil_slotlist_noheap_probe.cj" "$NOHEAP_SRC/Probe.cj"
(cd "$TMP" && "$SELFHOST_CJC" --package "$NOHEAP_SRC" --output-type=staticlib \
    --import-path "$TMP" --save-temps "$NOHEAP_TEMPS" --int-overflow wrapping \
    -Woff unused --output-dir "$TMP" -o liballocutil.slotlist.noheap.a)
PACKAGE_TEMPS+=("$NOHEAP_TEMPS")

declare -A PACKAGE_PRE_BC=()
for temps in "${PACKAGE_TEMPS[@]}"; do
    PRE_BC=()
    for bc in "$temps"/*.bc; do
        if [[ "$bc" != *.opt.bc ]]; then
            PRE_BC+=("$bc")
        fi
    done
    if [[ ${#PRE_BC[@]} -eq 0 ]]; then
        echo "SLOTLIST_NOHEAP FAIL no pre-opt BC in $temps" >&2
        exit 1
    fi
    package=$(basename "$temps" .temps)
    package_pre="$TMP/$package.pre.bc"
    "$LLVM_LINK" "${PRE_BC[@]}" -o "$package_pre"
    PACKAGE_PRE_BC["$package"]="$package_pre"
done
# Package-local compiler guards have identical synthetic names, so follow the
# actual import direction and retain only definitions needed by the live root.
"$LLVM_LINK" --only-needed \
    "${PACKAGE_PRE_BC[allocutil.slotlist.noheap]}" \
    "${PACKAGE_PRE_BC[rt.heap.allocator]}" \
    "${PACKAGE_PRE_BC[rt.sync]}" \
    "${PACKAGE_PRE_BC[rt.base]}" -o "$TMP/noheap.pre.bc"
"$LLVM_DIS" "$TMP/noheap.pre.bc" -o "$TMP/noheap.pre.ll"
"$LLVM_OPT" -passes=print-callgraph -disable-output "$TMP/noheap.pre.bc" \
    2> "$TMP/noheap.callgraph"
awk '
/^Call graph node for function:/ {
    line=$0; sub(/^.*function: '\''/, "", line); sub(/'\''.*$/, "", line)
    current=line; next
}
/calls function '\''/ {
    line=$0; sub(/^.*calls function '\''/, "", line); sub(/'\''.*$/, "", line)
    if (current != "") print current "\t" line
}
' "$TMP/noheap.callgraph" > "$TMP/noheap.calls.tsv"

# All three operation wrappers plus every emitted static-initializer definition
# are traversal roots. The exact operation-root count is fail-closed.
mapfile -t OPERATION_ROOTS < <(awk '/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
    if (name ~ /SlotList(PushFront|PopFront|ClearExtraContent)NoHeapRoot/) print name
}' "$TMP/noheap.pre.ll" | sort -u)
if [[ ${#OPERATION_ROOTS[@]} -ne 3 ]]; then
    printf 'SLOTLIST_NOHEAP FAIL operation_roots=%s\n' "${#OPERATION_ROOTS[@]}" >&2
    printf '%s\n' "${OPERATION_ROOTS[@]}" >&2
    exit 1
fi
mapfile -t STATIC_ROOTS < <(awk '/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
    if (name ~ /_CGV/) print name
}' "$TMP/noheap.pre.ll" | sort -u)
ROOT_SYMBOLS=("${OPERATION_ROOTS[@]}" "${STATIC_ROOTS[@]}")

declare -A SEEN=()
QUEUE=("${ROOT_SYMBOLS[@]}")
for symbol in "${ROOT_SYMBOLS[@]}"; do SEEN["$symbol"]=1; done
while [[ ${#QUEUE[@]} -gt 0 ]]; do
    CURRENT=${QUEUE[0]}
    QUEUE=("${QUEUE[@]:1}")
    while IFS=$'\t' read -r _ callee; do
        if [[ -n "$callee" && -z ${SEEN["$callee"]+present} ]]; then
            SEEN["$callee"]=1
            QUEUE+=("$callee")
        fi
    done < <(awk -F '\t' -v key="$CURRENT" '$1 == key {print}' "$TMP/noheap.calls.tsv")
done
for symbol in "${!SEEN[@]}"; do printf '%s\n' "$symbol"; done | sort > "$TMP/noheap.symbols"

awk '/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
    print name
}' "$TMP/noheap.pre.ll" | sort -u > "$TMP/noheap.defined"
comm -12 "$TMP/noheap.symbols" "$TMP/noheap.defined" > "$TMP/noheap.reachable_cj_defs"
BASEOBJECT_SYMBOL='_ZNK12MapleRuntime10BaseObject7GetSizeEv'
if ! grep -Fxq "$BASEOBJECT_SYMBOL" "$TMP/noheap.symbols"; then
    echo 'SLOTLIST_NOHEAP FAIL BaseObject::GetSize boundary absent' >&2
    exit 1
fi
printf '%s\n' "$BASEOBJECT_SYMBOL" > "$TMP/noheap.reachable_foreign_defs"
cat "$TMP/noheap.reachable_cj_defs" "$TMP/noheap.reachable_foreign_defs" |
    sort -u > "$TMP/noheap.reachable_defs"
REACHABLE_DEFS=$(wc -l < "$TMP/noheap.reachable_defs")

: > "$TMP/noheap.closure.ll"
: > "$TMP/noheap.final_defs"
FINAL_BC_COUNT=0
for temps in "${PACKAGE_TEMPS[@]}"; do
    package=$(basename "$temps" .temps)
    for final_bc in "$temps"/*.opt.bc; do
        module_ir="$TMP/$package.$(basename "${final_bc%.bc}").ll"
        closure_ir="$module_ir.closure"
        module_defs="$module_ir.defs"
        : > "$module_defs"
        "$LLVM_DIS" "$final_bc" -o "$module_ir"
        awk -v symbols="$TMP/noheap.reachable_cj_defs" -v defs="$module_defs" '
        BEGIN { while ((getline symbol < symbols) > 0) keep[symbol]=1 }
        /^define / {
            name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
            emit=(name in keep); if (emit) print name >> defs
        }
        emit { print; if ($0 ~ /^}/) emit=0 }
        ' "$module_ir" > "$closure_ir"
        if grep -q '^define ' "$closure_ir"; then
            FINAL_BC_COUNT=$((FINAL_BC_COUNT + 1))
            cat "$closure_ir" >> "$TMP/noheap.closure.ll"
            cat "$module_defs" >> "$TMP/noheap.final_defs"
        fi
    done
done
sort -u -o "$TMP/noheap.final_defs" "$TMP/noheap.final_defs"

: > "$TMP/noheap.closure.objdump"
: > "$TMP/noheap.object_defs"
OBJECT_COUNT=0
for temps in "${PACKAGE_TEMPS[@]}"; do
    package=$(basename "$temps" .temps)
    for object in "$temps"/*.o; do
        object_dump="$TMP/$package.$(basename "$object").objdump"
        closure_dump="$object_dump.closure"
        object_defs="$object_dump.defs"
        : > "$object_defs"
        objdump -dr "$object" > "$object_dump"
        awk -v symbols="$TMP/noheap.reachable_cj_defs" -v defs="$object_defs" '
        BEGIN { while ((getline symbol < symbols) > 0) keep[symbol]=1 }
        /^[[:xdigit:]]+ <.*>:/ {
            name=$0; sub(/^[^<]*</, "", name); sub(/>:[[:space:]]*$/, "", name)
            emit=(name in keep); if (emit) print name >> defs
        }
        emit { print }
        ' "$object_dump" > "$closure_dump"
        if [[ -s "$closure_dump" ]]; then
            OBJECT_COUNT=$((OBJECT_COUNT + 1))
            cat "$closure_dump" >> "$TMP/noheap.closure.objdump"
            cat "$object_defs" >> "$TMP/noheap.object_defs"
        fi
    done
done
sort -u -o "$TMP/noheap.object_defs" "$TMP/noheap.object_defs"

# Common/BaseObject.cpp:139-149 is the live foreign target-code leaf. The
# packaged runtime is the implementation used by the executable, so scan that
# exact definition rather than a test object with a same-named substitute.
if [[ ! -f "$SELFHOST_RUNTIME_LIB" ]]; then
    echo "SLOTLIST_NOHEAP FAIL runtime library absent: $SELFHOST_RUNTIME_LIB" >&2
    exit 1
fi
read -r BASEOBJECT_ADDRESS BASEOBJECT_SIZE < <(
    readelf -Ws "$SELFHOST_RUNTIME_LIB" | awk -v symbol="$BASEOBJECT_SYMBOL" '
        $8 == symbol "@@CANGJIE" && $4 == "FUNC" && $7 != "UND" { print $2, $3; exit }
    '
)
if [[ -z ${BASEOBJECT_ADDRESS:-} || -z ${BASEOBJECT_SIZE:-} || $BASEOBJECT_SIZE -eq 0 ]]; then
    echo 'SLOTLIST_NOHEAP FAIL live BaseObject::GetSize definition absent' >&2
    exit 1
fi
BASEOBJECT_START=$((16#$BASEOBJECT_ADDRESS))
BASEOBJECT_STOP=$((BASEOBJECT_START + BASEOBJECT_SIZE))
objdump -dr --start-address="$BASEOBJECT_START" --stop-address="$BASEOBJECT_STOP" \
    "$SELFHOST_RUNTIME_LIB" > "$TMP/noheap.baseobject.objdump"
if ! grep -Fq "<$BASEOBJECT_SYMBOL@@CANGJIE>:" "$TMP/noheap.baseobject.objdump"; then
    echo 'SLOTLIST_NOHEAP FAIL BaseObject::GetSize target-code extraction empty' >&2
    exit 1
fi
cat "$TMP/noheap.baseobject.objdump" >> "$TMP/noheap.closure.objdump"
printf '%s\n' "$BASEOBJECT_SYMBOL" > "$TMP/noheap.foreign_target_defs"

comm -12 "$TMP/noheap.final_defs" "$TMP/noheap.object_defs" > "$TMP/noheap.scanned_cj_defs"
cat "$TMP/noheap.scanned_cj_defs" "$TMP/noheap.foreign_target_defs" |
    sort -u > "$TMP/noheap.scanned_defs"
comm -23 "$TMP/noheap.reachable_defs" "$TMP/noheap.scanned_defs" > "$TMP/noheap.missing"
SCANNED_DEFS=$(wc -l < "$TMP/noheap.scanned_defs")
MISSING_DEFS=$(wc -l < "$TMP/noheap.missing")

FORBIDDEN_IR_PATTERN='llvm\.cj\.alloca\.generic|MCC_New|CJ_MCC_New|RawArrayAllocate|std\.core[:.]String|std\.core[:.]Array|ArrayList|HashMap|Create[A-Za-z]*Exception|ThrowException|closure'
FORBIDDEN_OBJECT_PATTERN='R_X86_64_.*(MCC_New|CJ_MCC_New|RawArrayAllocate|StringBuilder|ArrayList|HashMap|Exception|ThrowException)'
FORBIDDEN_REFS=$( { grep -Eih "$FORBIDDEN_IR_PATTERN" "$TMP/noheap.closure.ll" || true
    grep -Eih "$FORBIDDEN_OBJECT_PATTERN" "$TMP/noheap.closure.objdump" || true
} | wc -l )
MCC_NEW_REFS=$( { grep -Eih 'MCC_New|CJ_MCC_New' "$TMP/noheap.closure.ll" || true
    grep -Eih 'R_X86_64_.*(MCC_New|CJ_MCC_New)' "$TMP/noheap.closure.objdump" || true
} | wc -l )

if [[ $FINAL_BC_COUNT -eq 0 || $OBJECT_COUNT -eq 0 || $REACHABLE_DEFS -eq 0 ||
      $SCANNED_DEFS -ne $REACHABLE_DEFS || $MISSING_DEFS -ne 0 ||
      $FORBIDDEN_REFS -ne 0 || $MCC_NEW_REFS -ne 0 ]]; then
    echo "SLOTLIST_NOHEAP FAIL roots=${#ROOT_SYMBOLS[@]} reachable_defs=$REACHABLE_DEFS scanned_defs=$SCANNED_DEFS missing=$MISSING_DEFS forbidden=$FORBIDDEN_REFS mcc=$MCC_NEW_REFS" >&2
    sed 's/^/missing /' "$TMP/noheap.missing" >&2
    grep -Ein "$FORBIDDEN_IR_PATTERN" "$TMP/noheap.closure.ll" >&2 || true
    grep -Ein "$FORBIDDEN_OBJECT_PATTERN" "$TMP/noheap.closure.objdump" >&2 || true
    exit 1
fi

echo "ALLOCUTIL_SLOTLIST_PARITY lines=$(wc -l < "$CJ_OUT") mismatches=0 status=PASS"
echo "ALLOCUTIL_OWNER definitions=${#ALLOCUTIL_OWNERS[@]} owner=rt.base live_chain=rt.base,rt.sync,rt.heap.allocator status=PASS"
echo "SLOTLIST_NOHEAP_CLOSURE roots=${#ROOT_SYMBOLS[@]} reachable_defs=$REACHABLE_DEFS scanned_defs=$SCANNED_DEFS missing=$MISSING_DEFS mcc_new_refs=$MCC_NEW_REFS status=PASS"
echo "SLOTLIST_BASEOBJECT_CLOSURE symbol=$BASEOBJECT_SYMBOL target_bytes=$BASEOBJECT_SIZE runtime_sha256=$(sha256sum "$SELFHOST_RUNTIME_LIB" | awk '{print $1}') status=PASS"
echo 'SLOTLIST_PLATFORM target=Linux-x86_64 abi=Itanium compile=PASS execute=PASS status=PASS'
echo 'SLOTLIST_PLATFORM target=Apple abi=Itanium compile=UNTESTED execute=UNTESTED debt=no_apple_toolchain status=DEBT'
echo 'SLOTLIST_PLATFORM target=Win64 abi=MSVC compile=UNTESTED execute=UNTESTED debt=itanium_foreign_symbols_not_ported status=DEBT'
echo "ALLOCUTIL_SLOTLIST_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
