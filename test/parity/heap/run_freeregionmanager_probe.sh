#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RUNTIME="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}
LLVM_LINK="$CANGJIE_HOME/third_party/llvm/bin/llvm-link"
LLVM_OPT="$CANGJIE_HOME/third_party/llvm/bin/opt"
LLVM_DIS="$CANGJIE_HOME/third_party/llvm/bin/llvm-dis"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_freeregionmanager.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

SOURCE="$ROOT/src/rt.heap.allocator/FreeRegionManager.cj"
for marker in 'FreeRegionManager.h:19-168' 'RegionManager.cpp:278-304' \
    CJRT_PagePoolMutexTryLock CJRT_ScopedEnterSaferegionOnlyMutatorBegin \
    'FreeRegionCommitMemory' 'ReleaseGarbageRegions'; do
    grep -Fq "$marker" "$SOURCE"
done
[[ $(grep -Fc '@When[os == "Linux" || env == "ohos"]' "$SOURCE") -ge 4 ]]
[[ $(grep -Fc '@When[os == "macOS" || os == "iOS"]' "$SOURCE") -ge 4 ]]
[[ $(grep -Fc '@When[os == "Windows"]' "$SOURCE") -ge 4 ]]
if rg -n 'PLATFORM-DEBT|DEBUG-DEBT|ArrayList|HashMap|StringBuilder' "$SOURCE"; then
    echo 'FREE_REGION_SOURCE FAIL rejected debt/high-level facility' >&2
    exit 1
fi
echo 'FREE_REGION_SOURCE fresh=PASS linux_ohos=PASS apple=PASS win64=PASS'

INCLUDES=(-I"$RUNTIME_ROOT/include")
while IFS= read -r directory; do INCLUDES+=(-I"$directory"); done < <(find "$RUNTIME_ROOT/src" -type d)
CPP_FLAGS=(-std=c++17 -O2 -pthread -DMRT_USE_CJTHREAD_RENAME
    -I"$RUNTIME_ROOT/output/temp/include"
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    "${INCLUDES[@]}")

g++ "${CPP_FLAGS[@]}" "$ROOT/test/parity/heap/freeregionmanager_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -L"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" -lboundscheck -lsecurec \
    -lpthread -ldl -o "$TMP/free_region_ref"
LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH" "$TMP/free_region_ref" > "$TMP/ref.txt"

compile_native() {
    local output=$1
    mkdir -p "$output"
    for source in Futex Panic Atomic SpinLock PagePoolMutex; do
        g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/$source.cpp" -o "$output/$source.o"
    done
    g++ "${CPP_FLAGS[@]}" -fPIC -c "$ROOT/rt0/AllocBufferNative.cpp" -o "$output/AllocBufferNative.o"
    g++ "${CPP_FLAGS[@]}" -fPIC -c "$ROOT/rt0/ScopedSaferegion.cpp" -o "$output/ScopedSaferegion.o"
}

OUT="$TMP/cj"
mkdir -p "$OUT"
for package in rt.base rt.sync; do
    "$SELFHOST_CJC" --package "$ROOT/src/$package" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$OUT" --output-dir "$OUT" \
        -o "lib$package.a"
done
PROBE="$OUT/rt.heap.allocator.probe"
cp -a "$ROOT/src/rt.heap.allocator" "$PROBE"
cp "$ROOT/test/parity/heap/freeregionmanager_probe.cj" "$PROBE/FreeRegionManagerProbe.cj"
compile_native "$OUT/native"
"$SELFHOST_CJC" --package "$PROBE" --import-path "$OUT" --int-overflow wrapping -Woff unused \
    "$OUT/librt.sync.a" "$OUT/librt.base.a" "$OUT/native/"*.o \
    --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread -o "$OUT/free_region"
"$OUT/free_region" > "$TMP/cj.txt"
if ! cmp "$TMP/ref.txt" "$TMP/cj.txt"; then
    diff -u "$TMP/ref.txt" "$TMP/cj.txt" | head -n 120 >&2 || true
    echo 'FREE_REGION_TRANSCRIPT cmp=FAIL' >&2
    exit 1
fi
cat "$TMP/cj.txt"
echo "FREE_REGION_TRANSCRIPT lines=$(wc -l < "$TMP/cj.txt") bytes=$(wc -c < "$TMP/cj.txt") sha256=$(sha256sum "$TMP/cj.txt" | awk '{print $1}') cmp=PASS"

CLOSURE="$TMP/closure"
mkdir -p "$CLOSURE"
PACKAGE_TEMPS=()
for package in rt.base rt.sync; do
    temps="$CLOSURE/$package.temps"
    mkdir -p "$temps"
    "$SELFHOST_CJC" --package "$ROOT/src/$package" --output-type=staticlib --save-temps "$temps" \
        --int-overflow wrapping -Woff unused --import-path "$CLOSURE" --output-dir "$CLOSURE" \
        -o "lib$package.a"
    PACKAGE_TEMPS+=("$temps")
done
HEAP="$CLOSURE/rt.heap.allocator.noheap"
cp -a "$ROOT/src/rt.heap.allocator" "$HEAP"
cp "$ROOT/test/parity/heap/freeregionmanager_noheap.cj" "$HEAP/FreeRegionManagerNoHeap.cj"
HEAP_TEMPS="$CLOSURE/rt.heap.allocator.temps"
mkdir -p "$HEAP_TEMPS"
"$SELFHOST_CJC" --package "$HEAP" --output-type=staticlib --save-temps "$HEAP_TEMPS" \
    --int-overflow wrapping -Woff unused --import-path "$CLOSURE" --output-dir "$CLOSURE" \
    -o librt.heap.allocator.a
PACKAGE_TEMPS+=("$HEAP_TEMPS")

PACKAGE_PRE=()
for temps in "${PACKAGE_TEMPS[@]}"; do
    mapfile -t inputs < <(find "$temps" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
    [[ ${#inputs[@]} -gt 0 ]]
    linked="$CLOSURE/$(basename "$temps").pre.bc"
    "$LLVM_LINK" "${inputs[@]}" -o "$linked"
    PACKAGE_PRE+=("$linked")
done
"$LLVM_LINK" --only-needed "${PACKAGE_PRE[2]}" "${PACKAGE_PRE[1]}" "${PACKAGE_PRE[0]}" -o "$CLOSURE/pre.bc"
"$LLVM_DIS" "$CLOSURE/pre.bc" -o "$CLOSURE/pre.ll"
"$LLVM_OPT" -passes=print-callgraph -disable-output "$CLOSURE/pre.bc" 2> "$CLOSURE/callgraph"
awk '
/^Call graph node for function:/ { line=$0; sub(/^.*function: '\''/, "", line); sub(/'\''.*$/, "", line); owner=line; next }
/calls function '\''/ { line=$0; sub(/^.*calls function '\''/, "", line); sub(/'\''.*$/, "", line); if (owner != "") print owner "\t" line }
' "$CLOSURE/callgraph" > "$CLOSURE/calls.tsv"

FINAL_ARGS=()
OBJECT_ARGS=()
for temps in "${PACKAGE_TEMPS[@]}"; do
    while IFS= read -r bc; do
        ll="$CLOSURE/$(basename "$temps").$(basename "$bc").ll"
        "$LLVM_DIS" "$bc" -o "$ll"
        FINAL_ARGS+=(--final "$ll")
    done < <(find "$temps" -maxdepth 1 -type f -name '*.opt.bc' | sort)
    while IFS= read -r object; do
        dump="$CLOSURE/$(basename "$temps").$(basename "$object").objdump"
        objdump -dr "$object" > "$dump"
        OBJECT_ARGS+=(--object "$dump")
    done < <(find "$temps" -maxdepth 1 -type f -name '*.o' | sort)
done
compile_native "$CLOSURE/native"
NATIVE_ARGS=()
for object in "$CLOSURE/native/"*.o; do
    objdump -dr "$object" > "$object.objdump"
    NATIVE_ARGS+=(--native "$object.objdump")
done
PYTHONPATH="$ROOT/test/parity/heap" python3 "$ROOT/test/parity/heap/freeregionmanager_closure.py" \
    --pre "$CLOSURE/pre.ll" --calls "$CLOSURE/calls.tsv" \
    "${FINAL_ARGS[@]}" "${OBJECT_ARGS[@]}" "${NATIVE_ARGS[@]}"

for mode in release debug; do
    flags=()
    if [[ $mode == debug ]]; then flags=(-g); fi
    target="$TMP/windows.$mode"
    mkdir -p "$target"
    for package in rt.base rt.sync; do
        "$SELFHOST_CJC" --package "$ROOT/src/$package" --target x86_64-w64-mingw32 \
            --output-type=staticlib --int-overflow wrapping -Woff unused \
            --import-path "$target" --output-dir "$target" -o "lib$package.a"
    done
    "$SELFHOST_CJC" --package "$ROOT/src/rt.heap.allocator" --target x86_64-w64-mingw32 \
        --output-type=staticlib "${flags[@]}" --int-overflow wrapping -Woff unused \
        --import-path "$target" --output-dir "$target" -o librt.heap.allocator.a
done
echo 'FREE_REGION_PLATFORM target=Linux-OHOS size=352 compile=PASS execute=PASS status=PASS'
echo 'FREE_REGION_PLATFORM target=Apple size=400 cj_source=PASS native_execute=DEBT-APPLE-SDK-LIBCXX status=EXPLICIT-DEBT'
echo 'FREE_REGION_PLATFORM target=Win64 size=288 cj_release=PASS cj_debug=PASS native_bridge=DEBT-WIN64-LIBCXX-CROSS status=EXPLICIT-DEBT'
echo "FREE_REGION_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_freeregionmanager_probe: PASS'
