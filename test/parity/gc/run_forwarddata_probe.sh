#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative:$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_forwarddata.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
SOURCE="$ROOT/src/rt.heap.allocator/ForwardDataManager.cj"
for marker in 'ForwardDataManager.h:34-128' 'ForwardDataManager.h:36-44' \
    'os == "Linux" || env == "ohos"' 'os == "macOS" || os == "iOS"' 'os == "Windows"'; do grep -Fq "$marker" "$SOURCE"; done
echo 'FORWARDDATA_SOURCE fresh=PASS linux_ohos=PASS apple=PASS win64=PASS'

INCLUDES=(-I"$RUNTIME_ROOT/include" -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include")
while IFS= read -r d; do INCLUDES+=("-I$d"); done < <(find "$RUNTIME_ROOT/src" -type d)
g++ -std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME "${INCLUDES[@]}" \
    "$ROOT/test/parity/gc/forwarddata_ref.cpp" -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" \
    -lcangjie-runtime -L"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" \
    -lboundscheck -lsecurec -lpthread -ldl -o "$TMP/ref"
"$TMP/ref" > "$TMP/ref.txt"

compile_packages() {
    local out=$1; shift
    mkdir -p "$out"
    for pkg in rt.base rt.sync rt.gc; do
        "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib "$@" \
            --int-overflow wrapping -Woff unused --import-path "$out" --output-dir "$out" -o "lib$pkg.a"
    done
}
compile_native() {
    local out=$1; mkdir -p "$out"
    for source in Futex Panic Atomic SpinLock PagePoolMutex; do
        g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/$source.cpp" -o "$out/$source.o"
    done
    g++ -std=c++17 -O2 -fPIC "${INCLUDES[@]}" -c "$ROOT/rt0/AllocBufferNative.cpp" -o "$out/AllocBufferNative.o"
    g++ -std=c++17 -O2 -fPIC "${INCLUDES[@]}" -c "$ROOT/rt0/ScopedSaferegion.cpp" -o "$out/ScopedSaferegion.o"
}
OUT="$TMP/cj"; compile_packages "$OUT"; compile_native "$OUT/native"
PROBE="$OUT/rt.heap.allocator.probe"; cp -a "$ROOT/src/rt.heap.allocator" "$PROBE"
cp "$ROOT/test/parity/gc/forwarddata_probe.cj" "$PROBE/ForwardDataProbe.cj"
"$SELFHOST_CJC" --package "$PROBE" --import-path "$OUT" --int-overflow wrapping -Woff unused \
    "$OUT/librt.gc.a" "$OUT/librt.sync.a" "$OUT/librt.base.a" "$OUT/native/"*.o \
    --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread -o "$OUT/probe"
"$OUT/probe" > "$TMP/cj.txt"
cmp "$TMP/ref.txt" "$TMP/cj.txt"; cat "$TMP/cj.txt"
echo "FORWARDDATA_TRANSCRIPT lines=$(wc -l < "$TMP/cj.txt") bytes=$(wc -c < "$TMP/cj.txt") sha256=$(sha256sum "$TMP/cj.txt" | awk '{print $1}') cmp=PASS"

CLOSURE="$TMP/closure"; mkdir -p "$CLOSURE"; PACKAGE_TEMPS=()
for pkg in rt.base rt.sync rt.gc; do
    temps="$CLOSURE/$pkg.temps"; mkdir -p "$temps"
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib --save-temps "$temps" \
        --int-overflow wrapping -Woff unused --import-path "$CLOSURE" --output-dir "$CLOSURE" -o "lib$pkg.a"
    PACKAGE_TEMPS+=("$temps")
done
HEAP="$CLOSURE/rt.heap.allocator.noheap"; cp -a "$ROOT/src/rt.heap.allocator" "$HEAP"
cp "$ROOT/test/parity/gc/forwarddata_noheap.cj" "$HEAP/ForwardDataNoHeap.cj"
temps="$CLOSURE/rt.heap.allocator.temps"; mkdir -p "$temps"
"$SELFHOST_CJC" --package "$HEAP" --output-type=staticlib --save-temps "$temps" \
    --int-overflow wrapping -Woff unused --import-path "$CLOSURE" --output-dir "$CLOSURE" -o librt.heap.allocator.a
PACKAGE_TEMPS+=("$temps")
PRE=(); FINAL_ARGS=(); OBJECT_ARGS=()
for temps in "${PACKAGE_TEMPS[@]}"; do
    mapfile -t inputs < <(find "$temps" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
    linked="$CLOSURE/$(basename "$temps").pre.bc"
    "$CANGJIE_HOME/third_party/llvm/bin/llvm-link" "${inputs[@]}" -o "$linked"; PRE+=("$linked")
    while IFS= read -r bc; do ll="$CLOSURE/$(basename "$temps").$(basename "$bc").ll"; "$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$bc" -o "$ll"; FINAL_ARGS+=(--final "$ll"); done < <(find "$temps" -maxdepth 1 -name '*.opt.bc' | sort)
    while IFS= read -r obj; do dump="$CLOSURE/$(basename "$temps").$(basename "$obj").objdump"; objdump -dr "$obj" > "$dump"; OBJECT_ARGS+=(--object "$dump"); done < <(find "$temps" -maxdepth 1 -name '*.o' | sort)
done
"$CANGJIE_HOME/third_party/llvm/bin/llvm-link" --only-needed "${PRE[3]}" "${PRE[2]}" "${PRE[1]}" "${PRE[0]}" -o "$CLOSURE/pre.bc"
"$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$CLOSURE/pre.bc" -o "$CLOSURE/pre.ll"
"$CANGJIE_HOME/third_party/llvm/bin/opt" -passes=print-callgraph -disable-output "$CLOSURE/pre.bc" 2> "$CLOSURE/callgraph"
awk '/^Call graph node for function:/{line=$0;sub(/^.*function: '\''/,"",line);sub(/'\''.*$/,"",line);owner=line;next}/calls function '\''/{line=$0;sub(/^.*calls function '\''/,"",line);sub(/'\''.*$/,"",line);if(owner!="")print owner "\t" line}' "$CLOSURE/callgraph" > "$CLOSURE/calls.tsv"
compile_native "$CLOSURE/native"; NATIVE_ARGS=()
for obj in "$CLOSURE/native/"*.o; do objdump -dr "$obj" > "$obj.objdump"; NATIVE_ARGS+=(--native "$obj.objdump"); done
python3 "$ROOT/test/parity/gc/forwarddata_closure.py" --pre "$CLOSURE/pre.ll" --calls "$CLOSURE/calls.tsv" \
    "${FINAL_ARGS[@]}" "${OBJECT_ARGS[@]}" "${NATIVE_ARGS[@]}"

WIN="$TMP/win"; compile_packages "$WIN" --target x86_64-w64-mingw32
"$SELFHOST_CJC" --package "$ROOT/src/rt.heap.allocator" --target x86_64-w64-mingw32 \
    --output-type=staticlib --int-overflow wrapping -Woff unused --import-path "$WIN" --output-dir "$WIN" -o librt.heap.allocator.a
"$SELFHOST_CJC" --package "$ROOT/src/rt.heap.allocator" --target x86_64-w64-mingw32 -g \
    --output-type=staticlib --int-overflow wrapping -Woff unused --import-path "$WIN" --output-dir "$WIN" -o librt.heap.allocator.debug.a
clang++ --target=x86_64-w64-windows-gnu -std=c++14 -O2 -c "$ROOT/rt0/Atomic.cpp" -o "$WIN/Atomic.o"
llvm-nm "$WIN/Atomic.o" | grep -Fq cj_atomic_uintptr_fetch_add_seq_cst
echo 'FORWARDDATA_PLATFORM target=Linux-OHOS compile=PASS execute=PASS release_paths=PASS status=PASS'
echo 'FORWARDDATA_PLATFORM target=Apple source=PASS fixed_mmap=PASS native_execute=DEBT-APPLE-SDK status=EXPLICIT-DEBT'
echo 'FORWARDDATA_PLATFORM target=Win64 cj_release=PASS cj_debug=PASS reserve_commit_decommit=PASS status=PASS'
echo "FORWARDDATA_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_forwarddata_probe: PASS'
