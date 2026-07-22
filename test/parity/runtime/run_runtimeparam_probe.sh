#!/usr/bin/env bash
# Fail-closed RuntimeParam C ABI parity and noheap whole-closure proof.
set -euo pipefail

ROOT=$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd -P)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
CJC_BIN_DIR=$(cd "${SELFHOST_CJC%/*}" && pwd -P)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
export cjHeapSize=24GB

fail() { echo "run_runtimeparam_probe: FAIL $*" >&2; exit 1; }

for tool in cmp g++ git mktemp nm objdump python3 sha256sum stat; do
    command -v "$tool" >/dev/null || fail "missing tool $tool"
done
[[ -x "$SELFHOST_CJC" && -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" &&
   -x "$LLVM_BIN/opt" ]] || fail 'pinned compiler/LLVM tools absent'
for input in \
    "$ROOT/src/rt.runtime/RuntimeParam.cj" \
    "$ROOT/test/parity/runtime/runtimeparam_ref.cpp" \
    "$ROOT/test/parity/runtime/runtimeparam_probe.cj" \
    "$ROOT/test/parity/runtime/runtimeparam_noheap.cj" \
    "$ROOT/test/parity/runtime/runtimeparam_closure.py" \
    "$CPP_RUNTIME_ROOT/src/Cangjie.h"; do
    [[ -r "$input" ]] || fail "missing input $input"
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_runtimeparam_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/package" "$TMP/temps" "$TMP/noheap" "$TMP/noheap.temps"

"$SELFHOST_CJC" --package "$ROOT/src/rt.runtime" --output-type=staticlib \
    --int-overflow wrapping --save-temps "$TMP/temps" --output-dir "$TMP" -o librt.runtime.a
g++ -std=c++14 -O2 -Wall -Wextra -Werror -I "$CPP_RUNTIME_ROOT/src" \
    "$ROOT/test/parity/runtime/runtimeparam_ref.cpp" -o "$TMP/ref"
g++ -std=c++14 -O2 -Wall -Wextra -Werror -DRUNTIMEPARAM_LAYOUT_ONLY \
    -I "$CPP_RUNTIME_ROOT/src" "$ROOT/test/parity/runtime/runtimeparam_ref.cpp" -o "$TMP/layout"
"$SELFHOST_CJC" "$ROOT/test/parity/runtime/runtimeparam_probe.cj" --import-path "$TMP" \
    --int-overflow wrapping "$TMP/librt.runtime.a" -o "$TMP/probe"
"$TMP/ref" > "$TMP/ref.bin"
"$TMP/probe" > "$TMP/probe.bin"
cmp "$TMP/ref.bin" "$TMP/probe.bin"
"$TMP/layout"
echo "RUNTIMEPARAM_TRANSCRIPT bytes=$(stat -c %s "$TMP/probe.bin") sha256=$(sha256sum "$TMP/probe.bin" | awk '{print $1}') cmp=PASS"

cp "$ROOT/src/rt.runtime/RuntimeParam.cj" "$TMP/noheap/RuntimeParam.cj"
cp "$ROOT/test/parity/runtime/runtimeparam_noheap.cj" "$TMP/noheap/RuntimeParamNoHeap.cj"
"$SELFHOST_CJC" --package "$TMP/noheap" --output-type=staticlib --int-overflow wrapping \
    --save-temps "$TMP/noheap.temps" --output-dir "$TMP" -o librt.runtime.noheap.a

mapfile -t pre_bc < <(find "$TMP/noheap.temps" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
mapfile -t final_bc < <(find "$TMP/noheap.temps" -maxdepth 1 -type f -name '*.opt.bc' | sort)
mapfile -t objects < <(find "$TMP/noheap.temps" -maxdepth 1 -type f -name '*.o' | sort)
[[ ${#pre_bc[@]} -gt 0 && ${#final_bc[@]} -gt 0 && ${#objects[@]} -gt 0 ]] || fail 'closure artifacts absent'
"$LLVM_BIN/llvm-link" "${pre_bc[@]}" -o "$TMP/pre.bc"
"$LLVM_BIN/llvm-dis" "$TMP/pre.bc" -o "$TMP/pre.ll"
"$LLVM_BIN/opt" -passes=print-callgraph -disable-output "$TMP/pre.bc" 2> "$TMP/callgraph"
awk '
/^Call graph node for function:/ { line=$0; sub(/^.*function: '\''/, "", line); sub(/'\''.*$/, "", line); owner=line; next }
/calls function '\''/ { line=$0; sub(/^.*calls function '\''/, "", line); sub(/'\''.*$/, "", line); if (owner != "") print owner "\t" line }
' "$TMP/callgraph" > "$TMP/calls.tsv"

final_args=()
for bc in "${final_bc[@]}"; do
    ll="$TMP/$(basename "$bc").ll"
    "$LLVM_BIN/llvm-dis" "$bc" -o "$ll"
    final_args+=(--final "$ll")
done
object_args=()
for object in "${objects[@]}"; do
    dump="$TMP/$(basename "$object").objdump"
    objdump -dr "$object" > "$dump"
    object_args+=(--object "$dump")
done
PYTHONPATH="$ROOT/test/parity/heap" python3 "$ROOT/test/parity/runtime/runtimeparam_closure.py" \
    --pre "$TMP/pre.ll" --calls "$TMP/calls.tsv" "${final_args[@]}" "${object_args[@]}"

mkdir -p "$TMP/windows.release" "$TMP/windows.debug"
"$SELFHOST_CJC" --package "$ROOT/src/rt.runtime" --target x86_64-w64-mingw32 \
    --output-type=staticlib --int-overflow wrapping --output-dir "$TMP/windows.release" -o librt.runtime.a
"$SELFHOST_CJC" --package "$ROOT/src/rt.runtime" --target x86_64-w64-mingw32 -g \
    --output-type=staticlib --int-overflow wrapping --output-dir "$TMP/windows.debug" -o librt.runtime.a
echo 'RUNTIMEPARAM_PLATFORM target=Linux-OHOS compile=PASS execute=PASS status=PASS'
echo 'RUNTIMEPARAM_PLATFORM target=Apple abi=CANGJIE_C_RECORD source_branches=0 native_execute=DEBT-APPLE-SDK status=EXPLICIT-DEBT'
echo 'RUNTIMEPARAM_PLATFORM target=Win64 release=PASS debug=PASS status=PASS'
echo 'run_runtimeparam_probe: PASS'
