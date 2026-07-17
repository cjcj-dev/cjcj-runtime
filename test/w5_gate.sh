#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-"$ROOT/out/w5-gate"}
REPO=${REPO:-/root/cj_build/cjcj}
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
CJC=${CJC:-"$REPO/target/release/bin/cjcj::cjc"}
REF_CJC=${REF_CJC:-"$CANGJIE_HOME/bin/cjc"}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}
RTLIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
LLC="$CANGJIE_HOME/third_party/llvm/bin/llc"
REFERENCE="$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
RUNTIME_ARCHIVE="$RUNTIME_ROOT/target/common/linux_release_x86_64/lib/linux_x86_64_cjnative/libcangjie-runtime.a"

export CANGJIE_HOME
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$RTLIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

rm -rf "$OUT"
mkdir -p "$OUT/probe" "$OUT/g11/o0" "$OUT/g11/o2" "$OUT/abi" "$OUT/demangle-cwd" \
    "$OUT/demangle-object" "$OUT/oracle"

"$CJC" "$ROOT/test/compiler_gap/w5_cfunc_export.cj" --output-type dylib \
    -o "$OUT/probe/libw5_probe.so"
"$CJC" "$ROOT/test/compiler_gap/w5_cfunc_export.cj" --experimental \
    --output-type obj --compile-target dylib -O2 -o "$OUT/probe/w5_probe.o"
probe_so=$(nm -D --defined-only "$OUT/probe/libw5_probe.so" |
    awk '$3 == "W5_CFuncExportProbe" { count++ } END { print count + 0 }')
probe_obj=$(nm -g --defined-only "$OUT/probe/w5_probe.o" |
    awk '$3 == "W5_CFuncExportProbe" { count++ } END { print count + 0 }')
probe_mangled=$(nm -g --defined-only "$OUT/probe/w5_probe.o" |
    awk '$3 ~ /^_CN.*W5_CFuncExportProbe/ { count++ } END { print count + 0 }')
test "$probe_so" -eq 1
test "$probe_obj" -eq 1
test "$probe_mangled" -eq 0
printf 'CFUNC PROBE PASS so_c=%s obj_c=%s mangled=%s\n' "$probe_so" "$probe_obj" "$probe_mangled"

"$CJC" "$ROOT/test/compiler_gap/w2_varray_struct_store.cj" --experimental \
    --output-type obj --compile-target dylib --save-temps "$OUT/g11/o0" \
    -o "$OUT/g11/o0/probe.o" -Woff unused
"$CJC" "$ROOT/test/compiler_gap/w2_varray_struct_store.cj" --experimental \
    --output-type obj --compile-target dylib -O2 --save-temps "$OUT/g11/o2" \
    -o "$OUT/g11/o2/probe.o" -Woff unused
g11_o0_bytes=$(wc -c < "$OUT/g11/o0/probe.o")
g11_o2_bytes=$(wc -c < "$OUT/g11/o2/probe.o")
file "$OUT/g11/o0/probe.o" "$OUT/g11/o2/probe.o" | grep -Fc 'ELF 64-bit LSB relocatable' |
    awk '$1 == 2 { found=1 } END { exit !found }'
printf 'G11-PROBE O0_exit=0 O0_bytes=%s O2_exit=0 O2_bytes=%s\n' \
    "$g11_o0_bytes" "$g11_o2_bytes"

"$CJC" -p "$ROOT/src/rt.abi" --experimental --output-type obj \
    --compile-target dylib --int-overflow wrapping -O2 \
    --save-temps "$OUT/abi" -o "$OUT/abi/rt.abi.raw.o" -Woff unused
"$LLC" "$OUT/abi/rt.abi.opt.bc" --cangjie-pipeline -disable-debug-info-print \
    --relocation-model=pic --frame-pointer=non-leaf --stack-trace-format=default \
    -mcpu=generic -mattr=-avx --cj-safepoint-outline=false -O2 \
    --function-sections --filetype=obj -o "$OUT/abi/rt.abi.o"
abi_c=$(nm -g --defined-only "$OUT/abi/rt.abi.o" |
    awk '$3 == "MRT_DumpLog" { count++ } END { print count + 0 }')
abi_mangled=$(nm -g --defined-only "$OUT/abi/rt.abi.o" |
    awk '$3 ~ /^_CN.*MRT_DumpLog/ { count++ } END { print count + 0 }')
test "$abi_c" -eq 1
test "$abi_mangled" -eq 0
nm -u "$OUT/abi/rt.abi.o" | grep -Fq 'CJRT_BaseDumpLog'
env_symbols=(
    _ZN12MapleRuntime7CString15ParseNumFromEnvERKS0_
    _ZN12MapleRuntime7CString12IsPosDecimalERKS0_
    _ZN12MapleRuntime7CString8IsNumberERKS0_
)
env_aliases=(
    CJRT_BaseParseNumFromEnv
    CJRT_BaseIsPosDecimal
    CJRT_BaseIsNumber
)
for symbol in "${env_symbols[@]}"; do
    nm -g --defined-only "$OUT/abi/rt.abi.o" |
        awk -v wanted="$symbol" '$3 == wanted { found++ } END { exit found != 1 }'
done
for alias in "${env_aliases[@]}"; do
    nm -u "$OUT/abi/rt.abi.o" |
        awk -v wanted="$alias" '$NF == wanted { found++ } END { exit found != 1 }'
done
log_symbols=(
    _ZN12MapleRuntime7LogFile13CloseLogFilesEv
    _ZN12MapleRuntime7LogFile8SetFlagsEv
    _ZN12MapleRuntime7LogFile14SetFlagWithEnvEPKcNS_7LogTypeE
)
log_aliases=(
    CJRT_BaseCloseLogFiles
    CJRT_BaseSetLogFlags
    CJRT_BaseSetLogFlagWithEnv
)
for symbol in "${log_symbols[@]}"; do
    nm -g --defined-only "$OUT/abi/rt.abi.o" |
        awk -v wanted="$symbol" '$3 == wanted { found++ } END { exit found != 1 }'
done
for alias in "${log_aliases[@]}"; do
    nm -u "$OUT/abi/rt.abi.o" |
        awk -v wanted="$alias" '$NF == wanted { found++ } END { exit found != 1 }'
done
printf 'RT.ABI OBJECT PASS c=%s mangled=%s base_forward=1 env_forward=%s log_forward=%s\n' \
    "$abi_c" "$abi_mangled" "${#env_symbols[@]}" "${#log_symbols[@]}"

(
    cd "$OUT/demangle-cwd"
    cjHeapSize=${BUILD_HEAP_SIZE:-2GB} "$CJC" -p "$ROOT/src/rt.demangle" \
        --output-type staticlib -O2 --int-overflow wrapping \
        -o "$OUT/librt.demangle.a"
)
(
    cd "$OUT/demangle-object"
    llvm-ar x "$OUT/librt.demangle.a"
)
DEMANGLE_OBJECT="$OUT/demangle-object/rt.demangle.o"
test -f "$DEMANGLE_OBJECT"

env -u LD_LIBRARY_PATH cmake -S "$ROOT" -B "$OUT/cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_ASM_COMPILER=clang -DCANGJIE_RUNTIME_SOURCE="$RUNTIME_ROOT"
env -u LD_LIBRARY_PATH cmake --build "$OUT/cmake" \
    --target cjcj_rt0 cjcj_rt_instance_object --parallel

HYBRID="$OUT/hybrid/libcangjie-runtime.so"
python3 "$ROOT/build/link_hybrid.py" --runtime-root "$RUNTIME_ROOT" \
    --toolchain "$CANGJIE_HOME" --rt0-archive "$OUT/cmake/lib/libcjcj_rt0.a" \
    --instance-bridge "$OUT/cmake/lib/instance_bridge.o" \
    --inject "$OUT/abi/rt.abi.o" \
    --inject "$DEMANGLE_OBJECT" \
    --preserve-collision MRT_DumpLog=CJRT_BaseDumpLog \
    --preserve-collision _ZN12MapleRuntime7CString15ParseNumFromEnvERKS0_=CJRT_BaseParseNumFromEnv \
    --preserve-collision _ZN12MapleRuntime7CString12IsPosDecimalERKS0_=CJRT_BaseIsPosDecimal \
    --preserve-collision _ZN12MapleRuntime7CString8IsNumberERKS0_=CJRT_BaseIsNumber \
    --preserve-collision _ZN12MapleRuntime7LogFile13CloseLogFilesEv=CJRT_BaseCloseLogFiles \
    --preserve-collision _ZN12MapleRuntime7LogFile8SetFlagsEv=CJRT_BaseSetLogFlags \
    --preserve-collision _ZN12MapleRuntime7LogFile14SetFlagWithEnvEPKcNS_7LogTypeE=CJRT_BaseSetLogFlagWithEnv \
    --output "$HYBRID" \
    --work-dir "$OUT/hybrid-work"
python3 "$ROOT/build/symcheck.py" "$REFERENCE" "$HYBRID"

HYBRID="$HYBRID" OUT="$OUT/instance-contract" \
    bash "$ROOT/test/contract/instance/run_contract.sh"

official_symbol=$(objdump -T "$REFERENCE" | awk '$NF == "MRT_DumpLog" { print }')
hybrid_symbol=$(objdump -T "$HYBRID" | awk '$NF == "MRT_DumpLog" { print }')
test -n "$official_symbol"
test -n "$hybrid_symbol"
official_shape=$(objdump -T "$REFERENCE" |
    awk '$2 == "g" && $3 == "DF" && $4 == ".text" && $6 == "CANGJIE" && $7 == "MRT_DumpLog" { print $2, $3, $4, $6, $7 }')
hybrid_shape=$(objdump -T "$HYBRID" |
    awk '$2 == "g" && $3 == "DF" && $4 == ".text" && $6 == "CANGJIE" && $7 == "MRT_DumpLog" { print $2, $3, $4, $6, $7 }')
test "$official_shape" = 'g DF .text CANGJIE MRT_DumpLog'
test "$hybrid_shape" = "$official_shape"
printf 'OBJDUMP OFFICIAL %s\n' "$official_symbol"
printf 'OBJDUMP HYBRID   %s\n' "$hybrid_symbol"
nm --defined-only "$HYBRID" | awk '$3 == "CJRT_BaseDumpLog" { found++ } END { exit found != 1 }'
objdump -p "$HYBRID" | grep -Fq 'SONAME               libcangjie-runtime.so'

(
    cd "$OUT/oracle"
    llvm-ar x "$RUNTIME_ARCHIVE" LogFile.cpp.o CString.cpp.o
)
llvm-objcopy --dump-section .text.MRT_DumpLog="$OUT/oracle/original.text" "$OUT/oracle/LogFile.cpp.o"
llvm-objcopy --dump-section .text.MRT_DumpLog="$OUT/oracle/renamed.text" "$OUT/hybrid-work/runtime/LogFile.cpp.o"
cmp "$OUT/oracle/original.text" "$OUT/oracle/renamed.text"
text_bytes=$(wc -c < "$OUT/oracle/original.text")
printf 'BASE FORWARD PARITY PASS text_bytes=%s byte_diff=0\n' "$text_bytes"

env_bytes=0
for symbol in "${env_symbols[@]}"; do
    llvm-objcopy --dump-section ".text.$symbol=$OUT/oracle/$symbol.original.text" \
        "$OUT/oracle/CString.cpp.o"
    llvm-objcopy --dump-section ".text.$symbol=$OUT/oracle/$symbol.renamed.text" \
        "$OUT/hybrid-work/runtime/CString.cpp.o"
    cmp "$OUT/oracle/$symbol.original.text" "$OUT/oracle/$symbol.renamed.text"
    bytes=$(wc -c < "$OUT/oracle/$symbol.original.text")
    env_bytes=$((env_bytes + bytes))
done
printf 'ENV FORWARD PARITY PASS symbols=%s text_bytes=%s byte_diff=0\n' \
    "${#env_symbols[@]}" "$env_bytes"

log_bytes=0
for symbol in "${log_symbols[@]}"; do
    llvm-objcopy --dump-section ".text.$symbol=$OUT/oracle/$symbol.original.text" \
        "$OUT/oracle/LogFile.cpp.o"
    llvm-objcopy --dump-section ".text.$symbol=$OUT/oracle/$symbol.renamed.text" \
        "$OUT/hybrid-work/runtime/LogFile.cpp.o"
    cmp "$OUT/oracle/$symbol.original.text" "$OUT/oracle/$symbol.renamed.text"
    bytes=$(wc -c < "$OUT/oracle/$symbol.original.text")
    log_bytes=$((log_bytes + bytes))
done
printf 'LOG FORWARD PARITY PASS symbols=%s text_bytes=%s byte_diff=0\n' \
    "${#log_symbols[@]}" "$log_bytes"

"$REF_CJC" "$ROOT/test/parity/w5/dump_log.cj" -O2 --set-runtime-rpath \
    -o "$OUT/dump_log"
"$REF_CJC" "$ROOT/test/parity/w5/env_exports.cj" -O2 --set-runtime-rpath \
    -o "$OUT/env_exports"
"$REF_CJC" "$ROOT/test/parity/w5/log_leaves.cj" -O2 --set-runtime-rpath \
    -o "$OUT/log_leaves"
"$OUT/env_exports"
LD_PRELOAD="$HYBRID${LD_PRELOAD:+:$LD_PRELOAD}" "$OUT/env_exports"
printf 'ENV CALL PARITY PASS fixed_cases=5 official=0 hybrid=0\n'
"$OUT/log_leaves"
LD_PRELOAD="$HYBRID${LD_PRELOAD:+:$LD_PRELOAD}" "$OUT/log_leaves"
printf 'LOG CALL PARITY PASS leaves=3 official=0 hybrid=0\n'
MRT_LOG_CJTHREAD="$OUT/cfunc.log" LD_PRELOAD="$HYBRID${LD_PRELOAD:+:$LD_PRELOAD}" \
    "$OUT/dump_log"
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6} [0-9]+ W5_CFUNC_EXPORT$' \
    "$OUT/cfunc.log"
log_lines=$(wc -l < "$OUT/cfunc.log")
test "$log_lines" -eq 1
printf 'CFUNC CALL PASS log_lines=%s payload=W5_CFUNC_EXPORT\n' "$log_lines"

if [ "${SKIP_DIFFTEST:-0}" = 1 ]; then
    printf 'DIFFTEST SKIP SKIP_DIFFTEST=1\n'
    exit 0
fi

(
    cd "$REPO"
    LD_PRELOAD="$HYBRID${LD_PRELOAD:+:$LD_PRELOAD}" \
        bash scripts/difftest.sh -j "${DIFFTEST_JOBS:-4}"
) | tee "$OUT/difftest.log"
grep -Fq 'TOTAL=114  PASS=114  MISMATCH=0  FAIL=0' "$OUT/difftest.log"
printf 'W5 GATE PASS cfunc=1 instance=1 symcheck=2692/2695 base_text=%s difftest=114/114\n' "$text_bytes"
