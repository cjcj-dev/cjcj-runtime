#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
CJC_BIN_DIR=$(cd "${SELFHOST_CJC%/*}" && pwd -P)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

fail() { echo "run_callee_saved_probe: FAIL $*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail "executable target must be Linux x86_64"
for tool in g++ cmp objdump python3; do command -v "$tool" >/dev/null || fail "missing $tool"; done
[[ -x "$SELFHOST_CJC" && -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] || fail "missing pinned compiler tools"

SOURCE="$ROOT/src/rt.exception/CalleeSavedRegisterContext.cj"
grep -Fq '@When[(os == "Linux" || env == "ohos" || os == "macOS" || os == "iOS") && arch == "x86_64"]' "$SOURCE" || fail "missing SysV x86_64 branch"
[[ $(grep -Fc '@When[arch == "aarch64"]' "$SOURCE") -eq 1 ]] || fail "missing AArch64 branch"
[[ $(grep -Fc '@When[arch == "arm"]' "$SOURCE") -eq 1 ]] || fail "missing ARM32 branch"
[[ $(grep -Fc '@When[os == "Windows" && arch == "x86_64"]' "$SOURCE") -eq 2 ]] || fail "missing Win64 context/XMM branches"
echo "CALLEE_PLATFORM linux_x86_64=EXECUTED apple_x86_64=SOURCE_AUDITED aarch64=SOURCE_AUDITED arm32=SOURCE_AUDITED win64=SOURCE_AUDITED status=PASS"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_callee_saved.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/base" "$TMP/exception" "$TMP/root"

(
    cd "$TMP"
    "$SELFHOST_CJC" --package "$ROOT/src/rt.base" --output-type=staticlib -O2 \
        --int-overflow wrapping --save-temps "$TMP/base" --output-dir "$TMP" -o librt.base.a
    "$SELFHOST_CJC" --package "$ROOT/src/rt.exception" --output-type=staticlib -O2 \
        --int-overflow wrapping --import-path "$TMP" --save-temps "$TMP/exception" \
        --output-dir "$TMP" -o librt.exception.a
)
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"
"$SELFHOST_CJC" "$ROOT/test/parity/exception/callee_saved_probe.cj" --import-path "$TMP" \
    --int-overflow wrapping "$TMP/librt.exception.a" "$TMP/librt.base.a" \
    "$TMP/Panic.o" "$TMP/Atomic.o" --link-option=-lstdc++ --link-option=-lgcc_s \
    -o "$TMP/callee_saved_cj"
g++ -std=c++14 -O2 -I "$RUNTIME_ROOT/src" \
    "$ROOT/test/parity/exception/callee_saved_ref.cpp" -o "$TMP/callee_saved_cpp"
"$TMP/callee_saved_cj" > "$TMP/cj.transcript"
"$TMP/callee_saved_cpp" > "$TMP/cpp.transcript"
cmp "$TMP/cpp.transcript" "$TMP/cj.transcript"
cat "$TMP/cj.transcript"
echo "CALLEE_PARITY bytes=$(stat -c %s "$TMP/cj.transcript") cmp=identical status=PASS"

(
    cd "$TMP"
    "$SELFHOST_CJC" --package "$ROOT/test/parity/exception/callee_saved_noheap_root.cj" \
        --output-type=staticlib -O2 --int-overflow wrapping --import-path "$TMP" \
        --save-temps "$TMP/root" --output-dir "$TMP" -o libcallee.noheap.a
)
root_pre=$(find "$TMP/root" -maxdepth 1 -name '*.bc' ! -name '*.opt.bc' -print -quit)
root_final=$(find "$TMP/root" -maxdepth 1 -name '*.opt.bc' -print -quit)
exception_final=$(find "$TMP/exception" -maxdepth 1 -name '*.opt.bc' -print -quit)
[[ -n "$root_pre" && -n "$root_final" && -n "$exception_final" ]] || fail "missing closure bitcode"
"$LLVM_BIN/llvm-link" "$root_final" "$exception_final" -o "$TMP/linked.final.bc"
"$LLVM_BIN/llvm-dis" "$root_pre" -o "$TMP/root.pre.ll"
"$LLVM_BIN/llvm-dis" "$TMP/linked.final.bc" -o "$TMP/linked.final.ll"
root_object=$(find "$TMP/root" -maxdepth 1 -name '*.o' -print -quit)
exception_object=$(find "$TMP/exception" -maxdepth 1 -name '*.o' -print -quit)
closure=(python3 "$ROOT/test/parity/exception/callee_saved_closure.py" \
    --pre "$TMP/root.pre.ll" --final "$TMP/linked.final.ll" \
    --object "$root_object" --object "$exception_object")
"${closure[@]}"
set +e
"${closure[@]}" --inject-forbidden > "$TMP/negative.log" 2>&1
negative_rc=$?
set -e
[[ $negative_rc -ne 0 ]] || fail "closure negative accepted"
grep -Fq 'CALLEE_CLOSURE FAIL' "$TMP/negative.log" || fail "closure negative analyzer absent"
echo "CALLEE_NEGATIVE forbidden_rc=$negative_rc status=PASS"
echo "run_callee_saved_probe: PASS"
