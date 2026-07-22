#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative"
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
CJC_BIN_DIR=$(cd "${SELFHOST_CJC%/*}" && pwd -P)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB
fail() { echo "run_eh_primitives_probe: FAIL $*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail "executable target must be Linux x86_64"
for tool in g++ cmp objdump python3; do command -v "$tool" >/dev/null || fail "missing $tool"; done
[[ -x "$SELFHOST_CJC" && -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] || fail "missing pinned compiler tools"

CPP_H="$RUNTIME_ROOT/src/Exception/EhTable.h"
CPP_CC="$RUNTIME_ROOT/src/Exception/EhTable.cpp"
[[ $(sed -n '14,72p' "$CPP_H" | grep -Ec '^#if|^#ifdef|^#elif') -eq 0 ]] || fail "unexpected primitive header platform branch"
[[ $(sed -n '52,65p' "$CPP_CC" | grep -Ec '^#if|^#ifdef|^#elif') -eq 0 ]] || fail "unexpected ULEB platform branch"
echo "EH_PLATFORM linux_x86_64=EXECUTED apple=SHARED_LOGIC windows=SHARED_LOGIC arm=SHARED_LOGIC branches=0 status=PASS"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_eh_primitives.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/exception" "$TMP/root"
(
    cd "$TMP"
    "$SELFHOST_CJC" --package "$ROOT/src/rt.exception" --output-type=staticlib -O2 \
        --int-overflow wrapping --save-temps "$TMP/exception" --output-dir "$TMP" -o librt.exception.a
)
"$SELFHOST_CJC" "$ROOT/test/parity/exception/eh_primitives_probe.cj" --import-path "$TMP" \
    --int-overflow wrapping "$TMP/librt.exception.a" -o "$TMP/eh_cj"
cpp_includes=(-I "$RUNTIME_ROOT/src" \
    -I "$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    -I "$RUNTIME_ROOT/src/CJThread/src/runtime/schedule/include/inner/gas/x86/x86_64")
while IFS= read -r include_dir; do cpp_includes+=(-I "$include_dir"); done \
    < <(find "$RUNTIME_ROOT/src/CJThread" -type d -name include | sort)
g++ -std=c++14 -O2 "${cpp_includes[@]}" \
    "$ROOT/test/parity/exception/eh_primitives_ref.cpp" -L "$CPP_RUNTIME_LIB" \
    -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -o "$TMP/eh_cpp"
"$TMP/eh_cj" > "$TMP/cj.transcript"
LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib" \
    "$TMP/eh_cpp" > "$TMP/cpp.transcript"
cmp "$TMP/cpp.transcript" "$TMP/cj.transcript" || {
    diff -u "$TMP/cpp.transcript" "$TMP/cj.transcript" >&2 || true
    fail "byte transcript mismatch"
}
cat "$TMP/cj.transcript"
echo "EH_PARITY records=$(wc -l < "$TMP/cj.transcript") bytes=$(stat -c %s "$TMP/cj.transcript") cmp=identical status=PASS"

(
    cd "$TMP"
    "$SELFHOST_CJC" --package "$ROOT/test/parity/exception/eh.noheap" \
        --output-type=staticlib -O2 --int-overflow wrapping --import-path "$TMP" \
        --save-temps "$TMP/root" --output-dir "$TMP" -o libeh.noheap.a
)
root_pre=$(find "$TMP/root" -maxdepth 1 -name '*.bc' ! -name '*.opt.bc' -print -quit)
root_final=$(find "$TMP/root" -maxdepth 1 -name '*.opt.bc' -print -quit)
root_object=$(find "$TMP/root" -maxdepth 1 -name '*.o' -print -quit)
mapfile -t exception_finals < <(find "$TMP/exception" -maxdepth 1 -name '*.opt.bc' -print | sort)
mapfile -t exception_objects < <(find "$TMP/exception" -maxdepth 1 -name '*.o' -print | sort)
for artifact in "$root_pre" "$root_final" "$root_object" "${exception_finals[@]}" "${exception_objects[@]}"; do
    [[ -s "$artifact" ]] || fail "missing closure artifact"
done
[[ ${#exception_finals[@]} -eq ${#exception_objects[@]} && ${#exception_finals[@]} -ge 2 ]] ||
    fail "incomplete exception package closure artifacts"
"$LLVM_BIN/llvm-link" "$root_final" "${exception_finals[@]}" -o "$TMP/linked.final.bc"
"$LLVM_BIN/llvm-dis" "$root_pre" -o "$TMP/root.pre.ll"
"$LLVM_BIN/llvm-dis" "$TMP/linked.final.bc" -o "$TMP/linked.final.ll"
closure=(python3 "$ROOT/test/parity/exception/eh_primitives_closure.py" \
    --pre "$TMP/root.pre.ll" --final "$TMP/linked.final.ll" \
    --object "$root_object")
for object in "${exception_objects[@]}"; do closure+=(--object "$object"); done
"${closure[@]}"
set +e
"${closure[@]}" --inject-forbidden > "$TMP/negative.log" 2>&1
negative_rc=$?
set -e
[[ $negative_rc -ne 0 ]] || fail "negative closure accepted"
grep -Fq 'EH_CLOSURE FAIL' "$TMP/negative.log" || fail "negative analyzer absent"
echo "EH_NEGATIVE forbidden_rc=$negative_rc status=PASS"
echo "run_eh_primitives_probe: PASS"
