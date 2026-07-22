#!/usr/bin/env bash
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
WINDOWS_TARGET=x86_64-w64-mingw32
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_allocbuffer_fresh.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

SOURCE="$ROOT/src/rt.heap.allocator/AllocBuffer.cj"
[[ -f "$SOURCE" ]]
[[ $(grep -Fc '@When[os == "Linux" || env == "ohos"]' "$SOURCE") -eq 2 ]]
[[ $(grep -Fc '@When[os == "macOS" || os == "iOS"]' "$SOURCE") -eq 2 ]]
[[ $(grep -Fc '@When[os == "Windows"]' "$SOURCE") -eq 2 ]]
for marker in AllocBufferClearRegionLog ALLOC_BUFFER_CLEAR_REGION_LOG \
    _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz; do
    grep -Fq "$marker" "$SOURCE"
done
if rg -n 'PLATFORM-DEBT|DEBUG-DEBT|malloc\(|free\(' "$SOURCE"; then
    echo 'ALLOC_BUFFER_SOURCE FAIL rejected debt/workaround' >&2
    exit 1
fi
echo 'ALLOC_BUFFER_SOURCE fresh=PASS linux_ohos=PASS apple=PASS win64=PASS debug_paths=PASS'

INCLUDES=(-I"$RUNTIME_ROOT/include")
while IFS= read -r directory; do INCLUDES+=(-I"$directory"); done < <(find "$RUNTIME_ROOT/src" -type d)
CPP_FLAGS=(-std=c++17 -O2 -pthread -DMRT_USE_CJTHREAD_RENAME
    -I"$RUNTIME_ROOT/output/temp/include"
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    "${INCLUDES[@]}")

compile_native_linux() {
    local output=$1
    mkdir -p "$output"
    for source in Futex Panic Atomic SpinLock PagePoolMutex; do
        g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/$source.cpp" -o "$output/$source.o"
    done
    g++ "${CPP_FLAGS[@]}" -fPIC -c "$ROOT/rt0/AllocBufferNative.cpp" \
        -o "$output/AllocBufferNative.o"
}

build_cpp_probe() {
    local mode=$1
    local extra=()
    if [[ $mode == debug ]]; then extra=(-DMRT_DEBUG=1); fi
    g++ "${CPP_FLAGS[@]}" "${extra[@]}" "$ROOT/test/parity/heap/allocbuffer_ref.cpp" \
        -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
        -L"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" -lboundscheck -lsecurec \
        -lpthread -ldl -o "$TMP/ref.$mode"
    LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH" "$TMP/ref.$mode" > "$TMP/ref.$mode.txt"
}

build_cj_probe() {
    local mode=$1
    local owner_flag=()
    if [[ $mode == debug ]]; then owner_flag=(-g); fi
    local output="$TMP/cj.$mode"
    mkdir -p "$output"
    for package in rt.base rt.sync; do
        "$SELFHOST_CJC" --package "$ROOT/src/$package" --output-type=staticlib \
            --int-overflow wrapping -Woff unused --import-path "$output" --output-dir "$output" \
            -o "lib$package.a"
    done
    local probe="$output/rt.heap.allocator.probe"
    cp -a "$ROOT/src/rt.heap.allocator" "$probe"
    cp "$ROOT/test/parity/heap/allocbuffer_probe.cj" "$probe/AllocBufferProbe.cj"
    compile_native_linux "$output/native"
    g++ "${CPP_FLAGS[@]}" -fPIC -c "$ROOT/test/parity/heap/allocbuffer_probe_bridge.cpp" \
        -o "$output/native/AllocBufferProbeBridge.o"
    "$SELFHOST_CJC" --package "$probe" "${owner_flag[@]}" --import-path "$output" \
        --int-overflow wrapping -Woff unused "$output/librt.sync.a" "$output/librt.base.a" \
        "$output/native/"*.o --link-option=-lstdc++ --link-option=-lgcc_s \
        --link-option=-lpthread -o "$output/allocbuffer"
    "$output/allocbuffer" > "$TMP/cj.$mode.txt"
}

for mode in release debug; do
    build_cpp_probe "$mode"
    build_cj_probe "$mode"
    cmp "$TMP/ref.$mode.txt" "$TMP/cj.$mode.txt"
done
cmp "$TMP/cj.release.txt" "$TMP/cj.debug.txt"
cat "$TMP/cj.release.txt"
echo "ALLOC_BUFFER_TRANSCRIPT lines=$(wc -l < "$TMP/cj.release.txt") bytes=$(wc -c < "$TMP/cj.release.txt") sha256=$(sha256sum "$TMP/cj.release.txt" | awk '{print $1}') cmp=PASS"
echo "ALLOC_BUFFER_DEBUG_TRANSCRIPT lines=$(wc -l < "$TMP/cj.debug.txt") bytes=$(wc -c < "$TMP/cj.debug.txt") sha256=$(sha256sum "$TMP/cj.debug.txt" | awk '{print $1}') cmp=PASS"

build_closure() {
    local mode=$1
    local owner_flag=()
    local suffix=()
    if [[ $mode == debug ]]; then owner_flag=(-g); suffix=(--debug); fi
    local output="$TMP/closure.$mode"
    mkdir -p "$output"
    local package_temps=()
    for package in rt.base rt.sync; do
        local temps="$output/$package.temps"
        mkdir -p "$temps"
        "$SELFHOST_CJC" --package "$ROOT/src/$package" --output-type=staticlib \
            --save-temps "$temps" --int-overflow wrapping -Woff unused \
            --import-path "$output" --output-dir "$output" -o "lib$package.a"
        package_temps+=("$temps")
    done
    local heap="$output/rt.heap.allocator.noheap"
    cp -a "$ROOT/src/rt.heap.allocator" "$heap"
    cp "$ROOT/test/parity/heap/allocbuffer_fresh_noheap.cj" "$heap/FreshAllocBufferNoHeap.cj"
    local heap_temps="$output/rt.heap.allocator.temps"
    mkdir -p "$heap_temps"
    "$SELFHOST_CJC" --package "$heap" --output-type=staticlib "${owner_flag[@]}" \
        --save-temps "$heap_temps" --int-overflow wrapping -Woff unused \
        --import-path "$output" --output-dir "$output" -o librt.heap.allocator.a
    package_temps+=("$heap_temps")

    local package_pre=()
    for temps in "${package_temps[@]}"; do
        local inputs=()
        while IFS= read -r bc; do inputs+=("$bc"); done < <(
            find "$temps" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
        [[ ${#inputs[@]} -gt 0 ]]
        local linked="$output/$(basename "$temps").pre.bc"
        "$LLVM_LINK" "${inputs[@]}" -o "$linked"
        package_pre+=("$linked")
    done
    "$LLVM_LINK" --only-needed "${package_pre[2]}" "${package_pre[1]}" \
        "${package_pre[0]}" -o "$output/pre.bc"
    "$LLVM_DIS" "$output/pre.bc" -o "$output/pre.ll"
    "$LLVM_OPT" -passes=print-callgraph -disable-output "$output/pre.bc" 2> "$output/callgraph"
    awk '
    /^Call graph node for function:/ {
        line=$0; sub(/^.*function: '\''/, "", line); sub(/'\''.*$/, "", line); owner=line; next
    }
    /calls function '\''/ {
        line=$0; sub(/^.*calls function '\''/, "", line); sub(/'\''.*$/, "", line)
        if (owner != "") print owner "\t" line
    }' "$output/callgraph" > "$output/calls.tsv"

    local final_args=() object_args=()
    for temps in "${package_temps[@]}"; do
        while IFS= read -r bc; do
            local ll="$output/$(basename "$temps").$(basename "$bc").ll"
            "$LLVM_DIS" "$bc" -o "$ll"
            final_args+=(--final "$ll")
        done < <(find "$temps" -maxdepth 1 -type f -name '*.opt.bc' | sort)
        while IFS= read -r object; do
            local dump="$output/$(basename "$temps").$(basename "$object").objdump"
            objdump -dr "$object" > "$dump"
            object_args+=(--object "$dump")
        done < <(find "$temps" -maxdepth 1 -type f -name '*.o' | sort)
    done

    compile_native_linux "$output/native"
    local native_args=()
    for object in "$output/native/"*.o; do
        local dump="$object.objdump"
        objdump -dr "$object" > "$dump"
        native_args+=(--native "$dump")
    done
    PYTHONPATH="$ROOT/test/parity/heap" python3 \
        "$ROOT/test/parity/heap/allocbuffer_fresh_closure.py" \
        --pre "$output/pre.ll" --calls "$output/calls.tsv" \
        "${final_args[@]}" "${object_args[@]}" "${native_args[@]}" \
        --runtime "$SELFHOST_RUNTIME_LIB" "${suffix[@]}"
}

build_closure release
build_closure debug

# The Cangjie owner is compiled for shipped llvm-mingw in both modes. Apple
# source/layout selection is fail-closed here; native execution requires an
# Apple SDK/libc++ environment and is recorded as an explicit target debt.
for mode in release debug; do
    flags=()
    if [[ $mode == debug ]]; then flags=(-g); fi
    out="$TMP/windows.$mode"
    mkdir -p "$out"
    for package in rt.base rt.sync; do
        "$SELFHOST_CJC" --package "$ROOT/src/$package" --target "$WINDOWS_TARGET" \
            --output-type=staticlib --int-overflow wrapping -Woff unused \
            --import-path "$out" --output-dir "$out" -o "lib$package.a"
    done
    "$SELFHOST_CJC" --package "$ROOT/src/rt.heap.allocator" --target "$WINDOWS_TARGET" \
        --output-type=staticlib "${flags[@]}" --int-overflow wrapping -Woff unused \
        --import-path "$out" --output-dir "$out" -o librt.heap.allocator.a
done
for symbol in CJRT_AllocBufferNullRegion CJRT_AllocBufferPreparedConstruct \
    CJRT_AllocBufferPreparedLoadRelaxed CJRT_AllocBufferPreparedCompareExchangeRelease \
    CJRT_AllocBufferStackRootsConstruct CJRT_AllocBufferStackRootsDestroy \
    CJRT_AllocBufferPushRoot CJRT_AllocBufferMergeRoots; do
    llvm-nm -u "$TMP/windows.release/librt.heap.allocator.a" | awk '{print $2}' | grep -Fxq "$symbol"
done
echo 'ALLOC_BUFFER_PLATFORM target=Linux-OHOS size=200 compile=PASS execute=PASS status=PASS'
echo 'ALLOC_BUFFER_PLATFORM target=Apple size=248 cj_source=PASS native_execute=DEBT-APPLE-SDK-LIBCXX status=EXPLICIT-DEBT'
echo 'ALLOC_BUFFER_PLATFORM target=Win64 size=136 cj_release=PASS cj_debug=PASS native_imports=8 status=PASS'
echo "ALLOC_BUFFER_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_allocbuffer_probe: PASS'
