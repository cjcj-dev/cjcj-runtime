#!/usr/bin/env bash
# Real LocalDeque parity: original C++ header/runtime versus the selfhost Cangjie port.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export PATH=/root/.cjv/bin:$PATH
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
SELFHOST_RUNTIME=/root/cj_build/cjcj/target/release/runtime/lib/linux_x86_64_cjnative
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CPP_RUNTIME_LIB:$RUNTIME_ROOT/output/temp/lib:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

LLVM_DIS="$CANGJIE_HOME/third_party/llvm/bin/llvm-dis"
LLVM_AS="$CANGJIE_HOME/third_party/llvm/bin/llvm-as"
LLVM_OPT="$CANGJIE_HOME/third_party/llvm/bin/opt"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_localdeque_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

test -x "$SELFHOST_CJC"
test -f "$CPP_RUNTIME_LIB/libcangjie-runtime.so"
df -h / | tail -n 1 | sed 's/^/LOCALDEQUE_DISK_BEFORE /'

CPP_OUT="$TMP/cpp.transcript"
CJ_BEHAVIOR="$TMP/cj.behavior"
CJ_OUT="$TMP/cj.transcript"

# This executable instantiates and calls the real inline LocalDeque<T> methods from
# the original header. MemMap bodies resolve from the original release runtime.
g++ -std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME \
    -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/heap/localdeque_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -o "$TMP/localdeque_ref"
"$TMP/localdeque_ref" > "$CPP_OUT"

# Build the complete runtime package chain with the mandated selfhost. Saving the
# allocator package's final IR supplies both the live layout and stack-copy evidence.
mkdir -p "$TMP/heap_temps"
for pkg in rt.base rt.sync; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" \
        -o "lib$pkg.a"
done
"$SELFHOST_CJC" --package "$ROOT/src/rt.heap.allocator" --output-type=staticlib \
    --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" \
    --save-temps "$TMP/heap_temps" -o librt.heap.allocator.a

g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$TMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"

"$SELFHOST_CJC" "$ROOT/test/parity/heap/localdeque_probe.cj" \
    --import-path "$TMP" --int-overflow wrapping -Woff unused \
    "$TMP/librt.heap.allocator.a" "$TMP/librt.sync.a" "$TMP/librt.base.a" \
    "$TMP/Futex.o" "$TMP/Panic.o" "$TMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/localdeque_cj"
"$TMP/localdeque_cj" > "$CJ_BEHAVIOR"

for bc in "$TMP"/heap_temps/*.opt.bc; do
    "$LLVM_DIS" "$bc" -o -
done > "$TMP/heap.ll"

# Derive the Cangjie live record layout using LLVM's own target DataLayout. The
# field widths, alignments, offsets and total size below are constants folded from
# the exact final record type; none is copied from the C++ oracle.
mapfile -t type_lines < <(grep -F '%"record.rt.heap.allocator:LocalDeque" = type ' \
    "$TMP/heap.ll" | sort -u)
if [[ ${#type_lines[@]} -ne 1 ]]; then
    echo "LOCALDEQUE_LAYOUT FAIL live type count=${#type_lines[@]}" >&2
    exit 1
fi
type_rhs=${type_lines[0]#*= type }
if [[ $type_rhs =~ ^\{\ i([0-9]+),\ i([0-9]+),\ i8\ addrspace\(([0-9]+)\)\*,\ \[([0-9]+)\ x\ i8\*\]\ \}$ ]]; then
    front_bits=${BASH_REMATCH[1]}
    top_bits=${BASH_REMATCH[2]}
    sud_addrspace=${BASH_REMATCH[3]}
    local_length=${BASH_REMATCH[4]}
else
    echo "LOCALDEQUE_LAYOUT FAIL unexpected live type: $type_rhs" >&2
    exit 1
fi
mapfile -t datalayout_lines < <(grep '^target datalayout = ' "$TMP/heap.ll" | sort -u)
if [[ ${#datalayout_lines[@]} -ne 1 ]]; then
    echo "LOCALDEQUE_LAYOUT FAIL datalayout count=${#datalayout_lines[@]}" >&2
    exit 1
fi
datalayout=${datalayout_lines[0]#target datalayout = }

cat > "$TMP/layout.ll" <<EOF
target datalayout = $datalayout
%LD = type $type_rhs
%LDAlign = type { i8, %LD }
%FrontAlign = type { i8, i$front_bits }
%TopAlign = type { i8, i$top_bits }
%SudAlign = type { i8, i8 addrspace($sud_addrspace)* }
%ArrayAlign = type { i8, [$local_length x i8*] }
@size = global i64 ptrtoint (%LD* getelementptr (%LD, %LD* null, i32 1) to i64)
@align = global i64 ptrtoint (%LD* getelementptr (%LDAlign, %LDAlign* null, i32 0, i32 1) to i64)
@front_offset = global i64 ptrtoint (i$front_bits* getelementptr (%LD, %LD* null, i32 0, i32 0) to i64)
@top_offset = global i64 ptrtoint (i$top_bits* getelementptr (%LD, %LD* null, i32 0, i32 1) to i64)
@sud_offset = global i64 ptrtoint (i8 addrspace($sud_addrspace)** getelementptr (%LD, %LD* null, i32 0, i32 2) to i64)
@array_offset = global i64 ptrtoint ([$local_length x i8*]* getelementptr (%LD, %LD* null, i32 0, i32 3) to i64)
@front_width = global i64 ptrtoint (i$front_bits* getelementptr (i$front_bits, i$front_bits* null, i32 1) to i64)
@front_align = global i64 ptrtoint (i$front_bits* getelementptr (%FrontAlign, %FrontAlign* null, i32 0, i32 1) to i64)
@top_width = global i64 ptrtoint (i$top_bits* getelementptr (i$top_bits, i$top_bits* null, i32 1) to i64)
@top_align = global i64 ptrtoint (i$top_bits* getelementptr (%TopAlign, %TopAlign* null, i32 0, i32 1) to i64)
@sud_width = global i64 ptrtoint (i8 addrspace($sud_addrspace)** getelementptr (i8 addrspace($sud_addrspace)*, i8 addrspace($sud_addrspace)** null, i32 1) to i64)
@sud_align = global i64 ptrtoint (i8 addrspace($sud_addrspace)** getelementptr (%SudAlign, %SudAlign* null, i32 0, i32 1) to i64)
@array_width = global i64 ptrtoint ([$local_length x i8*]* getelementptr ([$local_length x i8*], [$local_length x i8*]* null, i32 1) to i64)
@array_align = global i64 ptrtoint ([$local_length x i8*]* getelementptr (%ArrayAlign, %ArrayAlign* null, i32 0, i32 1) to i64)
EOF
"$LLVM_AS" "$TMP/layout.ll" -o "$TMP/layout.bc"
"$LLVM_OPT" -S -passes=globalopt "$TMP/layout.bc" -o "$TMP/layout.folded.ll"
layout_value() {
    awk -v symbol="@$1" '$1 == symbol { print $NF }' "$TMP/layout.folded.ll"
}

cj_size=$(layout_value size)
cj_align=$(layout_value align)
cj_front=$(layout_value front_offset)
cj_top=$(layout_value top_offset)
cj_sud=$(layout_value sud_offset)
cj_array=$(layout_value array_offset)
cj_front_width=$(layout_value front_width)
cj_front_align=$(layout_value front_align)
cj_top_width=$(layout_value top_width)
cj_top_align=$(layout_value top_align)
cj_sud_width=$(layout_value sud_width)
cj_sud_align=$(layout_value sud_align)
cj_array_width=$(layout_value array_width)
cj_array_align=$(layout_value array_align)

{
    printf 'LOCALDEQUE_LAYOUT sizeof=%s align=%s front=%s top=%s sud=%s array=%s local_length=%s\n' \
        "$cj_size" "$cj_align" "$cj_front" "$cj_top" "$cj_sud" "$cj_array" "$local_length"
    printf 'LOCALDEQUE_FIELDS front_width=%s front_align=%s top_width=%s top_align=%s sud_width=%s sud_align=%s array_width=%s array_align=%s\n' \
        "$cj_front_width" "$cj_front_align" "$cj_top_width" "$cj_top_align" \
        "$cj_sud_width" "$cj_sud_align" "$cj_array_width" "$cj_array_align"
    cat "$CJ_BEHAVIOR"
} > "$CJ_OUT"

# Full-file comparison is intentionally not reduced to markers or selected records.
if ! cmp "$CPP_OUT" "$CJ_OUT"; then
    diff -u "$CPP_OUT" "$CJ_OUT" | head -n 200 >&2 || true
    echo "LOCALDEQUE_TRANSCRIPT cmp=FAIL" >&2
    exit 1
fi
head -n 2 "$CPP_OUT"
grep '^CASE ' "$CPP_OUT"
grep '^LIFETIME id=0 ' "$CPP_OUT"
grep '^LIFETIME id=1099 ' "$CPP_OUT"
grep '^TRACE step=0 ' "$CPP_OUT"
grep '^TRACE step=1199 ' "$CPP_OUT"
grep '^MIXED PASS ' "$CPP_OUT"
grep '^LOCALDEQUE_PARITY PASS ' "$CPP_OUT"
echo "LOCALDEQUE_TRANSCRIPT lines=$(wc -l < "$CPP_OUT") bytes=$(wc -c < "$CPP_OUT") sha256=$(sha256sum "$CPP_OUT" | awk '{print $1}') cmp=PASS"
echo "LOCALDEQUE_BINARIES cpp_sha256=$(sha256sum "$TMP/localdeque_ref" | awk '{print $1}') cj_sha256=$(sha256sum "$TMP/localdeque_cj" | awk '{print $1}')"

# The generic pointer premise is a concrete unsafe read/write compile-and-run probe.
"$SELFHOST_CJC" "$ROOT/test/parity/heap/localdeque_generic_pointer_probe.cj" \
    --int-overflow wrapping -Woff unused -o "$TMP/generic_pointer_probe"
"$TMP/generic_pointer_probe"

# Count the actual stack copies retained by the operation-local VArray access.
function_count() {
    local symbol=$1
    local pattern=$2
    awk -v symbol="$symbol" -v pattern="$pattern" '
        $0 ~ /^define / && index($0, symbol) { inside = 1 }
        inside && $0 ~ pattern { ++count }
        inside && /^}/ { print count + 0; exit }
    ' "$TMP/heap.ll"
}
push_memcpy=$(function_count 'LocalDeque4Push' 'llvm.memcpy.*i64 [0-9]+, i1 false')
top_memcpy=$(function_count 'LocalDeque3Top' 'llvm.memcpy.*i64 [0-9]+, i1 false')
front_memcpy=$(function_count 'LocalDeque5Front' 'llvm.memcpy.*i64 [0-9]+, i1 false')
push_allocas=$(function_count 'LocalDeque4Push' 'alloca .*512 x i8')
top_allocas=$(function_count 'LocalDeque3Top' 'alloca .*512 x i8')
front_allocas=$(function_count 'LocalDeque5Front' 'alloca .*512 x i8')
copy_bytes=$(awk '
    /^define / && /LocalDeque4Push/ { inside = 1 }
    inside && /llvm.memcpy/ && match($0, /i64 [0-9]+, i1 false/) {
        value = substr($0, RSTART + 4, RLENGTH - 14); print value; exit
    }
    inside && /^}/ { exit }
' "$TMP/heap.ll")
if [[ -z $copy_bytes ]]; then
    echo "LOCALDEQUE_STACK_COPIES FAIL no memcpy size" >&2
    exit 1
fi
echo "LOCALDEQUE_STACK_COPIES push_memcpy=$push_memcpy top_memcpy=$top_memcpy front_memcpy=$front_memcpy bytes_each=$copy_bytes push_allocas=$push_allocas top_allocas=$top_allocas front_allocas=$front_allocas"

# Compile the dedicated root with closure checking, then scan the final IR and every
# object emitted for that compilation. Either source of MCC_New evidence is fatal.
mkdir -p "$TMP/noheap_temps"
set +e
"$SELFHOST_CJC" "$ROOT/test/parity/heap/localdeque_noheap_probe.cj" \
    --output-type=staticlib --import-path "$TMP" --int-overflow wrapping -Woff unused \
    --save-temps "$TMP/noheap_temps" -o "$TMP/localdeque_noheap.a" \
    > "$TMP/noheap.log" 2>&1
noheap_rc=$?
set -e
roots=$(grep -c '^@NoHeapAlloc' "$ROOT/test/parity/heap/localdeque_noheap_probe.cj" || true)
object_refs=$(find "$TMP/noheap_temps" -type f -name '*.o' -exec nm -u {} \; | \
    grep -Ec 'MCC_New|CJ_MCC_New' || true)
for bc in "$TMP"/noheap_temps/*.opt.bc; do
    "$LLVM_DIS" "$bc" -o -
done > "$TMP/noheap.ll" 2>/dev/null || true
ir_refs=$(grep -Ec 'MCC_New|CJ_MCC_New' "$TMP/noheap.ll" || true)
mcc_new_refs=$((object_refs + ir_refs))
if [[ $noheap_rc -ne 0 || $roots -ne 1 || $mcc_new_refs -ne 0 ]]; then
    cat "$TMP/noheap.log" >&2
    grep -nE 'MCC_New|CJ_MCC_New' "$TMP/noheap.ll" >&2 || true
    find "$TMP/noheap_temps" -type f -name '*.o' -exec nm -u {} \; | \
        grep -E 'MCC_New|CJ_MCC_New' >&2 || true
    echo "LOCALDEQUE_NOHEAP roots=$roots mcc_new_refs=$mcc_new_refs status=FAIL" >&2
    exit 1
fi
echo "LOCALDEQUE_NOHEAP roots=$roots mcc_new_refs=$mcc_new_refs status=PASS"

df -h / | tail -n 1 | sed 's/^/LOCALDEQUE_DISK_AFTER /'
echo "run_localdeque_probe: PASS"
