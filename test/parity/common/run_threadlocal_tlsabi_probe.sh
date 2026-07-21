#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
SELFHOST_RUNTIME=/root/cj_build/cjcj/target/release/runtime/lib/linux_x86_64_cjnative
export PATH=/root/.cjv/bin:$PATH
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

LLVM="$CANGJIE_HOME/third_party/llvm/bin"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_threadlocal_tlsabi.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "threadlocal TLS ABI execution requires Linux x86_64" >&2
    exit 2
fi
test -x "$SELFHOST_CJC"
test -f "$CPP_RUNTIME_LIB/libcangjie-runtime.so"
test -f "$SELFHOST_RUNTIME/libcangjie-runtime.so"
df -h / | tail -n 1 | sed 's/^/THREADLOCAL_DISK_BEFORE /'
echo "THREADLOCAL_COMPILER path=$SELFHOST_CJC status=PASS"

build_package() {
    local package=$1
    local source=$2
    local output=$3
    shift 3
    (cd "$TMP" && "$SELFHOST_CJC" --package "$source" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" \
        "$@" -o "$output")
}

# Build the original-header C++ oracle against the original runtime repository.
g++ -std=c++14 -O2 -pthread -DTHREADLOCAL_ORACLE \
    -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/common/threadlocal_tlsabi_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -o "$TMP/threadlocal_oracle"
LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib" \
    "$TMP/threadlocal_oracle" > "$TMP/cpp.transcript"

# Build the package closure and a probe-owned copy of rt.common with final/pre-opt objects.
build_package rt.base "$ROOT/src/rt/base" librt.base.a
build_package rt.sync "$ROOT/src/rt/sync" librt.sync.a
build_package rt.heap.allocator "$ROOT/src/rt/heap/allocator" librt.heap.allocator.a
cp -a "$ROOT/src/rt/common" "$TMP/rt.common.probe"
cp "$ROOT/test/parity/common/threadlocal_tlsabi_probe.cj" \
    "$TMP/rt.common.probe/ThreadLocalTLSABIProbe.cj"
mkdir -p "$TMP/common_temps"
build_package rt.common "$TMP/rt.common.probe" librt.common.probe.a \
    --save-temps "$TMP/common_temps"

PRE_BC=()
for bc in "$TMP/common_temps"/[0-9]*.bc; do
    [[ "$bc" == *.opt.bc ]] || PRE_BC+=("$bc")
done
"$LLVM/llvm-link" "${PRE_BC[@]}" -o "$TMP/common.pre.bc"
"$LLVM/llvm-dis" "$TMP/common.pre.bc" -o "$TMP/common.pre.ll"

# Derive the Cangjie record layout from the selfhost-generated LLVM type.
mapfile -t TLS_TYPES < <(grep -F '%"record.rt.common:ThreadLocalData" = type ' \
    "$TMP/common.pre.ll" | sort -u)
if [[ ${#TLS_TYPES[@]} -ne 1 ]]; then
    echo "THREADLOCAL_LAYOUT type_count=${#TLS_TYPES[@]} status=FAIL" >&2
    exit 1
fi
TLS_RHS=${TLS_TYPES[0]#*= type }
EXPECTED_RHS='{ i8*, i8*, i8*, i8*, i8*, i8*, i64, i64, i8*, i32, i1, i8* }'
if [[ "$TLS_RHS" != "$EXPECTED_RHS" ]]; then
    echo "THREADLOCAL_LAYOUT type=$TLS_RHS status=FAIL" >&2
    exit 1
fi
mapfile -t DATALAYOUTS < <(grep '^target datalayout = ' "$TMP/common.pre.ll" | sort -u)
if [[ ${#DATALAYOUTS[@]} -ne 1 ]]; then
    echo "THREADLOCAL_LAYOUT datalayout_count=${#DATALAYOUTS[@]} status=FAIL" >&2
    exit 1
fi
cat > "$TMP/layout.ll" <<EOF
${DATALAYOUTS[0]}
%TLS = type $TLS_RHS
%TLSAlign = type { i8, %TLS }
@tls_size = global i64 ptrtoint (%TLS* getelementptr (%TLS, %TLS* null, i32 1) to i64)
@tls_align = global i64 ptrtoint (%TLS* getelementptr (%TLSAlign, %TLSAlign* null, i32 0, i32 1) to i64)
@tls_buffer = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 0) to i64)
@tls_mutator = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 1) to i64)
@tls_cjthread = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 2) to i64)
@tls_schedule = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 3) to i64)
@tls_preempt = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 4) to i64)
@tls_protect = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 5) to i64)
@tls_safepoint = global i64 ptrtoint (i64* getelementptr (%TLS, %TLS* null, i32 0, i32 6) to i64)
@tls_tid = global i64 ptrtoint (i64* getelementptr (%TLS, %TLS* null, i32 0, i32 7) to i64)
@tls_foreign = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 8) to i64)
@tls_type = global i64 ptrtoint (i32* getelementptr (%TLS, %TLS* null, i32 0, i32 9) to i64)
@tls_processor = global i64 ptrtoint (i1* getelementptr (%TLS, %TLS* null, i32 0, i32 10) to i64)
@tls_cache = global i64 ptrtoint (i8** getelementptr (%TLS, %TLS* null, i32 0, i32 11) to i64)
EOF
"$LLVM/llvm-as" "$TMP/layout.ll" -o "$TMP/layout.bc"
"$LLVM/opt" -S -passes=globalopt "$TMP/layout.bc" -o "$TMP/layout.folded.ll"
layout_value() {
    awk -v symbol="@$1" '$1 == symbol { print $NF }' "$TMP/layout.folded.ll"
}
CJ_TLS_SIZE=$(layout_value tls_size)
CJ_TLS_ALIGN=$(layout_value tls_align)
CJ_TLS_BUFFER=$(layout_value tls_buffer)
CJ_TLS_MUTATOR=$(layout_value tls_mutator)
CJ_TLS_CJTHREAD=$(layout_value tls_cjthread)
CJ_TLS_SCHEDULE=$(layout_value tls_schedule)
CJ_TLS_PREEMPT=$(layout_value tls_preempt)
CJ_TLS_PROTECT=$(layout_value tls_protect)
CJ_TLS_SAFEPOINT=$(layout_value tls_safepoint)
CJ_TLS_TID=$(layout_value tls_tid)
CJ_TLS_FOREIGN=$(layout_value tls_foreign)
CJ_TLS_TYPE=$(layout_value tls_type)
CJ_TLS_PROCESSOR=$(layout_value tls_processor)
CJ_TLS_CACHE=$(layout_value tls_cache)
LAYOUT_VALUES="$CJ_TLS_SIZE $CJ_TLS_ALIGN $CJ_TLS_BUFFER $CJ_TLS_MUTATOR $CJ_TLS_CJTHREAD $CJ_TLS_SCHEDULE $CJ_TLS_PREEMPT $CJ_TLS_PROTECT $CJ_TLS_SAFEPOINT $CJ_TLS_TID $CJ_TLS_FOREIGN $CJ_TLS_TYPE $CJ_TLS_PROCESSOR $CJ_TLS_CACHE"
if [[ "$LAYOUT_VALUES" != '88 8 0 8 16 24 32 40 48 56 64 72 76 80' ]]; then
    echo "THREADLOCAL_LAYOUT values=$LAYOUT_VALUES status=FAIL" >&2
    exit 1
fi

CJ_DEFINES=(
    -DCJ_TLS_SIZE="$CJ_TLS_SIZE" -DCJ_TLS_ALIGN="$CJ_TLS_ALIGN"
    -DCJ_TLS_BUFFER="$CJ_TLS_BUFFER" -DCJ_TLS_MUTATOR="$CJ_TLS_MUTATOR"
    -DCJ_TLS_CJTHREAD="$CJ_TLS_CJTHREAD" -DCJ_TLS_SCHEDULE="$CJ_TLS_SCHEDULE"
    -DCJ_TLS_PREEMPT="$CJ_TLS_PREEMPT" -DCJ_TLS_PROTECT="$CJ_TLS_PROTECT"
    -DCJ_TLS_SAFEPOINT="$CJ_TLS_SAFEPOINT" -DCJ_TLS_TID="$CJ_TLS_TID"
    -DCJ_TLS_FOREIGN="$CJ_TLS_FOREIGN" -DCJ_TLS_TYPE="$CJ_TLS_TYPE"
    -DCJ_TLS_PROCESSOR="$CJ_TLS_PROCESSOR" -DCJ_TLS_CACHE="$CJ_TLS_CACHE"
)
g++ -std=c++14 -O2 -pthread -fPIC "${CJ_DEFINES[@]}" \
    -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    -c "$ROOT/test/parity/common/threadlocal_tlsabi_ref.cpp" -o "$TMP/threadlocal_driver.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$TMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/PagePoolMutex.cpp" -o "$TMP/PagePoolMutex.o"

(cd "$TMP" && "$SELFHOST_CJC" "$ROOT/test/parity/common/threadlocal_tlsabi_driver.cj" \
    -Woff unused --import-path "$TMP" --int-overflow wrapping "$TMP/threadlocal_driver.o" \
    "$TMP/librt.common.probe.a" "$TMP/librt.heap.allocator.a" "$TMP/librt.sync.a" \
    "$TMP/librt.base.a" "$TMP/Futex.o" "$TMP/Panic.o" "$TMP/Atomic.o" \
    "$TMP/PagePoolMutex.o" --link-option=-lstdc++ --link-option=-lgcc_s \
    --link-option=-lpthread -o "$TMP/threadlocal_cj")
"$TMP/threadlocal_cj" > "$TMP/cj.transcript"
if ! cmp "$TMP/cpp.transcript" "$TMP/cj.transcript"; then
    diff -u "$TMP/cpp.transcript" "$TMP/cj.transcript" | head -n 240 >&2 || true
    echo "THREADLOCAL_TRANSCRIPT cmp=FAIL" >&2
    exit 1
fi
cat "$TMP/cj.transcript"
echo "THREADLOCAL_TRANSCRIPT lines=$(wc -l < "$TMP/cj.transcript") bytes=$(wc -c < "$TMP/cj.transcript") sha256=$(sha256sum "$TMP/cj.transcript" | awk '{print $1}') cmp=PASS"
echo "THREADLOCAL_BINARIES cpp_sha256=$(sha256sum "$TMP/threadlocal_oracle" | awk '{print $1}') cj_sha256=$(sha256sum "$TMP/threadlocal_cj" | awk '{print $1}') common_archive_sha256=$(sha256sum "$TMP/librt.common.probe.a" | awk '{print $1}')"

# Both production calls must remain imports and the Cangjie objects must own no TLS store.
MRT_UNDEFINED=$(nm -u "$TMP/librt.common.probe.a" | awk '$2 == "MRT_GetThreadLocalData" {++n} END {print n+0}')
CHECK_UNDEFINED=$(nm -u "$TMP/librt.common.probe.a" | awk '$2 == "CJ_MCC_CheckThreadLocalDataOffset" {++n} END {print n+0}')
MRT_DEFINED=$(nm --defined-only "$TMP/librt.common.probe.a" | awk '$3 == "MRT_GetThreadLocalData" {++n} END {print n+0}')
CHECK_DEFINED=$(nm --defined-only "$TMP/librt.common.probe.a" | awk '$3 == "CJ_MCC_CheckThreadLocalDataOffset" {++n} END {print n+0}')
SHADOW_DEFINED=$(nm --defined-only "$TMP/librt.common.probe.a" | \
    awk '$3 == "_ZN12MapleRuntime15threadLocalDataE" || $3 == "threadLocalData" {++n} END {print n+0}')
TLS_DEFINED=$(for object in "$TMP/common_temps"/*.o; do readelf -Ws "$object"; done | \
    awk '$4 == "TLS" && $7 != "UND" {++n} END {print n+0}')
MRT_RELOCS=$(for object in "$TMP/common_temps"/*.o; do readelf -rW "$object"; done | \
    grep -c 'MRT_GetThreadLocalData' || true)
CHECK_RELOCS=$(for object in "$TMP/common_temps"/*.o; do readelf -rW "$object"; done | \
    grep -c 'CJ_MCC_CheckThreadLocalDataOffset' || true)
MRT_RUNTIME=$(nm -D "$SELFHOST_RUNTIME/libcangjie-runtime.so" | \
    awk '$3 ~ /^MRT_GetThreadLocalData(@@.*)?$/ {++n} END {print n+0}')
CHECK_RUNTIME=$(nm -D "$SELFHOST_RUNTIME/libcangjie-runtime.so" | \
    awk '$3 ~ /^CJ_MCC_CheckThreadLocalDataOffset(@@.*)?$/ {++n} END {print n+0}')
MRT_EXE=$(readelf -Ws "$TMP/threadlocal_cj" | \
    awk '$7 == "UND" && $8 ~ /^MRT_GetThreadLocalData(@.*)?$/ {++n} END {print n+0}')
CHECK_EXE=$(readelf -Ws "$TMP/threadlocal_cj" | \
    awk '$7 == "UND" && $8 ~ /^CJ_MCC_CheckThreadLocalDataOffset(@.*)?$/ {++n} END {print n+0}')
RUNTIME_RESOLVED=$(ldd "$TMP/threadlocal_cj" | \
    awk '/libcangjie-runtime.so => \/.*libcangjie-runtime.so/ {++n} END {print n+0}')
if [[ $MRT_UNDEFINED -lt 1 || $CHECK_UNDEFINED -lt 1 || $MRT_DEFINED -ne 0 ||
      $CHECK_DEFINED -ne 0 || $SHADOW_DEFINED -ne 0 || $TLS_DEFINED -ne 0 ||
      $MRT_RELOCS -lt 1 || $CHECK_RELOCS -lt 1 || $MRT_RUNTIME -ne 1 ||
      $CHECK_RUNTIME -ne 1 || $MRT_EXE -lt 1 || $CHECK_EXE -lt 1 ||
      $RUNTIME_RESOLVED -ne 1 ]]; then
    echo "THREADLOCAL_SYMBOLS mrt_undef=$MRT_UNDEFINED check_undef=$CHECK_UNDEFINED mrt_def=$MRT_DEFINED check_def=$CHECK_DEFINED shadow=$SHADOW_DEFINED tls=$TLS_DEFINED mrt_reloc=$MRT_RELOCS check_reloc=$CHECK_RELOCS status=FAIL" >&2
    exit 1
fi
echo "THREADLOCAL_SYMBOLS runtime_imports=2 mrt_relocs=$MRT_RELOCS check_relocs=$CHECK_RELOCS tls_defs=0 shadow_defs=0 runtime_so=libcangjie-runtime.so status=PASS"

# Traverse the pre-opt root, then require every reachable definition in final BC and objects.
"$LLVM/opt" -passes=print-callgraph -disable-output "$TMP/common.pre.bc" \
    2> "$TMP/noheap.callgraph"
awk '
/^Call graph node for function:/ {
    line=$0; sub(/^.*function: '\''/, "", line); sub(/'\''.*$/, "", line); current=line; next
}
/calls function '\''/ {
    line=$0; sub(/^.*calls function '\''/, "", line); sub(/'\''.*$/, "", line)
    if (current != "") print current "\t" line
}
' "$TMP/noheap.callgraph" > "$TMP/noheap.calls.tsv"
ROOT_SYMBOL=_CN9rt.common25ThreadLocalDataNoHeapRootHr
declare -A SEEN=(["$ROOT_SYMBOL"]=1)
QUEUE=("$ROOT_SYMBOL")
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
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name); print name
}' "$TMP/common.pre.ll" | sort -u > "$TMP/noheap.pre.defined"
comm -12 "$TMP/noheap.symbols" "$TMP/noheap.pre.defined" > "$TMP/noheap.reachable_defs"
comm -23 "$TMP/noheap.symbols" "$TMP/noheap.pre.defined" > "$TMP/noheap.external"
printf '%s\n' CJ_MCC_CheckThreadLocalDataOffset MRT_GetThreadLocalData \
    _CNatXPG_12toUIntNativeHv _CNatXPG_plHl | sort > "$TMP/noheap.allowed_external"
if ! cmp "$TMP/noheap.allowed_external" "$TMP/noheap.external"; then
    diff -u "$TMP/noheap.allowed_external" "$TMP/noheap.external" >&2 || true
    echo "THREADLOCAL_TLSABI_NOHEAP unexpected_external status=FAIL" >&2
    exit 1
fi

awk -v symbols="$TMP/noheap.reachable_defs" '
BEGIN { while ((getline symbol < symbols) > 0) keep[symbol]=1 }
/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name); emit=(name in keep)
}
emit { print; if ($0 ~ /^}/) emit=0 }
' "$TMP/common.pre.ll" > "$TMP/noheap.pre.closure.ll"
: > "$TMP/noheap.final_defs"
: > "$TMP/noheap.final.closure.ll"
for bc in "$TMP/common_temps"/*.opt.bc; do
    ir="$TMP/$(basename "${bc%.bc}").ll"
    "$LLVM/llvm-dis" "$bc" -o "$ir"
    awk -v symbols="$TMP/noheap.reachable_defs" -v defs="$TMP/noheap.final_defs" '
    BEGIN { while ((getline symbol < symbols) > 0) keep[symbol]=1 }
    /^define / {
        name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
        emit=(name in keep); if (emit) print name >> defs
    }
    emit { print; if ($0 ~ /^}/) emit=0 }
    ' "$ir" >> "$TMP/noheap.final.closure.ll"
done
sort -u -o "$TMP/noheap.final_defs" "$TMP/noheap.final_defs"
: > "$TMP/noheap.object_defs"
: > "$TMP/noheap.object.closure.txt"
for object in "$TMP/common_temps"/[0-9]*.o; do
    dump="$TMP/$(basename "$object").objdump"
    objdump -dr "$object" > "$dump"
    awk -v symbols="$TMP/noheap.reachable_defs" -v defs="$TMP/noheap.object_defs" '
    BEGIN { while ((getline symbol < symbols) > 0) keep[symbol]=1 }
    /^[[:xdigit:]]+ <.*>:/ {
        name=$0; sub(/^[^<]*</, "", name); sub(/>:[[:space:]]*$/, "", name)
        emit=(name in keep); if (emit) print name >> defs
    }
    emit { print }
    ' "$dump" >> "$TMP/noheap.object.closure.txt"
done
sort -u -o "$TMP/noheap.object_defs" "$TMP/noheap.object_defs"
comm -23 "$TMP/noheap.reachable_defs" "$TMP/noheap.final_defs" > "$TMP/noheap.missing_final"
comm -23 "$TMP/noheap.reachable_defs" "$TMP/noheap.object_defs" > "$TMP/noheap.missing_object"
REACHABLE_DEFS=$(wc -l < "$TMP/noheap.reachable_defs")
MISSING_FINAL=$(wc -l < "$TMP/noheap.missing_final")
MISSING_OBJECT=$(wc -l < "$TMP/noheap.missing_object")
FORBIDDEN_IR='MCC_New|RawArrayAllocate|llvm\.cj\.alloca\.generic|std\.core[:.]String|std\.core[:.]Array|ArrayList|HashMap|Create[A-Za-z]*Exception|ThrowException|closure|llvm\.memcpy.*i64 88'
FORBIDDEN_OBJECT='R_X86_64_.*(MCC_New|RawArrayAllocate|StringBuilder|ArrayList|HashMap|Exception|ThrowException|memcpy)'
FORBIDDEN_REFS=$( { grep -Eih "$FORBIDDEN_IR" "$TMP/noheap.pre.closure.ll" "$TMP/noheap.final.closure.ll" || true
    grep -Eih "$FORBIDDEN_OBJECT" "$TMP/noheap.object.closure.txt" || true
} | wc -l )
MCC_NEW_REFS=$( { grep -Eih 'MCC_New|CJ_MCC_New' "$TMP/noheap.pre.closure.ll" "$TMP/noheap.final.closure.ll" || true
    grep -Eih 'R_X86_64_.*(MCC_New|CJ_MCC_New)' "$TMP/noheap.object.closure.txt" || true
} | wc -l )
AGGREGATE_COPY=$( { grep -Eh 'llvm\.memcpy.*i64 88' \
    "$TMP/noheap.pre.closure.ll" "$TMP/noheap.final.closure.ll" || true; } | wc -l )
ILLEGAL_AS1=$( { grep -Eh 'addrspacecast .*addrspace\(1\)\* .* to [^ ]+\*' \
    "$TMP/noheap.pre.closure.ll" "$TMP/noheap.final.closure.ll" || true; } | wc -l )
if [[ $REACHABLE_DEFS -eq 0 || $MISSING_FINAL -ne 0 || $MISSING_OBJECT -ne 0 ||
      $FORBIDDEN_REFS -ne 0 || $MCC_NEW_REFS -ne 0 || $AGGREGATE_COPY -ne 0 ||
      $ILLEGAL_AS1 -ne 0 ]] || ! grep -q "$ROOT_SYMBOL" "$TMP/noheap.pre.closure.ll"; then
    echo "THREADLOCAL_TLSABI_NOHEAP reachable=$REACHABLE_DEFS missing_final=$MISSING_FINAL missing_object=$MISSING_OBJECT forbidden=$FORBIDDEN_REFS mcc=$MCC_NEW_REFS memcpy88=$AGGREGATE_COPY illegal_as1=$ILLEGAL_AS1 status=FAIL" >&2
    sed 's/^/missing_final /' "$TMP/noheap.missing_final" >&2
    sed 's/^/missing_object /' "$TMP/noheap.missing_object" >&2
    exit 1
fi
echo "THREADLOCAL_TLSABI_NOHEAP roots=1 reachable_defs=$REACHABLE_DEFS final_defs=$REACHABLE_DEFS object_defs=$REACHABLE_DEFS approved_runtime_leaves=4 mcc_new_refs=0 memcpy88=0 illegal_as1_to_as0=0 status=PASS"

echo "THREADLOCAL_PLATFORM linux_x86_64=EXECUTED aarch64_tbi=SOURCE_PRESERVED_UNEXECUTED non_linux_layouts=UNEXECUTED"

# Required existing PagePool regression and all runtime package builds use only selfhost cjc.
bash "$ROOT/test/parity/common/run_pagepool_probe.sh"
rm -rf "$TMP/package_build"
mkdir -p "$TMP/package_build"
for package in rt.base rt.sync rt.heap.allocator rt.common rt.demangle rt.stackmap rt.abi; do
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$package" \
        --output-type=staticlib --int-overflow wrapping -Woff unused \
        --import-path "$TMP/package_build" --output-dir "$TMP/package_build" \
        -o "lib$package.a")
    archive="$TMP/package_build/lib$package.a"
    echo "RUNTIME_PACKAGE_BUILD package=$package archive_size=$(stat -c %s "$archive") status=PASS"
done

df -h / | tail -n 1 | sed 's/^/THREADLOCAL_DISK_AFTER /'
echo "run_threadlocal_tlsabi_probe: PASS"
