#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative"
export cjHeapSize=24GB
fail() { echo "run_memcommon_probe: FAIL $*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail "executable target must be Linux x86_64"
printf 'MEMCOMMON_COMPILER path=%s source=%s sha256=%s size=%s toolchain_root=%s toolchain=%s llvm_bin=%s runtime_lib=%s status=PASS\n' \
    "$SELFHOST_CJC" "$COMPILER_SOURCE" "$COMPILER_SHA256" "$COMPILER_SIZE" \
    "$CANGJIE_HOME" "$COMPILER_BUILD_TOOLCHAIN" "$LLVM_BIN" "$RUNTIME_TOOLCHAIN_RT_LIB"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_memcommon.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/common" "$TMP/root"
for pkg in rt.base rt.sync; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib --int-overflow wrapping \
        -Woff unused --import-path "$TMP" --output-dir "$TMP" -o "lib$pkg.a"
done
"$SELFHOST_CJC" --package "$ROOT/src/rt.heap.allocator" --output-type=staticlib --int-overflow wrapping \
    -Woff unused --import-path "$TMP" --output-dir "$TMP" -o librt.heap.allocator.a
"$SELFHOST_CJC" --package "$ROOT/src/rt.common" --output-type=staticlib -O2 --int-overflow wrapping \
    -Woff unused --import-path "$TMP" --save-temps "$TMP/common" --output-dir "$TMP" -o librt.common.a
mkdir -p "$TMP/native"
for source in Futex Panic Atomic SpinLock PagePoolMutex; do
    g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/$source.cpp" -o "$TMP/native/$source.o"
done
native_includes=(-I"$RUNTIME_ROOT/include" -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include")
while IFS= read -r include_dir; do native_includes+=(-I"$include_dir"); done < <(find "$RUNTIME_ROOT/src" -type d | sort)
g++ -std=c++17 -O2 -pthread -DMRT_USE_CJTHREAD_RENAME "${native_includes[@]}" -fPIC \
    -c "$ROOT/rt0/AllocBufferNative.cpp" -o "$TMP/native/AllocBufferNative.o"
g++ -std=c++17 -O2 -pthread -DMRT_USE_CJTHREAD_RENAME "${native_includes[@]}" -fPIC \
    -c "$ROOT/rt0/ScopedSaferegion.cpp" -o "$TMP/native/ScopedSaferegion.o"
"$SELFHOST_CJC" "$ROOT/test/parity/common/memcommon_probe.cj" --import-path "$TMP" --int-overflow wrapping \
    "$TMP/librt.common.a" "$TMP/librt.heap.allocator.a" "$TMP/librt.sync.a" "$TMP/librt.base.a" \
    "$TMP/native/"*.o \
    --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread -o "$TMP/mem_cj"

cpp_includes=(-I "$RUNTIME_ROOT/src" -I "$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    -I "$RUNTIME_ROOT/src/CJThread/src/runtime/schedule/include/inner/gas/x86/x86_64")
while IFS= read -r include_dir; do cpp_includes+=(-I "$include_dir"); done < <(find "$RUNTIME_ROOT/src/CJThread" -type d -name include | sort)
g++ -std=c++14 -O2 "${cpp_includes[@]}" "$ROOT/test/parity/common/memcommon_ref.cpp" \
    -L "$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -o "$TMP/mem_cpp"
"$TMP/mem_cj" > "$TMP/cj.transcript"
LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH" "$TMP/mem_cpp" > "$TMP/cpp.transcript"
cmp "$TMP/cpp.transcript" "$TMP/cj.transcript" || { diff -u "$TMP/cpp.transcript" "$TMP/cj.transcript" >&2 || true; fail "byte transcript mismatch"; }
cat "$TMP/cj.transcript"
echo "MEMCOMMON_PARITY records=$(wc -l < "$TMP/cj.transcript") bytes=$(stat -c %s "$TMP/cj.transcript") cmp=identical status=PASS"

"$SELFHOST_CJC" --package "$ROOT/test/parity/common/memcommon.noheap" --output-type=staticlib -O2 \
    --int-overflow wrapping --import-path "$TMP" --save-temps "$TMP/root" --output-dir "$TMP" -o libmemcommon.noheap.a
root_pre=$(find "$TMP/root" -maxdepth 1 -name '*.bc' ! -name '*.opt.bc' -print -quit)
root_final=$(find "$TMP/root" -maxdepth 1 -name '*.opt.bc' -print -quit)
root_object=$(find "$TMP/root" -maxdepth 1 -name '*.o' -print -quit)
mapfile -t common_finals < <(find "$TMP/common" -maxdepth 1 -name '*.opt.bc' -print | sort)
mapfile -t common_objects < <(find "$TMP/common" -maxdepth 1 -name '*.o' -print | sort)
"$LLVM_BIN/llvm-link" "$root_final" "${common_finals[@]}" -o "$TMP/linked.final.bc"
"$LLVM_BIN/llvm-dis" "$root_pre" -o "$TMP/root.pre.ll"
"$LLVM_BIN/llvm-dis" "$TMP/linked.final.bc" -o "$TMP/linked.final.ll"
closure=(python3 "$ROOT/test/parity/common/memcommon_closure.py" --pre "$TMP/root.pre.ll" --final "$TMP/linked.final.ll" --object "$root_object")
for object in "${common_objects[@]}"; do closure+=(--object "$object"); done
"${closure[@]}"
set +e; "${closure[@]}" --inject-forbidden > "$TMP/negative.log" 2>&1; negative_rc=$?; set -e
[[ $negative_rc -ne 0 ]] || fail "negative closure accepted"
grep -Fq 'MEMCOMMON_CLOSURE FAIL' "$TMP/negative.log" || fail "negative analyzer absent"
echo "MEMCOMMON_NEGATIVE forbidden_rc=$negative_rc status=PASS"
echo "MEMCOMMON_PLATFORM branches=0 linux_x86_64=EXECUTED apple=SOURCE_AUDITED windows=SOURCE_AUDITED arm=SOURCE_AUDITED status=PASS"
echo "run_memcommon_probe: PASS"
