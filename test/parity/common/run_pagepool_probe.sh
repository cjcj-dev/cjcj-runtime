#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export PATH=/root/.cjv/bin:$PATH
export LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$RUNTIME_ROOT/output/temp/lib:$LD_LIBRARY_PATH"
export cjHeapSize=24GB

LLVM_DIS="$CANGJIE_HOME/third_party/llvm/bin/llvm-dis"
LLVM_AS="$CANGJIE_HOME/third_party/llvm/bin/llvm-as"
LLVM_OPT="$CANGJIE_HOME/third_party/llvm/bin/opt"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_pagepool_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

test -x "$SELFHOST_CJC"
test -f "$CPP_RUNTIME_LIB/libcangjie-runtime.so"
df -h / | tail -n 1 | sed 's/^/PAGEPOOL_DISK_BEFORE /'

PAGEPOOL_SOURCE="$ROOT/src/rt.common/PagePool.cj"
APPLE_RETURN_BLOCK="$TMP/apple_return_page_part2.cj"
awk '
$0 == "@When[os == \"macOS\" || os == \"iOS\"]" { candidate = 1; annotation = $0; next }
candidate {
    if ($0 == "func ReturnPagePart2(page: CPointer<Unit>, size: UIntNative): Unit {") {
        print annotation
        capture = 1
        print
        next
    }
    candidate = 0
}
capture && $0 == "@When[os == \"Windows\"]" { exit }
capture { print }
' "$PAGEPOOL_SOURCE" > "$APPLE_RETURN_BLOCK"
if grep -Eq 'PAGE_POOL_MMAP_(FIXED|WRONG_ADDR)_ERROR' "$PAGEPOOL_SOURCE" ||
   [[ $(grep -Fc 'var mmapFailedMessage: VArray<UInt8, $28> = [' "$PAGEPOOL_SOURCE") -ne 1 ]] ||
   [[ $(grep -Fc 'var wrongAddressMessage: VArray<UInt8, $25> = [' "$PAGEPOOL_SOURCE") -ne 1 ]] ||
   [[ $(grep -Fc '@When[os == "macOS" || os == "iOS"]' "$APPLE_RETURN_BLOCK") -ne 1 ]] ||
   [[ $(grep -Fc 'func ReturnPagePart2(page: CPointer<Unit>, size: UIntNative): Unit {' "$APPLE_RETURN_BLOCK") -ne 1 ]] ||
   [[ $(grep -Fc '    var mmapFailedMessage: VArray<UInt8, $28> = [' "$APPLE_RETURN_BLOCK") -ne 1 ]] ||
   [[ $(grep -Fc '    var wrongAddressMessage: VArray<UInt8, $25> = [' "$APPLE_RETURN_BLOCK") -ne 1 ]] ||
   [[ $(grep -Fc 'perror(CString(CPointer<UInt8>(inout mmapFailedMessage)))' "$APPLE_RETURN_BLOCK") -ne 1 ]] ||
   [[ $(grep -Fc 'perror(CString(CPointer<UInt8>(inout wrongAddressMessage)))' "$APPLE_RETURN_BLOCK") -ne 1 ]]; then
    echo "PAGEPOOL_APPLE_DIAGNOSTIC_BOUNDARY package_globals=FAIL local_arrays=FAIL status=FAIL" >&2
    exit 1
fi
echo "PAGEPOOL_APPLE_DIAGNOSTIC_BOUNDARY package_globals=0 local_arrays=2 status=PASS"

CPP_OUT="$TMP/pagepool.cpp.txt"
CJ_OUT="$TMP/pagepool.cj.txt"

g++ -std=c++17 -O2 -pthread -DPAGEPOOL_ORIGINAL -DMRT_USE_CJTHREAD_RENAME \
    -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/src/Heap" \
    -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/common/pagepool_ref.cpp" \
    "$ROOT/rt0/os/Linux/PagePoolMutex.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -o "$TMP/pagepool_ref"
"$TMP/pagepool_ref" > "$CPP_OUT"

mkdir -p "$TMP/heap_temps" "$TMP/common_temps"
for pkg in rt.base rt.sync; do
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" \
        -o "lib$pkg.a")
done
(cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/rt.heap.allocator" \
    --output-type=staticlib --int-overflow wrapping -Woff unused --import-path "$TMP" \
    --output-dir "$TMP" --save-temps "$TMP/heap_temps" -o librt.heap.allocator.a)
(cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/rt.common" \
    --output-type=staticlib --int-overflow wrapping -Woff unused --import-path "$TMP" \
    --output-dir "$TMP" --save-temps "$TMP/common_temps" -o librt.common.a)

for bc in "$TMP"/heap_temps/*.opt.bc; do "$LLVM_DIS" "$bc" -o -; done > "$TMP/heap.ll"
for bc in "$TMP"/common_temps/*.opt.bc; do "$LLVM_DIS" "$bc" -o -; done > "$TMP/common.ll"

type_rhs() {
    local file=$1
    local name=$2
    mapfile -t lines < <(grep -F "%\"record.$name\" = type " "$file" | sort -u)
    if [[ ${#lines[@]} -ne 1 ]]; then
        echo "PAGEPOOL_LAYOUT FAIL type=$name count=${#lines[@]}" >&2
        exit 1
    fi
    printf '%s' "${lines[0]#*= type }"
}

sud_rhs=$(type_rhs "$TMP/heap.ll" 'rt.heap.allocator:SingleUseDeque')
rt_rhs=$(type_rhs "$TMP/heap.ll" 'rt.heap.allocator:RTAllocatorT')
tree_rhs=$(type_rhs "$TMP/heap.ll" 'rt.heap.allocator:CartesianTree')
ld_rhs=$(type_rhs "$TMP/heap.ll" 'rt.heap.allocator:LocalDeque')
node_rhs=$(type_rhs "$TMP/heap.ll" 'rt.heap.allocator:CartesianNode')
mutex_rhs=$(type_rhs "$TMP/common.ll" 'rt.common:PagePoolMutex')
pool_rhs=$(type_rhs "$TMP/common.ll" 'rt.common:PagePool')
ILLEGAL_AS1_CASTS=$(cat "$TMP/heap.ll" "$TMP/common.ll" | \
    grep -Ec 'addrspacecast .*addrspace\(1\)\* .* to i8\*' || true)
if [[ $ILLEGAL_AS1_CASTS -ne 0 ||
      "$sud_rhs" != '{ i8*, i8*, i8*, i8*, i8* }' ||
      "$rt_rhs" != '{ i8*, i8*, i8*, i8* }' ||
      "$tree_rhs" != '{ i32, i8*, %"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:RTAllocatorT" }' ||
      "$pool_rhs" != '{ %"record.rt.common:PagePoolMutex", %"record.rt.heap.allocator:CartesianTree", i8*, i64, i64, i8*, i32, i32 }' ]]; then
    echo "PAGEPOOL_IR FAIL illegal_as1_casts=$ILLEGAL_AS1_CASTS" >&2
    exit 1
fi
datalayout=$(grep '^target datalayout = ' "$TMP/common.ll" | sort -u)
if [[ $(printf '%s\n' "$datalayout" | wc -l) -ne 1 ]]; then
    echo "PAGEPOOL_LAYOUT FAIL datalayout" >&2
    exit 1
fi

cat > "$TMP/layout.ll" <<EOF
$datalayout
%"record.rt.heap.allocator:SingleUseDeque" = type $sud_rhs
%"record.rt.heap.allocator:RTAllocatorT" = type $rt_rhs
%"record.rt.heap.allocator:CartesianTree" = type $tree_rhs
%"record.rt.heap.allocator:LocalDeque" = type $ld_rhs
%"record.rt.heap.allocator:CartesianNode" = type $node_rhs
%"record.rt.common:PagePoolMutex" = type $mutex_rhs
%"record.rt.common:PagePool" = type $pool_rhs
%SUDAlign = type { i8, %"record.rt.heap.allocator:SingleUseDeque" }
%RTAlign = type { i8, %"record.rt.heap.allocator:RTAllocatorT" }
%TreeAlign = type { i8, %"record.rt.heap.allocator:CartesianTree" }
%LDAlign = type { i8, %"record.rt.heap.allocator:LocalDeque" }
%NodeAlign = type { i8, %"record.rt.heap.allocator:CartesianNode" }
%MutexAlign = type { i8, %"record.rt.common:PagePoolMutex" }
%PoolAlign = type { i8, %"record.rt.common:PagePool" }
%AtomicAlign = type { i8, i32 }
@sud_size = global i64 ptrtoint (%"record.rt.heap.allocator:SingleUseDeque"* getelementptr (%"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:SingleUseDeque"* null, i32 1) to i64)
@sud_align = global i64 ptrtoint (%"record.rt.heap.allocator:SingleUseDeque"* getelementptr (%SUDAlign, %SUDAlign* null, i32 0, i32 1) to i64)
@rt_size = global i64 ptrtoint (%"record.rt.heap.allocator:RTAllocatorT"* getelementptr (%"record.rt.heap.allocator:RTAllocatorT", %"record.rt.heap.allocator:RTAllocatorT"* null, i32 1) to i64)
@rt_align = global i64 ptrtoint (%"record.rt.heap.allocator:RTAllocatorT"* getelementptr (%RTAlign, %RTAlign* null, i32 0, i32 1) to i64)
@tree_size = global i64 ptrtoint (%"record.rt.heap.allocator:CartesianTree"* getelementptr (%"record.rt.heap.allocator:CartesianTree", %"record.rt.heap.allocator:CartesianTree"* null, i32 1) to i64)
@tree_align = global i64 ptrtoint (%"record.rt.heap.allocator:CartesianTree"* getelementptr (%TreeAlign, %TreeAlign* null, i32 0, i32 1) to i64)
@ld_size = global i64 ptrtoint (%"record.rt.heap.allocator:LocalDeque"* getelementptr (%"record.rt.heap.allocator:LocalDeque", %"record.rt.heap.allocator:LocalDeque"* null, i32 1) to i64)
@ld_align = global i64 ptrtoint (%"record.rt.heap.allocator:LocalDeque"* getelementptr (%LDAlign, %LDAlign* null, i32 0, i32 1) to i64)
@node_size = global i64 ptrtoint (%"record.rt.heap.allocator:CartesianNode"* getelementptr (%"record.rt.heap.allocator:CartesianNode", %"record.rt.heap.allocator:CartesianNode"* null, i32 1) to i64)
@node_align = global i64 ptrtoint (%"record.rt.heap.allocator:CartesianNode"* getelementptr (%NodeAlign, %NodeAlign* null, i32 0, i32 1) to i64)
@mutex_size = global i64 ptrtoint (%"record.rt.common:PagePoolMutex"* getelementptr (%"record.rt.common:PagePoolMutex", %"record.rt.common:PagePoolMutex"* null, i32 1) to i64)
@mutex_align = global i64 ptrtoint (%"record.rt.common:PagePoolMutex"* getelementptr (%MutexAlign, %MutexAlign* null, i32 0, i32 1) to i64)
@pool_size = global i64 ptrtoint (%"record.rt.common:PagePool"* getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 1) to i64)
@pool_align = global i64 ptrtoint (%"record.rt.common:PagePool"* getelementptr (%PoolAlign, %PoolAlign* null, i32 0, i32 1) to i64)
@atomic_size = global i64 ptrtoint (i32* getelementptr (i32, i32* null, i32 1) to i64)
@atomic_align = global i64 ptrtoint (i32* getelementptr (%AtomicAlign, %AtomicAlign* null, i32 0, i32 1) to i64)
EOF

cat >> "$TMP/layout.ll" <<'EOF'
@sud_memMap = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:SingleUseDeque"* null, i32 0, i32 0) to i64)
@sud_begin = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:SingleUseDeque"* null, i32 0, i32 1) to i64)
@sud_front = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:SingleUseDeque"* null, i32 0, i32 2) to i64)
@sud_top = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:SingleUseDeque"* null, i32 0, i32 3) to i64)
@sud_end = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:SingleUseDeque", %"record.rt.heap.allocator:SingleUseDeque"* null, i32 0, i32 4) to i64)
@rt_head = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:RTAllocatorT", %"record.rt.heap.allocator:RTAllocatorT"* null, i32 0, i32 0) to i64)
@rt_curr = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:RTAllocatorT", %"record.rt.heap.allocator:RTAllocatorT"* null, i32 0, i32 1) to i64)
@rt_end = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:RTAllocatorT", %"record.rt.heap.allocator:RTAllocatorT"* null, i32 0, i32 2) to i64)
@rt_memMap = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:RTAllocatorT", %"record.rt.heap.allocator:RTAllocatorT"* null, i32 0, i32 3) to i64)
@tree_total = global i64 ptrtoint (i32* getelementptr (%"record.rt.heap.allocator:CartesianTree", %"record.rt.heap.allocator:CartesianTree"* null, i32 0, i32 0) to i64)
@tree_root = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:CartesianTree", %"record.rt.heap.allocator:CartesianTree"* null, i32 0, i32 1) to i64)
@tree_sud = global i64 ptrtoint (%"record.rt.heap.allocator:SingleUseDeque"* getelementptr (%"record.rt.heap.allocator:CartesianTree", %"record.rt.heap.allocator:CartesianTree"* null, i32 0, i32 2) to i64)
@tree_traversal = global i64 ptrtoint (%"record.rt.heap.allocator:SingleUseDeque"* getelementptr (%"record.rt.heap.allocator:CartesianTree", %"record.rt.heap.allocator:CartesianTree"* null, i32 0, i32 3) to i64)
@tree_allocator = global i64 ptrtoint (%"record.rt.heap.allocator:RTAllocatorT"* getelementptr (%"record.rt.heap.allocator:CartesianTree", %"record.rt.heap.allocator:CartesianTree"* null, i32 0, i32 4) to i64)
@ld_front = global i64 ptrtoint (i32* getelementptr (%"record.rt.heap.allocator:LocalDeque", %"record.rt.heap.allocator:LocalDeque"* null, i32 0, i32 0) to i64)
@ld_top = global i64 ptrtoint (i32* getelementptr (%"record.rt.heap.allocator:LocalDeque", %"record.rt.heap.allocator:LocalDeque"* null, i32 0, i32 1) to i64)
@ld_sud = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:LocalDeque", %"record.rt.heap.allocator:LocalDeque"* null, i32 0, i32 2) to i64)
@ld_array = global i64 ptrtoint ([512 x i8*]* getelementptr (%"record.rt.heap.allocator:LocalDeque", %"record.rt.heap.allocator:LocalDeque"* null, i32 0, i32 3) to i64)
@node_l = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:CartesianNode", %"record.rt.heap.allocator:CartesianNode"* null, i32 0, i32 0) to i64)
@node_r = global i64 ptrtoint (i8** getelementptr (%"record.rt.heap.allocator:CartesianNode", %"record.rt.heap.allocator:CartesianNode"* null, i32 0, i32 1) to i64)
@node_index = global i64 ptrtoint (i32* getelementptr (%"record.rt.heap.allocator:CartesianNode", %"record.rt.heap.allocator:CartesianNode"* null, i32 0, i32 2) to i64)
@node_count = global i64 ptrtoint (i32* getelementptr (%"record.rt.heap.allocator:CartesianNode", %"record.rt.heap.allocator:CartesianNode"* null, i32 0, i32 3) to i64)
@pool_mutex = global i64 ptrtoint (%"record.rt.common:PagePoolMutex"* getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 0) to i64)
@pool_tree = global i64 ptrtoint (%"record.rt.heap.allocator:CartesianTree"* getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 1) to i64)
@pool_base = global i64 ptrtoint (i8** getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 2) to i64)
@pool_totalSize = global i64 ptrtoint (i64* getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 3) to i64)
@pool_usedZone = global i64 ptrtoint (i64* getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 4) to i64)
@pool_tag = global i64 ptrtoint (i8** getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 5) to i64)
@pool_atomic = global i64 ptrtoint (i32* getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 6) to i64)
@pool_pageCount = global i64 ptrtoint (i32* getelementptr (%"record.rt.common:PagePool", %"record.rt.common:PagePool"* null, i32 0, i32 7) to i64)
EOF

"$LLVM_AS" "$TMP/layout.ll" -o "$TMP/layout.bc"
"$LLVM_OPT" -S -passes=globalopt "$TMP/layout.bc" -o "$TMP/layout.folded.ll"
layout_value() {
    awk -v symbol="@$1" '$1 == symbol { print $NF }' "$TMP/layout.folded.ll"
}

CJ_DEFINES=(
    -DCJ_SUD_SIZE=$(layout_value sud_size) -DCJ_SUD_ALIGN=$(layout_value sud_align)
    -DCJ_SUD_MEMMAP=$(layout_value sud_memMap) -DCJ_SUD_BEGIN=$(layout_value sud_begin)
    -DCJ_SUD_FRONT=$(layout_value sud_front) -DCJ_SUD_TOP=$(layout_value sud_top)
    -DCJ_SUD_END=$(layout_value sud_end)
    -DCJ_RT_SIZE=$(layout_value rt_size) -DCJ_RT_ALIGN=$(layout_value rt_align)
    -DCJ_RT_HEAD=$(layout_value rt_head) -DCJ_RT_CURR=$(layout_value rt_curr)
    -DCJ_RT_END=$(layout_value rt_end) -DCJ_RT_MEMMAP=$(layout_value rt_memMap)
    -DCJ_TREE_SIZE=$(layout_value tree_size) -DCJ_TREE_ALIGN=$(layout_value tree_align)
    -DCJ_TREE_TOTAL=$(layout_value tree_total) -DCJ_TREE_ROOT=$(layout_value tree_root)
    -DCJ_TREE_SUD=$(layout_value tree_sud) -DCJ_TREE_TRAVERSAL=$(layout_value tree_traversal)
    -DCJ_TREE_ALLOCATOR=$(layout_value tree_allocator)
    -DCJ_LD_SIZE=$(layout_value ld_size) -DCJ_LD_ALIGN=$(layout_value ld_align)
    -DCJ_LD_FRONT=$(layout_value ld_front) -DCJ_LD_TOP=$(layout_value ld_top)
    -DCJ_LD_SUD=$(layout_value ld_sud) -DCJ_LD_ARRAY=$(layout_value ld_array)
    -DCJ_NODE_SIZE=$(layout_value node_size) -DCJ_NODE_ALIGN=$(layout_value node_align)
    -DCJ_NODE_L=$(layout_value node_l) -DCJ_NODE_R=$(layout_value node_r)
    -DCJ_NODE_INDEX=$(layout_value node_index) -DCJ_NODE_COUNT=$(layout_value node_count)
    -DCJ_POOL_SIZE=$(layout_value pool_size) -DCJ_POOL_ALIGN=$(layout_value pool_align)
    -DCJ_POOL_MUTEX=$(layout_value pool_mutex) -DCJ_POOL_TREE=$(layout_value pool_tree)
    -DCJ_POOL_BASE=$(layout_value pool_base) -DCJ_POOL_TOTALSIZE=$(layout_value pool_totalSize)
    -DCJ_POOL_USEDZONE=$(layout_value pool_usedZone) -DCJ_POOL_TAG=$(layout_value pool_tag)
    -DCJ_POOL_ATOMIC=$(layout_value pool_atomic) -DCJ_POOL_PAGECOUNT=$(layout_value pool_pageCount)
    -DCJ_MUTEX_SIZE=$(layout_value mutex_size) -DCJ_MUTEX_ALIGN=$(layout_value mutex_align)
    -DCJ_ATOMIC_SIZE=$(layout_value atomic_size) -DCJ_ATOMIC_ALIGN=$(layout_value atomic_align)
)

g++ -std=c++17 -O2 -pthread -fPIC "${CJ_DEFINES[@]}" \
    -c "$ROOT/test/parity/common/pagepool_ref.cpp" -o "$TMP/pagepool_driver.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$TMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/PagePoolMutex.cpp" -o "$TMP/PagePoolMutex.o"

COMMON_SRC="$TMP/rt.common.probe"
cp -a "$ROOT/src/rt.common" "$COMMON_SRC"
cp "$ROOT/test/parity/common/pagepool_layout_probe.cj" "$COMMON_SRC/PagePoolLayoutProbe.cj"
cp "$ROOT/test/parity/common/pagepool_driver.cj" "$COMMON_SRC/PagePoolDriver.cj"
(cd "$TMP" && "$SELFHOST_CJC" --package "$COMMON_SRC" --import-path "$TMP" \
    --int-overflow wrapping -Woff unused "$TMP/librt.heap.allocator.a" \
    "$TMP/librt.sync.a" "$TMP/librt.base.a" "$TMP/pagepool_driver.o" \
    "$TMP/Futex.o" "$TMP/Panic.o" "$TMP/Atomic.o" "$TMP/PagePoolMutex.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread -o "$TMP/pagepool_cj")
"$TMP/pagepool_cj" > "$CJ_OUT"

if ! cmp "$CPP_OUT" "$CJ_OUT"; then
    diff -u "$CPP_OUT" "$CJ_OUT" | head -n 240 >&2 || true
    echo "PAGEPOOL_TRANSCRIPT cmp=FAIL" >&2
    exit 1
fi

grep '^PAGEPOOL_LAYOUT ' "$CJ_OUT"
grep '^PAGEPOOL_FIELDS ' "$CJ_OUT"
grep '^PAGEPOOL_CONFIG ' "$CJ_OUT"
grep '^PAGEPOOL_PARITY PASS ' "$CJ_OUT"
grep '^PAGEPOOL_MUTEX ' "$CJ_OUT"
grep '^PAGEPOOL_MUTEX_ABI ' "$CJ_OUT"
grep '^PAGEPOOL_PLATFORM ' "$CJ_OUT"
echo "PAGEPOOL_TRANSCRIPT lines=$(wc -l < "$CJ_OUT") bytes=$(wc -c < "$CJ_OUT") sha256=$(sha256sum "$CJ_OUT" | awk '{print $1}') cmp=PASS"

for symbol in \
    _ZN12MapleRuntime8PagePool8InstanceEv \
    _ZN12MapleRuntime8PagePool7GetPageEm \
    _ZN12MapleRuntime8PagePool10ReturnPageEPhm \
    _ZN12MapleRuntime8PagePool4FiniEv \
    _ZNK12MapleRuntime8PagePool9MapMemoryEmPKcb; do
    cpp_count=$(nm -D "$CPP_RUNTIME_LIB/libcangjie-runtime.so" | awk -v s="$symbol" '$3 ~ ("^" s "(@@.*)?$") {++n} END {print n+0}')
    cj_count=$(nm "$TMP/pagepool_cj" | awk -v s="$symbol" '$3 == s {++n} END {print n+0}')
    if [[ $cpp_count -ne 1 || $cj_count -ne 1 ]]; then
        echo "PAGEPOOL_SYMBOL FAIL symbol=$symbol cpp=$cpp_count cj=$cj_count" >&2
        exit 1
    fi
done
echo "PAGEPOOL_SYMBOLS instance=1 get=1 return=1 fini=1 map=1 signatures=PASS"
echo "PAGEPOOL_IR inline_sud=1 inline_allocator=1 inline_tree=1 inline_pool=1 illegal_as1_casts=0 status=PASS"

# Compile every package in the live PagePool closure with an annotated root in
# its owning package. The linked pre-opt graph below therefore resolves the
# allocator calls to definitions instead of stopping at imported declarations.
HEAP_NOHEAP_SRC="$TMP/rt.heap.allocator.noheap"
HEAP_NOHEAP_TEMPS="$TMP/heap_noheap_temps"
cp -a "$ROOT/src/rt.heap.allocator" "$HEAP_NOHEAP_SRC"
cp "$ROOT/test/parity/heap/cartesian_tree_noheap_probe.cj" \
    "$HEAP_NOHEAP_SRC/CartesianTreeNoHeapProbe.cj"
mkdir -p "$HEAP_NOHEAP_TEMPS"
(cd "$TMP" && "$SELFHOST_CJC" --package "$HEAP_NOHEAP_SRC" --output-type=staticlib \
    --import-path "$TMP" --save-temps "$HEAP_NOHEAP_TEMPS" --int-overflow wrapping \
    -Woff unused --output-dir "$TMP" -o pagepool_heap_noheap.a)

COMMON_NOHEAP_SRC="$TMP/rt.common.noheap"
COMMON_NOHEAP_TEMPS="$TMP/common_noheap_temps"
cp -a "$ROOT/src/rt.common" "$COMMON_NOHEAP_SRC"
cp "$ROOT/test/parity/common/pagepool_noheap_probe.cj" \
    "$COMMON_NOHEAP_SRC/PagePoolNoHeapProbe.cj"
mkdir -p "$COMMON_NOHEAP_TEMPS"
(cd "$TMP" && "$SELFHOST_CJC" --package "$COMMON_NOHEAP_SRC" --output-type=staticlib \
    --import-path "$TMP" --save-temps "$COMMON_NOHEAP_TEMPS" --int-overflow wrapping \
    -Woff unused --output-dir "$TMP" -o pagepool_common_noheap.a)

HEAP_PRE_BC=()
for bc in "$HEAP_NOHEAP_TEMPS"/[0-9]*.bc; do
    if [[ "$bc" != *.opt.bc ]]; then
        HEAP_PRE_BC+=("$bc")
    fi
done
COMMON_PRE_BC=()
for bc in "$COMMON_NOHEAP_TEMPS"/[0-9]*.bc; do
    if [[ "$bc" != *.opt.bc ]]; then
        COMMON_PRE_BC+=("$bc")
    fi
done
"$CANGJIE_HOME/third_party/llvm/bin/llvm-link" "${HEAP_PRE_BC[@]}" \
    -o "$TMP/noheap.heap.pre.bc"
"$CANGJIE_HOME/third_party/llvm/bin/llvm-link" "${COMMON_PRE_BC[@]}" \
    -o "$TMP/noheap.common.pre.bc"
"$CANGJIE_HOME/third_party/llvm/bin/llvm-link" --only-needed \
    "$TMP/noheap.common.pre.bc" "$TMP/noheap.heap.pre.bc" -o "$TMP/noheap.pre.bc"
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

"$LLVM_DIS" "$TMP/noheap.pre.bc" -o "$TMP/noheap.pre.ll"
mapfile -t ROOT_SYMBOLS < <(awk '/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
    if (name ~ /PagePool(Construct|Init|GetPage|ReturnPage|TrimFini)NoHeapRoot/ ||
        name ~ /_CGV9rt\.common(13MRT_PAGE_SIZE|13PAGE_POOL_TAG|18PAGE_POOL_INSTANCE|27PAGE_POOL_MUTEX_CONSTRUCTED)/) print name
}' "$TMP/noheap.pre.ll" | sort -u)
if [[ ${#ROOT_SYMBOLS[@]} -ne 9 ]]; then
    printf 'PAGEPOOL_NOHEAP FAIL root_symbols=%s\n' "${#ROOT_SYMBOLS[@]}" >&2
    printf '%s\n' "${ROOT_SYMBOLS[@]}" >&2
    exit 1
fi
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
comm -12 "$TMP/noheap.symbols" "$TMP/noheap.defined" > "$TMP/noheap.reachable_defs"
REACHABLE_DEFS=$(wc -l < "$TMP/noheap.reachable_defs")

: > "$TMP/noheap.closure.ll"
: > "$TMP/noheap.final_defs"
NOHEAP_FINAL_BC=0
for temps in "$HEAP_NOHEAP_TEMPS" "$COMMON_NOHEAP_TEMPS"; do
    package=$(basename "$temps" _noheap_temps)
    for final_bc in "$temps"/*.opt.bc; do
        module_ir="$TMP/$package.$(basename "${final_bc%.bc}").ll"
        closure_ir="$module_ir.closure"
        module_defs="$module_ir.defs"
        "$LLVM_DIS" "$final_bc" -o "$module_ir"
        awk -v symbols="$TMP/noheap.reachable_defs" -v defs="$module_defs" '
        BEGIN { while ((getline symbol < symbols) > 0) keep[symbol] = 1 }
        /^define / {
            name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
            emit=(name in keep)
            if (emit) print name >> defs
        }
        emit { print; if ($0 ~ /^}/) emit=0 }
        ' "$module_ir" > "$closure_ir"
        if grep -q '^define ' "$closure_ir"; then
            NOHEAP_FINAL_BC=$((NOHEAP_FINAL_BC + 1))
            cat "$closure_ir" >> "$TMP/noheap.closure.ll"
            cat "$module_defs" >> "$TMP/noheap.final_defs"
        fi
    done
done
sort -u -o "$TMP/noheap.final_defs" "$TMP/noheap.final_defs"

: > "$TMP/noheap.closure.objdump"
: > "$TMP/noheap.object_defs"
NOHEAP_OBJECTS=0
for temps in "$HEAP_NOHEAP_TEMPS" "$COMMON_NOHEAP_TEMPS"; do
    package=$(basename "$temps" _noheap_temps)
    for object in "$temps"/[0-9]*.o; do
        object_dump="$TMP/$package.$(basename "$object").objdump"
        closure_dump="$object_dump.closure"
        object_defs="$object_dump.defs"
        objdump -dr "$object" > "$object_dump"
        awk -v symbols="$TMP/noheap.reachable_defs" -v defs="$object_defs" '
        BEGIN { while ((getline symbol < symbols) > 0) keep[symbol] = 1 }
        /^[[:xdigit:]]+ <.*>:/ {
            name=$0; sub(/^[^<]*</, "", name); sub(/>:[[:space:]]*$/, "", name); emit=(name in keep)
            if (emit) print name >> defs
        }
        emit { print }
        ' "$object_dump" > "$closure_dump"
        if [[ -s "$closure_dump" ]]; then
            NOHEAP_OBJECTS=$((NOHEAP_OBJECTS + 1))
            cat "$closure_dump" >> "$TMP/noheap.closure.objdump"
            cat "$object_defs" >> "$TMP/noheap.object_defs"
        fi
    done
done
sort -u -o "$TMP/noheap.object_defs" "$TMP/noheap.object_defs"

comm -23 "$TMP/noheap.reachable_defs" "$TMP/noheap.final_defs" > "$TMP/noheap.missing_final"
comm -23 "$TMP/noheap.reachable_defs" "$TMP/noheap.object_defs" > "$TMP/noheap.missing_object"
comm -12 "$TMP/noheap.final_defs" "$TMP/noheap.object_defs" > "$TMP/noheap.scanned_defs"
cat "$TMP/noheap.missing_final" "$TMP/noheap.missing_object" | sort -u > "$TMP/noheap.missing"
SCANNED_DEFS=$(wc -l < "$TMP/noheap.scanned_defs")
MISSING_DEFS=$(wc -l < "$TMP/noheap.missing")
CLOSURE_COMPONENTS=0
for component in CartesianTree SingleUseDeque RTAllocatorT MemMap; do
    if grep -q "rt.heap.allocator.*$component" "$TMP/noheap.reachable_defs"; then
        CLOSURE_COMPONENTS=$((CLOSURE_COMPONENTS + 1))
    fi
done

FORBIDDEN_IR_PATTERN='llvm\.cj\.alloca\.generic|MCC_New|CJ_MCC_New|RawArrayAllocate|std\.core[:.]String|std\.core[:.]Array|ArrayList|HashMap|Create[A-Za-z]*Exception|ThrowException|closure'
FORBIDDEN_OBJECT_PATTERN='R_X86_64_.*(MCC_New|CJ_MCC_New|RawArrayAllocate|StringBuilder|ArrayList|HashMap|Exception|ThrowException)'
FORBIDDEN_REFS=$( { grep -Eih "$FORBIDDEN_IR_PATTERN" "$TMP/noheap.closure.ll" || true
    grep -Eih "$FORBIDDEN_OBJECT_PATTERN" "$TMP/noheap.closure.objdump" || true
} | wc -l )
MCC_NEW_REFS=$( { grep -Eih 'MCC_New|CJ_MCC_New' "$TMP/noheap.closure.ll" || true
    grep -Eih 'R_X86_64_.*(MCC_New|CJ_MCC_New)' "$TMP/noheap.closure.objdump" || true
} | wc -l )
NOHEAP_ILLEGAL_AS1_CASTS=$(grep -Ec 'addrspacecast .*addrspace\(1\)\* .* to i8\*' \
    "$TMP/noheap.closure.ll" || true)
if [[ $NOHEAP_FINAL_BC -eq 0 || $NOHEAP_OBJECTS -eq 0 || $REACHABLE_DEFS -eq 0 ||
      $SCANNED_DEFS -ne $REACHABLE_DEFS || $MISSING_DEFS -ne 0 ||
      $CLOSURE_COMPONENTS -ne 4 ||
      $FORBIDDEN_REFS -ne 0 || $MCC_NEW_REFS -ne 0 ||
      $NOHEAP_ILLEGAL_AS1_CASTS -ne 0 ]] ||
   ! grep -q 'PagePoolInitNoHeapRoot' "$TMP/noheap.closure.ll" ||
   ! grep -q 'PAGE_POOL_MUTEX_CONSTRUCTED' "$TMP/noheap.closure.ll"; then
    echo "PAGEPOOL_NOHEAP FAIL objects=$NOHEAP_OBJECTS final_bc=$NOHEAP_FINAL_BC reachable=$REACHABLE_DEFS scanned=$SCANNED_DEFS missing=$MISSING_DEFS forbidden=$FORBIDDEN_REFS mcc=$MCC_NEW_REFS" >&2
    sed 's/^/missing_final /' "$TMP/noheap.missing_final" >&2
    sed 's/^/missing_object /' "$TMP/noheap.missing_object" >&2
    grep -Ein "$FORBIDDEN_IR_PATTERN" "$TMP/noheap.closure.ll" >&2 || true
    grep -Ein "$FORBIDDEN_OBJECT_PATTERN" "$TMP/noheap.closure.objdump" >&2 || true
    exit 1
fi

NOHEAP_EXEC_SRC="$TMP/rt.common.noheap.exec"
cp -a "$ROOT/src/rt.common" "$NOHEAP_EXEC_SRC"
cp "$ROOT/test/parity/common/pagepool_noheap_probe.cj" "$NOHEAP_EXEC_SRC/PagePoolNoHeapProbe.cj"
cp "$ROOT/test/parity/common/pagepool_noheap_driver.cj" "$NOHEAP_EXEC_SRC/PagePoolNoHeapDriver.cj"
(cd "$TMP" && "$SELFHOST_CJC" --package "$NOHEAP_EXEC_SRC" --import-path "$TMP" \
    --int-overflow wrapping -Woff unused "$TMP/librt.heap.allocator.a" \
    "$TMP/librt.sync.a" "$TMP/librt.base.a" "$TMP/Futex.o" "$TMP/Panic.o" \
    "$TMP/Atomic.o" "$TMP/PagePoolMutex.o" --link-option=-lstdc++ --link-option=-lgcc_s \
    -o "$TMP/pagepool_noheap_exec")
NOHEAP_EXEC_OUTPUT=$("$TMP/pagepool_noheap_exec")
if [[ "$NOHEAP_EXEC_OUTPUT" != 'PAGEPOOL_NOHEAP_EXEC bump=8 reuse=PASS overflow=PASS fini=PASS' ]]; then
    echo "PAGEPOOL_NOHEAP execution FAIL" >&2
    printf '%s\n' "$NOHEAP_EXEC_OUTPUT" >&2
    exit 1
fi
echo "PAGEPOOL_NOHEAP roots=${#ROOT_SYMBOLS[@]} objects=$NOHEAP_OBJECTS final_bc=$NOHEAP_FINAL_BC executables=1 mcc_new_refs=$MCC_NEW_REFS status=PASS"
echo "PAGEPOOL_NOHEAP_CLOSURE reachable_defs=$REACHABLE_DEFS scanned_defs=$SCANNED_DEFS packages=rt.common,rt.heap.allocator missing=$MISSING_DEFS status=PASS"
echo "PAGEPOOL_BINARIES cpp_sha256=$(sha256sum "$TMP/pagepool_ref" | awk '{print $1}') cj_sha256=$(sha256sum "$TMP/pagepool_cj" | awk '{print $1}') noheap_sha256=$(sha256sum "$TMP/pagepool_noheap_exec" | awk '{print $1}')"

df -h / | tail -n 1 | sed 's/^/PAGEPOOL_DISK_AFTER /'
echo "run_pagepool_probe: PASS"
