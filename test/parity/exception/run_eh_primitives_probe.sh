#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative"
export cjHeapSize=24GB
fail() { echo "run_eh_primitives_probe: FAIL $*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail "executable target must be Linux x86_64"
for tool in g++ cmp objdump python3 sha256sum; do command -v "$tool" >/dev/null || fail "missing $tool"; done
[[ -x "$SELFHOST_CJC" && -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] || fail "missing pinned compiler tools"

CPP_H="$RUNTIME_ROOT/src/Exception/EhTable.h"
CPP_CC="$RUNTIME_ROOT/src/Exception/EhTable.cpp"
[[ $(sed -n '14,72p' "$CPP_H" | grep -Ec '^#if|^#ifdef|^#elif') -eq 0 ]] || fail "unexpected primitive header platform branch"
[[ $(sed -n '52,65p' "$CPP_CC" | grep -Ec '^#if|^#ifdef|^#elif') -eq 0 ]] || fail "unexpected ULEB platform branch"
[[ $(sed -n '17,27p' "$CPP_CC" | grep -Ec '^#ifdef __arm__$') -eq 1 ]] || fail "missing C++ ReadAbsPtr ARM branch"
[[ $(sed -n '68,88p' "$CPP_CC" | grep -Ec '^#if defined\(__APPLE__\)$') -eq 1 ]] || fail "missing C++ SLEB Apple branch"
CPP_SLEB_PLATFORM=$(sed -n '/^#if defined(__APPLE__)$/,/^#endif$/p' "$CPP_CC")
[[ $(grep -Fc 'value |= LLONG_MAX << shift;' <<< "$CPP_SLEB_PLATFORM") -eq 1 &&
   $(grep -Fc 'value |= ULLONG_MAX << shift;' <<< "$CPP_SLEB_PLATFORM") -eq 1 ]] ||
    fail "C++ SLEB Apple/non-Apple constants drift"
CJ_SLEB_SOURCE="$ROOT/src/rt.exception/EhTablePrimitives.cj"
grep -Fq $'@When[os == "macOS" || os == "iOS"]\n@NoHeapAlloc\npublic func ReadSLEB128' \
    "$CJ_SLEB_SOURCE" || fail "missing Cangjie SLEB Apple arm"
grep -Fq $'@When[os != "macOS" && os != "iOS"]\n@NoHeapAlloc\npublic func ReadSLEB128' \
    "$CJ_SLEB_SOURCE" || fail "missing Cangjie SLEB non-Apple arm"
[[ $(grep -Fc 'public func ReadSLEB128' "$CJ_SLEB_SOURCE") -eq 2 &&
   $(grep -Fc 'value |= 0x7fffffffffffffffu64 << shift' "$CJ_SLEB_SOURCE") -eq 1 &&
   $(grep -Fc 'value |= 0xffffffffffffffffu64 << shift' "$CJ_SLEB_SOURCE") -eq 1 ]] ||
    fail "Cangjie SLEB Apple/non-Apple source constants drift"
[[ $(grep -Ec '^@When\[arch (==|!=) "arm"\]$' "$ROOT/src/rt.exception/EhTablePrimitives.cj") -eq 2 ]] ||
    fail "incomplete Cangjie ttype-reader width branches"
[[ $(grep -Ec '^@When\[arch (==|!=) "arm"\]$' "$ROOT/src/rt.exception/EhFramePrimitives.cj") -eq 2 ]] ||
    fail "incomplete Cangjie frame-reader width branches"
echo "EH_PLATFORM linux_x86_64=EXECUTED apple=SOURCE_AUDITED windows=SOURCE_AUDITED arm=SOURCE_AUDITED table_width_branches=2 frame_width_branches=2 status=PASS"
CPP_CONTEXT="$RUNTIME_ROOT/src/Exception/CalleeSavedRegisterContext.h"
CJ_CONTEXT="$ROOT/src/rt.exception/CalleeSavedRegisterContext.cj"
[[ $(grep -Fc 'public struct CalleeSavedRegisterContext' "$CJ_CONTEXT") -eq 4 &&
   $(grep -Fc 'public struct XMMReg' "$CJ_CONTEXT") -eq 1 ]] || fail "incomplete callee-saved storage arms"
[[ $(grep -Fc 'public func SetValueByIdx' "$CJ_CONTEXT") -eq 1 &&
   $(grep -Fc 'public func SetXMMValueByIdx' "$CJ_CONTEXT") -eq 1 ]] || fail "incomplete callee-saved slot writers"
grep -Fq '@When[(os == "Linux" || os == "macOS" || os == "iOS") && arch == "x86_64"]' \
    "$CJ_CONTEXT" || fail "missing Linux/Apple x86_64 context arm"
grep -Fq '@When[arch == "aarch64"]' "$CJ_CONTEXT" || fail "missing AArch64 context arm"
grep -Fq '@When[arch == "arm"]' "$CJ_CONTEXT" || fail "missing ARM32 context arm"
[[ $(grep -Fc '@When[os == "Windows" && arch == "x86_64"]' "$CJ_CONTEXT") -eq 3 ]] ||
    fail "incomplete Win64 storage/writer arms"
for cpp_arm in '#if (defined(__linux__) || defined(__APPLE__)) && defined(__x86_64__)' \
    '#elif defined(__aarch64__)' '#elif defined(__arm__)' '#elif defined(_WIN64)'; do
    grep -Fq "$cpp_arm" "$CPP_CONTEXT" || fail "missing C++ context arm: $cpp_arm"
done
echo "EH_CONTEXT_PLATFORM linux_x86_64=EXECUTED apple_x86_64=SOURCE_AUDITED aarch64=SOURCE_AUDITED arm=SOURCE_AUDITED win64=SOURCE_AUDITED status=PASS"
echo "EH_CONTEXT_WRITERS set_value_free=1 win64_xmm_free=1 cpp_members=2 status=PASS"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_eh_primitives.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/exception" "$TMP/root"
"$SELFHOST_CJC" --package "$ROOT/src/rt.base" --output-type=staticlib -O2 \
    --int-overflow wrapping --output-dir "$TMP" -o "$TMP/librt.base.a"
(
    cd "$TMP"
    "$SELFHOST_CJC" --package "$ROOT/src/rt.exception" --output-type=staticlib -O2 \
        --int-overflow wrapping --import-path "$TMP" --save-temps "$TMP/exception" \
        --output-dir "$TMP" -o librt.exception.a
)
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
"$SELFHOST_CJC" "$ROOT/test/parity/exception/eh_primitives_probe.cj" --import-path "$TMP" \
    --int-overflow wrapping "$TMP/librt.exception.a" "$TMP/librt.base.a" "$TMP/Panic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/eh_cj"
cpp_includes=(-I "$RUNTIME_ROOT/src" \
    -I "$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    -I "$RUNTIME_ROOT/src/CJThread/src/runtime/schedule/include/inner/gas/x86/x86_64")
while IFS= read -r include_dir; do cpp_includes+=(-I "$include_dir"); done \
    < <(find "$RUNTIME_ROOT/src/CJThread" -type d -name include | sort)
g++ -std=c++14 -O2 "${cpp_includes[@]}" \
    "$ROOT/test/parity/exception/eh_primitives_ref.cpp" -L "$CPP_RUNTIME_LIB" \
    -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -o "$TMP/eh_cpp"
"$TMP/eh_cj" > "$TMP/cj.transcript"
LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH" \
    "$TMP/eh_cpp" > "$TMP/cpp.transcript"
cmp "$TMP/cpp.transcript" "$TMP/cj.transcript" || {
    diff -u "$TMP/cpp.transcript" "$TMP/cj.transcript" >&2 || true
    fail "byte transcript mismatch"
}
cat "$TMP/cj.transcript"
echo "EH_PARITY records=$(wc -l < "$TMP/cj.transcript") bytes=$(stat -c %s "$TMP/cj.transcript") sha256=$(sha256sum "$TMP/cj.transcript" | awk '{print $1}') cmp=identical status=PASS"

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
[[ ${#exception_finals[@]} -eq ${#exception_objects[@]} && ${#exception_finals[@]} -ge 1 ]] ||
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
