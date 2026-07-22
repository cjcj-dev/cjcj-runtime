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
WINDOWS_TARGET=x86_64-w64-mingw32
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_markworkstack.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

SOURCE="$ROOT/src/rt.gc/MarkWorkStack.cj"
CPP_SOURCE="$RUNTIME_ROOT/src/Common/MarkWorkStack.h"
[[ -f "$SOURCE" && -f "$CPP_SOURCE" ]]
[[ $(grep -Fc '@When[os == "Linux" || env == "ohos"]' "$SOURCE") -eq 2 ]]
[[ $(grep -Fc '@When[os == "macOS" || os == "iOS"]' "$SOURCE") -eq 2 ]]
[[ $(grep -Fc '@When[os == "Windows"]' "$SOURCE") -eq 2 ]]
if rg -n 'PLATFORM-DEBT|DEBUG-DEBT|malloc\(|free\(' "$SOURCE"; then
    echo 'MARKWORKSTACK_SOURCE FAIL rejected debt/allocator substitution' >&2
    exit 1
fi
cpp_platform_branches=$(grep -Ec '^#(if|elif).*(__APPLE__|_WIN64|__linux__|hongmeng)' "$CPP_SOURCE" || true)
[[ $cpp_platform_branches -eq 0 ]]
echo 'MARKWORKSTACK_SOURCE fresh=PASS linux_ohos=PASS apple=PASS win64=PASS cpp_platform_branches=0'

CPP_FLAGS=(-std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME
    -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/output/temp/include"
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include")
g++ "${CPP_FLAGS[@]}" "$ROOT/test/parity/gc/markworkstack_ref.cpp" \
    "$ROOT/test/parity/gc/markworkstack_alloc.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -o "$TMP/ref"
"$TMP/ref" > "$TMP/ref.txt"

g++ -std=c++17 -O2 -fPIC -c "$ROOT/test/parity/gc/markworkstack_alloc.cpp" -o "$TMP/alloc.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/Atomic.cpp" -o "$TMP/Atomic.o"
PROBE="$TMP/rt.gc.probe"
cp -a "$ROOT/src/rt.gc" "$PROBE"
cp "$ROOT/test/parity/gc/markworkstack_probe.cj" "$PROBE/Probe.cj"
"$SELFHOST_CJC" --package "$PROBE" --int-overflow wrapping -Woff unused \
    "$TMP/alloc.o" "$TMP/Atomic.o" --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/probe"
"$TMP/probe" > "$TMP/probe.txt"
cmp "$TMP/ref.txt" "$TMP/probe.txt"
cat "$TMP/probe.txt"
echo "MARKWORKSTACK_TRANSCRIPT lines=$(wc -l < "$TMP/probe.txt") bytes=$(wc -c < "$TMP/probe.txt") sha256=$(sha256sum "$TMP/probe.txt" | awk '{print $1}') cmp=PASS"

# MarkWorkStack.h:88-101 has a real non-empty clear failure: tail is reset only
# after a loop whose empty predicate also requires tail==nullptr. Preserve and
# compare that failure outside the successful transcript.
g++ "${CPP_FLAGS[@]}" "$ROOT/test/parity/gc/markworkstack_nonempty_clear_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -o "$TMP/clear.ref"
CLEAR_PROBE="$TMP/rt.gc.clear"
cp -a "$ROOT/src/rt.gc" "$CLEAR_PROBE"
cp "$ROOT/test/parity/gc/markworkstack_nonempty_clear.cj" "$CLEAR_PROBE/Clear.cj"
"$SELFHOST_CJC" --package "$CLEAR_PROBE" --int-overflow wrapping -Woff unused \
    "$TMP/Atomic.o" --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/clear.cj"
ulimit -c 0 || true
set +e
"$TMP/clear.ref" >/dev/null 2>&1
cpp_clear_rc=$?
"$TMP/clear.cj" >/dev/null 2>&1
cj_clear_rc=$?
set -e
[[ $cpp_clear_rc -ne 0 && $cj_clear_rc -ne 0 ]]
echo "MARKWORKSTACK_NONEMPTY_CLEAR cpp_rc=$cpp_clear_rc cj_rc=$cj_clear_rc outcome=FAILURE_PARITY status=PASS"

CLOSURE="$TMP/rt.gc.noheap"
cp -a "$ROOT/src/rt.gc" "$CLOSURE"
cp "$ROOT/test/parity/gc/markworkstack_noheap.cj" "$CLOSURE/NoHeap.cj"
TEMPS="$TMP/temps"
mkdir -p "$TEMPS"
"$SELFHOST_CJC" --package "$CLOSURE" --output-type=staticlib --save-temps "$TEMPS" \
    --int-overflow wrapping -Woff unused -o "$TMP/librt.gc.a"
mapfile -t PRE_BC < <(find "$TEMPS" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
[[ ${#PRE_BC[@]} -gt 0 ]]
"$LLVM_LINK" "${PRE_BC[@]}" -o "$TMP/pre.bc"
"$LLVM_DIS" "$TMP/pre.bc" -o "$TMP/pre.ll"
"$LLVM_OPT" -passes=print-callgraph -disable-output "$TMP/pre.bc" 2> "$TMP/callgraph"
awk '
/^Call graph node for function:/ {
    line=$0; sub(/^.*function: '\''/, "", line); sub(/'\''.*$/, "", line); owner=line; next
}
/calls function '\''/ {
    line=$0; sub(/^.*calls function '\''/, "", line); sub(/'\''.*$/, "", line)
    if (owner != "") print owner "\t" line
}' "$TMP/callgraph" > "$TMP/calls.tsv"
final_args=()
object_args=()
while IFS= read -r bc; do
    ll="$TMP/$(basename "$bc").ll"
    "$LLVM_DIS" "$bc" -o "$ll"
    final_args+=(--final "$ll")
done < <(find "$TEMPS" -maxdepth 1 -type f -name '*.opt.bc' | sort)
while IFS= read -r object; do
    dump="$TMP/$(basename "$object").objdump"
    objdump -dr "$object" > "$dump"
    object_args+=(--object "$dump")
done < <(find "$TEMPS" -maxdepth 1 -type f -name '*.o' | sort)
python3 "$ROOT/test/parity/gc/markworkstack_closure.py" \
    --pre "$TMP/pre.ll" --calls "$TMP/calls.tsv" "${final_args[@]}" "${object_args[@]}"

for mode in release debug; do
    flags=()
    [[ $mode == debug ]] && flags=(-g)
    out="$TMP/windows.$mode"
    mkdir -p "$out"
    "$SELFHOST_CJC" --package "$ROOT/src/rt.gc" --target "$WINDOWS_TARGET" \
        --output-type=staticlib "${flags[@]}" --int-overflow wrapping -Woff unused \
        --output-dir "$out" -o librt.gc.a
done
for symbol in _Znwm _ZdlPv abort; do
    llvm-nm -u "$TMP/windows.debug/librt.gc.a" | awk '{print $2}' | grep -Fxq "$symbol"
done
echo 'MARKWORKSTACK_PLATFORM target=Linux-OHOS compile=PASS execute=PASS status=PASS'
echo 'MARKWORKSTACK_PLATFORM target=Apple source_branches=2 cpp_branches=0 native_execute=DEBT-APPLE-SDK status=EXPLICIT-DEBT'
echo 'MARKWORKSTACK_PLATFORM target=Win64 cj_release=PASS cj_debug=PASS operator_new_delete=PASS status=PASS'
echo "MARKWORKSTACK_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_markworkstack_probe: PASS'
