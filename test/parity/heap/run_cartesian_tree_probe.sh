#!/usr/bin/env bash
# Actual C++ CartesianTree versus the native-node Cangjie port, plus native-slot
# and complete @NoHeapAlloc static-closure gates.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export PATH=/root/.cjv/bin:$PATH
SELFHOST_RUNTIME="$RUNTIME_TOOLCHAIN_RT_LIB"
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CPP_RUNTIME_LIB:$RUNTIME_ROOT/output/temp/lib:$LD_LIBRARY_PATH"
export cjHeapSize=24GB

LLVM_DIS="$CANGJIE_HOME/third_party/llvm/bin/llvm-dis"
LLVM_LINK="$CANGJIE_HOME/third_party/llvm/bin/llvm-link"
LLVM_OPT="$CANGJIE_HOME/third_party/llvm/bin/opt"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_cartesian_tree_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

test -x "$SELFHOST_CJC"
test -f "$CPP_RUNTIME_LIB/libcangjie-runtime.so"
df -h / | tail -n 1 | sed 's/^/CARTESIAN_DISK_BEFORE /'

CPP_TRANSCRIPT="$TMP/cartesian.cpp.txt"
CJ_TRANSCRIPT="$TMP/cartesian.cj.txt"

# Compile the original header and .cpp directly. The reference source only
# exposes private members to drive/inspect the actual production implementation.
g++ -std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME \
    -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/src/Heap" \
    -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/heap/cartesian_tree_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -o "$TMP/cartesian_ref"
"$TMP/cartesian_ref" > "$CPP_TRANSCRIPT"

# Build the complete runtime dependency chain with the mandated selfhost.
for pkg in rt.base rt.sync rt.heap.allocator; do
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" \
        -o "lib$pkg.a")
done

g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$TMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"

PARITY_SRC="$TMP/rt.heap.allocator.parity"
PARITY_TEMPS="$TMP/parity-temps"
cp -a "$ROOT/src/rt.heap.allocator" "$PARITY_SRC"
cp "$ROOT/test/parity/heap/cartesian_tree_probe.cj" \
    "$PARITY_SRC/CartesianTreeProbe.cj"
mkdir -p "$PARITY_TEMPS"
(cd "$TMP" && "$SELFHOST_CJC" --package "$PARITY_SRC" --import-path "$TMP" \
    --save-temps "$PARITY_TEMPS" --int-overflow wrapping -Woff unused \
    "$TMP/librt.sync.a" "$TMP/librt.base.a" \
    "$TMP/Futex.o" "$TMP/Panic.o" "$TMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/cartesian_cj")
"$TMP/cartesian_cj" > "$CJ_TRANSCRIPT"

# Full-file parity is fail-closed: no selected-record or self-comparison path.
if ! cmp "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT"; then
    diff -u "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT" | head -n 240 >&2 || true
    echo "CARTESIAN_TREE_TRANSCRIPT cmp=FAIL" >&2
    exit 1
fi

LAYOUT=$(grep '^CARTESIAN_NODE_LAYOUT ' "$CJ_TRANSCRIPT")
FIELDS=$(grep '^CARTESIAN_NODE_FIELDS ' "$CJ_TRANSCRIPT")
if [[ "$LAYOUT" != 'CARTESIAN_NODE_LAYOUT sizeof=24 align=8 l=0 r=8 index=16 count=20' ||
      "$FIELDS" != 'CARTESIAN_NODE_FIELDS l_width=8 r_width=8 index_width=4 count_width=4' ]]; then
    echo "CARTESIAN_NODE_LAYOUT FAIL" >&2
    printf '%s\n%s\n' "$LAYOUT" "$FIELDS" >&2
    exit 1
fi

# The causal native-slot executable uses actual RTAllocatorT slots and the root
# field of the production @C CartesianTree. Its complete final IR is scanned.
NATIVE_SRC="$TMP/rt.heap.allocator.native"
NATIVE_TEMPS="$TMP/native-temps"
cp -a "$ROOT/src/rt.heap.allocator" "$NATIVE_SRC"
cp "$ROOT/test/parity/heap/cartesian_tree_native_slot_probe.cj" \
    "$NATIVE_SRC/CartesianTreeNativeSlotProbe.cj"
mkdir -p "$NATIVE_TEMPS"
(cd "$TMP" && "$SELFHOST_CJC" --package "$NATIVE_SRC" --import-path "$TMP" \
    --save-temps "$NATIVE_TEMPS" --int-overflow wrapping -Woff unused \
    "$TMP/librt.sync.a" "$TMP/librt.base.a" \
    "$TMP/Futex.o" "$TMP/Panic.o" "$TMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/cartesian_native_slot")
NATIVE_EXEC_OUTPUT=$("$TMP/cartesian_native_slot")
if [[ "$NATIVE_EXEC_OUTPUT" != \
      'CARTESIAN_NATIVE_SLOT_EXEC nodes=2 root=PASS l=PASS r=PASS status=PASS' ]]; then
    echo "CARTESIAN_NATIVE_SLOT_GATE execution FAIL" >&2
    printf '%s\n' "$NATIVE_EXEC_OUTPUT" >&2
    exit 1
fi
: > "$TMP/native.ll"
NATIVE_FINAL_BC=0
for bc in "$NATIVE_TEMPS"/*.opt.bc; do
    "$LLVM_DIS" "$bc" -o - >> "$TMP/native.ll"
    NATIVE_FINAL_BC=$((NATIVE_FINAL_BC + 1))
done
NATIVE_OBJECTS=$(find "$NATIVE_TEMPS" -type f -name '*.o' | wc -l)
ILLEGAL_AS1_CASTS=$(grep -Ec \
    'addrspacecast .*addrspace\(1\)\* .* to i8\*' "$TMP/native.ll" || true)
if [[ $NATIVE_FINAL_BC -eq 0 || $NATIVE_OBJECTS -eq 0 || $ILLEGAL_AS1_CASTS -ne 0 ]] ||
   ! grep -Fq '%"record.rt.heap.allocator:CartesianNode" = type { i8*, i8*, i32, i32 }' \
       "$TMP/native.ll" ||
   ! grep -Fq '%"record.rt.heap.allocator:CartesianTree" = type { i32, i8*,' \
       "$TMP/native.ll"; then
    echo "CARTESIAN_NATIVE_SLOT_GATE IR FAIL objects=$NATIVE_OBJECTS final_bc=$NATIVE_FINAL_BC illegal=$ILLEGAL_AS1_CASTS" >&2
    exit 1
fi
echo "CARTESIAN_NATIVE_SLOT_GATE nodes=2 root=PASS l=PASS r=PASS illegal_as1_casts=0 status=PASS"
echo "CARTESIAN_NATIVE_SLOT_ARTIFACTS objects=$NATIVE_OBJECTS final_bc=$NATIVE_FINAL_BC executables=1 sha256=$(sha256sum "$TMP/cartesian_native_slot" | awk '{print $1}')"

# Compile the dedicated annotated root in its owning package.
NOHEAP_SRC="$TMP/rt.heap.allocator.noheap"
NOHEAP_TEMPS="$TMP/noheap-temps"
cp -a "$ROOT/src/rt.heap.allocator" "$NOHEAP_SRC"
cp "$ROOT/test/parity/heap/cartesian_tree_noheap_probe.cj" \
    "$NOHEAP_SRC/CartesianTreeNoHeapProbe.cj"
mkdir -p "$NOHEAP_TEMPS"
(cd "$TMP" && "$SELFHOST_CJC" --package "$NOHEAP_SRC" --output-type=staticlib \
    --import-path "$TMP" --save-temps "$NOHEAP_TEMPS" --int-overflow wrapping \
    -Woff unused --output-dir "$TMP" -o cartesian_noheap.a)

# Derive the whole static closure from linked pre-opt IR, then scan every final
# BC and object that contains a corresponding definition.
PRE_BC=()
for bc in "$NOHEAP_TEMPS"/[0-9]*-rt.heap.allocator.bc; do
    if [[ "$bc" != *.opt.bc ]]; then
        PRE_BC+=("$bc")
    fi
done
"$LLVM_LINK" "${PRE_BC[@]}" -o "$TMP/noheap.pre.bc"
"$LLVM_OPT" -passes=print-callgraph -disable-output "$TMP/noheap.pre.bc" \
    2> "$TMP/noheap.callgraph"
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
' "$TMP/noheap.callgraph" > "$TMP/noheap.calls.tsv"

mapfile -t ROOT_SYMBOLS < <(awk -F '\t' '$1 ~ /CartesianTreeNoHeapRoot/ {print $1}' \
    "$TMP/noheap.calls.tsv" | sort -u)
if [[ ${#ROOT_SYMBOLS[@]} -ne 1 ]]; then
    echo "CARTESIAN_TREE_NOHEAP FAIL root_symbols=${#ROOT_SYMBOLS[@]}" >&2
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
    done < <(awk -F '\t' -v key="$CURRENT" '$1 == key {print}' "$TMP/noheap.calls.tsv")
done
for symbol in "${!SEEN[@]}"; do
    printf '%s\n' "$symbol"
done | sort > "$TMP/noheap.symbols"

: > "$TMP/noheap.closure.ll"
NOHEAP_FINAL_BC=0
for final_bc in "$NOHEAP_TEMPS"/*.opt.bc; do
    module_ir="$TMP/$(basename "${final_bc%.bc}").ll"
    closure_ir="$module_ir.closure"
    "$LLVM_DIS" "$final_bc" -o "$module_ir"
    awk -v symbols="$TMP/noheap.symbols" '
    BEGIN { while ((getline symbol < symbols) > 0) keep[symbol] = 1 }
    /^define / {
        name = $0
        sub(/^[^@]*@/, "", name)
        sub(/\(.*/, "", name)
        gsub(/^"|"$/, "", name)
        emit = (name in keep)
    }
    emit {
        print
        if ($0 ~ /^}/) emit = 0
    }
    ' "$module_ir" > "$closure_ir"
    if grep -q '^define ' "$closure_ir"; then
        NOHEAP_FINAL_BC=$((NOHEAP_FINAL_BC + 1))
        cat "$closure_ir" >> "$TMP/noheap.closure.ll"
    fi
done

: > "$TMP/noheap.closure.objdump"
NOHEAP_OBJECTS=0
for object in "$NOHEAP_TEMPS"/*.o; do
    object_dump="$TMP/$(basename "$object").objdump"
    closure_dump="$object_dump.closure"
    objdump -dr "$object" > "$object_dump"
    awk -v symbols="$TMP/noheap.symbols" '
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
        NOHEAP_OBJECTS=$((NOHEAP_OBJECTS + 1))
        cat "$closure_dump" >> "$TMP/noheap.closure.objdump"
    fi
done

FORBIDDEN_IR_PATTERN='llvm\.cj\.alloca\.generic|MCC_New|CJ_MCC_New|RawArrayAllocate|std\.core[:.]String|std\.core[:.]Array|ArrayList|HashMap|Create[A-Za-z]*Exception|ThrowException|closure'
FORBIDDEN_OBJECT_PATTERN='R_X86_64_.*(MCC_New|CJ_MCC_New|RawArrayAllocate|String|ArrayList|HashMap|Exception|ThrowException)'
FORBIDDEN_REFS=$( { grep -Eih "$FORBIDDEN_IR_PATTERN" "$TMP/noheap.closure.ll" || true
    grep -Eih "$FORBIDDEN_OBJECT_PATTERN" "$TMP/noheap.closure.objdump" || true
} | wc -l )
# Only relocations are object references. A raw disassembly target can otherwise
# mislabel the adjacent CJ_MCC_HandleSafepoint leaf as CJ_MCC_NewObjectFast+0x30.
MCC_NEW_REFS=$( { grep -Eih 'MCC_New|CJ_MCC_New' "$TMP/noheap.closure.ll" || true
    grep -Eih 'R_X86_64_.*(MCC_New|CJ_MCC_New)' "$TMP/noheap.closure.objdump" || true
} | wc -l )
if [[ $NOHEAP_FINAL_BC -eq 0 || $NOHEAP_OBJECTS -eq 0 || $FORBIDDEN_REFS -ne 0 ||
      $MCC_NEW_REFS -ne 0 ]] ||
   ! grep -q 'CartesianTreeNoHeapRoot' "$TMP/noheap.closure.ll" ||
   ! grep -q 'CartesianTreeNoHeapRoot' "$TMP/noheap.closure.objdump"; then
    echo "CARTESIAN_TREE_NOHEAP FAIL objects=$NOHEAP_OBJECTS final_bc=$NOHEAP_FINAL_BC forbidden=$FORBIDDEN_REFS mcc=$MCC_NEW_REFS" >&2
    grep -Ein "$FORBIDDEN_IR_PATTERN" "$TMP/noheap.closure.ll" >&2 || true
    grep -Ein "$FORBIDDEN_OBJECT_PATTERN" "$TMP/noheap.closure.objdump" >&2 || true
    exit 1
fi

# Execute the exact annotated root with Init/Fini outside its checked closure.
NOHEAP_EXEC_SRC="$TMP/rt.heap.allocator.noheap.exec"
cp -a "$ROOT/src/rt.heap.allocator" "$NOHEAP_EXEC_SRC"
cp "$ROOT/test/parity/heap/cartesian_tree_noheap_probe.cj" \
    "$NOHEAP_EXEC_SRC/CartesianTreeNoHeapProbe.cj"
cp "$ROOT/test/parity/heap/cartesian_tree_noheap_driver.cj" \
    "$NOHEAP_EXEC_SRC/CartesianTreeNoHeapDriver.cj"
(cd "$TMP" && "$SELFHOST_CJC" --package "$NOHEAP_EXEC_SRC" --import-path "$TMP" \
    --int-overflow wrapping -Woff unused "$TMP/librt.sync.a" "$TMP/librt.base.a" \
    "$TMP/Futex.o" "$TMP/Panic.o" "$TMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/cartesian_noheap_exec")
NOHEAP_EXEC_OUTPUT=$("$TMP/cartesian_noheap_exec")
if [[ "$NOHEAP_EXEC_OUTPUT" != \
      'CARTESIAN_TREE_NOHEAP_EXEC result=43 release=PASS' ]]; then
    echo "CARTESIAN_TREE_NOHEAP execution FAIL" >&2
    printf '%s\n' "$NOHEAP_EXEC_OUTPUT" >&2
    exit 1
fi

OPERATIONS=$(awk '/^S / {sub(/^.*operations=/, ""); sub(/ .*/, ""); print}' "$CJ_TRANSCRIPT")
LIFETIMES=$(awk '/^S / {sub(/^.*lifetimes=/, ""); sub(/ .*/, ""); print}' "$CJ_TRANSCRIPT")
RECORDS=$(awk '/^S / {sub(/^.*records=/, ""); print}' "$CJ_TRANSCRIPT")
REFRESH=$(grep -c '^G refresh ' "$CJ_TRANSCRIPT")
RELEASE=$(grep -c '^G release ' "$CJ_TRANSCRIPT")
TRANSCRIPT_LINES=$(wc -l < "$CJ_TRANSCRIPT")
TRANSCRIPT_BYTES=$(wc -c < "$CJ_TRANSCRIPT")
TRANSCRIPT_SHA=$(sha256sum "$CJ_TRANSCRIPT" | awk '{print $1}')

printf '%s\n%s\n' "$LAYOUT" "$FIELDS"
echo "CARTESIAN_TREE_PARITY PASS operations=$OPERATIONS lifetimes=$LIFETIMES records=$RECORDS"
echo "CARTESIAN_TREE_TRANSCRIPT lines=$TRANSCRIPT_LINES bytes=$TRANSCRIPT_BYTES sha256=$TRANSCRIPT_SHA cmp=PASS"
echo "CARTESIAN_TREE_REGIONINFO refresh=$REFRESH release=$RELEASE status=PASS"
echo "CARTESIAN_TREE_NOHEAP roots=1 objects=$NOHEAP_OBJECTS final_bc=$NOHEAP_FINAL_BC executables=1 mcc_new_refs=$MCC_NEW_REFS status=PASS"
echo "CARTESIAN_TREE_PLATFORM os=Linux release=executed status=PASS"
echo "CARTESIAN_TREE_BINARIES cpp_sha256=$(sha256sum "$TMP/cartesian_ref" | awk '{print $1}') cj_sha256=$(sha256sum "$TMP/cartesian_cj" | awk '{print $1}') noheap_sha256=$(sha256sum "$TMP/cartesian_noheap_exec" | awk '{print $1}')"

df -h / | tail -n 1 | sed 's/^/CARTESIAN_DISK_AFTER /'
echo "run_cartesian_tree_probe: PASS"
