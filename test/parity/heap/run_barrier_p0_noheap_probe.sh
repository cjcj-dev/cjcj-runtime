#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH"
export cjHeapSize=24GB
LLVM_LINK="$CANGJIE_HOME/third_party/llvm/bin/llvm-link"
LLVM_DIS="$CANGJIE_HOME/third_party/llvm/bin/llvm-dis"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_barrier_p0_noheap.XXXXXX")
trap 'find "$TMP" -depth -delete' EXIT
mkdir -p "$TMP/lib"

declare -A PRE=()
declare -A FINAL=()
PACKAGE_TEMPS=()
build_package() {
    local name=$1 source=$2
    local temps="$TMP/$name.temps"
    mkdir -p "$temps"
    "$SELFHOST_CJC" --package "$source" --output-type=staticlib --import-path "$TMP/lib" \
        --save-temps "$temps" --int-overflow wrapping -O2 -Woff unused \
        --output-dir "$TMP/lib" -o "lib$name.a"
    mapfile -t pre_bc < <(find "$temps" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
    mapfile -t final_bc < <(find "$temps" -maxdepth 1 -type f -name '*.opt.bc' | sort)
    [[ ${#pre_bc[@]} -gt 0 && ${#final_bc[@]} -gt 0 ]]
    "$LLVM_LINK" "${pre_bc[@]}" -o "$TMP/$name.pre.bc"
    "$LLVM_LINK" "${final_bc[@]}" -o "$TMP/$name.final.bc"
    PRE[$name]="$TMP/$name.pre.bc"
    FINAL[$name]="$TMP/$name.final.bc"
    PACKAGE_TEMPS+=("$temps")
}

build_package rt.base "$ROOT/src/rt.base"
build_package rt.sync "$ROOT/src/rt.sync"
build_package rt.gc "$ROOT/src/rt.gc"
build_package rt.objectmodel "$ROOT/src/rt.objectmodel"

NOHEAP_SRC="$TMP/rt.heap.allocator.noheap"
cp -a "$ROOT/src/rt.heap.allocator" "$NOHEAP_SRC"
cp "$ROOT/test/parity/heap/barrier_p0_noheap_roots.cj" "$NOHEAP_SRC/Roots.cj"
build_package rt.heap.allocator.noheap "$NOHEAP_SRC"

"$LLVM_LINK" --only-needed "${PRE[rt.heap.allocator.noheap]}" "${PRE[rt.objectmodel]}" \
    "${PRE[rt.gc]}" "${PRE[rt.sync]}" "${PRE[rt.base]}" \
    -o "$TMP/closure.pre.bc"
"$LLVM_LINK" --only-needed "${FINAL[rt.heap.allocator.noheap]}" "${FINAL[rt.objectmodel]}" \
    "${FINAL[rt.gc]}" "${FINAL[rt.sync]}" "${FINAL[rt.base]}" \
    -o "$TMP/closure.final.bc"
"$LLVM_DIS" "$TMP/closure.pre.bc" -o "$TMP/closure.pre.ll"
"$LLVM_DIS" "$TMP/closure.final.bc" -o "$TMP/closure.final.ll"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/Atomic.cpp" -o "$TMP/Atomic.o"
objdump -dr "$TMP/Atomic.o" > "$TMP/Atomic.objdump"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
objdump -dr "$TMP/Panic.o" > "$TMP/Panic.objdump"

ANALYZER=(python3 "$ROOT/test/parity/heap/barrier_p0_closure.py"
    --pre "$TMP/closure.pre.ll" --final "$TMP/closure.final.ll")
for temps in "${PACKAGE_TEMPS[@]}"; do
    while IFS= read -r object; do
        dump="$TMP/$(basename "$temps").$(basename "$object").objdump"
        objdump -dr "$object" > "$dump"
        ANALYZER+=(--object "$dump")
    done < <(find "$temps" -maxdepth 1 -type f -name '*.o' | sort)
done
ANALYZER+=(--native "$TMP/Atomic.objdump" --native "$TMP/Panic.objdump")
"${ANALYZER[@]}"
for injection in missing-root extra-root forbidden-final forbidden-object; do
    set +e
    "${ANALYZER[@]}" --inject "$injection" > "$TMP/$injection.log" 2>&1
    rc=$?
    set -e
    [[ $rc -ne 0 ]]
    grep -Fq "BARRIER_P0_CLOSURE FAIL injection=$injection" "$TMP/$injection.log"
done
echo 'BARRIER_P0_NEGATIVES missing_root=REJECT extra_root=REJECT forbidden_final=REJECT forbidden_object=REJECT status=PASS'

cp "$ROOT/test/parity/heap/barrier_p0_noheap_driver.cj" "$NOHEAP_SRC/Driver.cj"
CJTHREAD_INCLUDES=()
while IFS= read -r directory; do CJTHREAD_INCLUDES+=("-I$directory"); done \
    < <(find "$RUNTIME_ROOT/src/CJThread/src" -type d | sort)
CPP_FLAGS=(-std=c++17 -O2 -fPIC -DMRT_USE_CJTHREAD_RENAME -I"$RUNTIME_ROOT/include"
    -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/output/temp/include"
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    "${CJTHREAD_INCLUDES[@]}")
g++ "${CPP_FLAGS[@]}" -c "$ROOT/test/parity/objectmodel/baseobject_size_bridge.cpp" -o "$TMP/BaseObjectSizeBridge.o"
g++ "${CPP_FLAGS[@]}" -c "$ROOT/rt0/AllocBufferNative.cpp" -o "$TMP/AllocBufferNative.o"
g++ "${CPP_FLAGS[@]}" -c "$ROOT/rt0/ScopedSaferegion.cpp" -o "$TMP/ScopedSaferegion.o"
for source in Futex Atomic SpinLock PagePoolMutex; do
    g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/$source.cpp" -o "$TMP/$source.o"
done
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/GCTibShift.cpp" -o "$TMP/GCTibShift.o"
"$SELFHOST_CJC" --package "$NOHEAP_SRC" --import-path "$TMP/lib" --int-overflow wrapping -O2 -Woff unused \
    "$TMP/lib/librt.objectmodel.a" "$TMP/lib/librt.gc.a" \
    "$TMP/lib/librt.sync.a" "$TMP/lib/librt.base.a" "$TMP/BaseObjectSizeBridge.o" \
    "$TMP/AllocBufferNative.o" "$TMP/ScopedSaferegion.o" "$TMP/GCTibShift.o" \
    "$TMP/Futex.o" "$TMP/Panic.o" "$TMP/Atomic.o" "$TMP/SpinLock.o" "$TMP/PagePoolMutex.o" \
    -L"$CPP_RUNTIME_LIB" --link-option=-lcangjie-runtime --link-option=-lstdc++ \
    --link-option=-lgcc_s -o "$TMP/root_probe"
"$TMP/root_probe"
echo "BARRIER_P0_NOHEAP_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_barrier_p0_noheap_probe: PASS'
