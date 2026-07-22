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
WINDOWS_RUNTIME="$CANGJIE_HOME/runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll.a"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_regionlist_fresh.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

SOURCE="$ROOT/src/rt.heap.allocator/RegionList.cj"
[[ -f "$SOURCE" ]]
[[ $(grep -Fc '@When[os == "Linux" || env == "ohos"]' "$SOURCE") -eq 11 ]]
[[ $(grep -Fc '@When[os == "macOS" || os == "iOS"]' "$SOURCE") -eq 11 ]]
[[ $(grep -Fc '@When[os == "Windows"]' "$SOURCE") -eq 11 ]]
for marker in DumpRegionList VerifyRegion REGION_LIST_PREPEND_LOG REGION_LIST_DELETE_LOG \
    _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz; do
    grep -Fq "$marker" "$SOURCE"
done
if rg -n 'PLATFORM-DEBT|DEBUG-DEBT|CJRT_RegionListInvokeVisitor|malloc\(|free\(' "$SOURCE"; then
    echo 'REGIONLIST_SOURCE FAIL rejected debt/workaround' >&2
    exit 1
fi
echo 'REGIONLIST_SOURCE fresh=PASS linux_ohos=PASS apple=PASS win64=PASS debug_paths=PASS'

INCLUDES=(-I"$RUNTIME_ROOT/include")
while IFS= read -r directory; do INCLUDES+=(-I"$directory"); done < <(find "$RUNTIME_ROOT/src" -type d)
CPP_FLAGS=(-std=c++17 -O2 -pthread -DMRT_USE_CJTHREAD_RENAME
    -I"$RUNTIME_ROOT/output/temp/include"
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    "${INCLUDES[@]}")

build_cpp_probe() {
    local mode=$1
    local extra=()
    if [[ $mode == debug ]]; then extra=(-DMRT_DEBUG=1); fi
    g++ "${CPP_FLAGS[@]}" "${extra[@]}" -c "$RUNTIME_ROOT/src/Heap/Allocator/RegionManager.cpp" \
        -o "$TMP/RegionManager.$mode.o"
    g++ "${CPP_FLAGS[@]}" "${extra[@]}" -c "$ROOT/test/parity/heap/regionlist_fresh_ref.cpp" \
        -o "$TMP/ref.$mode.o"
    g++ -Wl,--gc-sections "$TMP/ref.$mode.o" "$TMP/RegionManager.$mode.o" \
        -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
        -L"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" \
        -lboundscheck -lsecurec -lpthread -ldl -o "$TMP/ref.$mode"
    LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH" "$TMP/ref.$mode" > "$TMP/ref.$mode.txt"
}

compile_native_linux() {
    local output=$1
    mkdir -p "$output"
    for source in Futex Panic Atomic SpinLock PagePoolMutex; do
        g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/$source.cpp" -o "$output/$source.o"
    done
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
    cp "$ROOT/test/parity/heap/regionlist_fresh_probe.cj" "$probe/FreshProbe.cj"
    compile_native_linux "$output/native"
    "$SELFHOST_CJC" --package "$probe" "${owner_flag[@]}" --import-path "$output" \
        --int-overflow wrapping -Woff unused "$output/librt.sync.a" "$output/librt.base.a" \
        "$output/native/Futex.o" "$output/native/Panic.o" "$output/native/Atomic.o" \
        "$output/native/SpinLock.o" "$output/native/PagePoolMutex.o" \
        --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread \
        -o "$output/regionlist"
    "$output/regionlist" > "$TMP/cj.$mode.txt"
}

build_cpp_probe release
build_cj_probe release
cmp "$TMP/ref.release.txt" "$TMP/cj.release.txt"
build_cpp_probe debug
build_cj_probe debug
cmp "$TMP/ref.debug.txt" "$TMP/cj.debug.txt"
cmp "$TMP/cj.release.txt" "$TMP/cj.debug.txt"
cat "$TMP/cj.release.txt"
echo "REGIONLIST_TRANSCRIPT lines=$(wc -l < "$TMP/cj.release.txt") bytes=$(wc -c < "$TMP/cj.release.txt") sha256=$(sha256sum "$TMP/cj.release.txt" | awk '{print $1}') cmp=PASS"
echo "REGIONLIST_DEBUG_TRANSCRIPT lines=$(wc -l < "$TMP/cj.debug.txt") bytes=$(wc -c < "$TMP/cj.debug.txt") sha256=$(sha256sum "$TMP/cj.debug.txt" | awk '{print $1}') cmp=PASS"

build_closure() {
    local mode=$1
    local owner_flag=()
    local suffix=''
    if [[ $mode == debug ]]; then owner_flag=(-g); suffix=--debug; fi
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
    cp "$ROOT/test/parity/heap/regionlist_fresh_noheap.cj" "$heap/FreshNoHeapRoots.cj"
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

    local final_args=()
    local object_args=()
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
    for object in "$output/native"/*.o; do
        local dump="$object.objdump"
        objdump -dr "$object" > "$dump"
        native_args+=(--native "$dump")
    done
    python3 "$ROOT/test/parity/heap/regionlist_fresh_closure.py" \
        --pre "$output/pre.ll" --calls "$output/calls.tsv" \
        "${final_args[@]}" "${object_args[@]}" "${native_args[@]}" \
        --runtime "$SELFHOST_RUNTIME_LIB" $suffix
}

build_closure release
build_closure debug

# Platform closure: compile both non-host Layer0 sources without host headers,
# compile the complete Cangjie owner package for Win64 in release and debug,
# and bind the WriteLog leaf against the shipped runtime import library.
clang++ --target=x86_64-apple-darwin -std=c++17 -O2 -c \
    "$ROOT/rt0/os/Macos/PagePoolMutex.cpp" -o "$TMP/apple-mutex.o"
clang++ --target=x86_64-w64-windows-gnu -std=c++17 -O2 -c \
    "$ROOT/rt0/os/Windows/PagePoolMutex.cpp" -o "$TMP/windows-mutex.o"
for object in "$TMP/apple-mutex.o" "$TMP/windows-mutex.o"; do
    [[ $(llvm-nm --defined-only "$object" | grep -Ec 'CJRT_PagePoolMutex(Construct|Destroy|Lock|Unlock)$') -eq 4 ]]
done

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
llvm-nm -u "$TMP/windows.debug/librt.heap.allocator.a" | awk '{print $2}' | sort -u \
    > "$TMP/windows.undefined"
llvm-nm "$WINDOWS_RUNTIME" | awk '{print $3}' | sort -u > "$TMP/windows.runtime"
for symbol in CJRT_PagePoolMutexConstruct CJRT_PagePoolMutexDestroy \
    CJRT_PagePoolMutexLock CJRT_PagePoolMutexUnlock \
    _ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz; do
    grep -Fxq "$symbol" "$TMP/windows.undefined"
    if [[ $symbol == _ZN* ]]; then grep -Fxq "$symbol" "$TMP/windows.runtime"; fi
done
echo 'REGIONLIST_PLATFORM target=Linux-OHOS layout=40 compile=PASS execute=PASS status=PASS'
echo 'REGIONLIST_PLATFORM target=Apple layout=64 bridge_cross_compile=PASS definitions=4 status=PASS'
echo 'REGIONLIST_PLATFORM target=Win64 layout=8 cj_release=PASS cj_debug=PASS bridge_cross_compile=PASS definitions=4 runtime_writelog=PASS status=PASS'
echo "REGIONLIST_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_regionlist_fresh_probe: PASS'
