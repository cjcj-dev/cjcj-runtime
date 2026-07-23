#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/test/compiler_identity.sh"
OUT=${OUT:-"$ROOT/out/gate"}
REPO=${REPO:-/root/cj_build/cjcj}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}

bash "$ROOT/test/runtime_build_gate.sh" full
bash "$ROOT/test/parity/sched/run_sched_lowdeps_probe.sh"
bash "$ROOT/test/parity/sched/run_trace_vocab_probe.sh"
bash "$ROOT/test/parity/heap/run_freeregionmanager_probe.sh"
bash "$ROOT/test/parity/exception/run_eh_primitives_probe.sh"
bash "$ROOT/test/parity/runtime/run_runtimeparam_probe.sh"
bash "$ROOT/test/parity/gc/run_markworkstack_probe.sh"
bash "$ROOT/test/parity/gc/run_regionbitmap_probe.sh"
bash "$ROOT/test/parity/gc/run_forwarddata_probe.sh"
bash "$ROOT/test/parity/objectmodel/run_field_ref_probe.sh"
bash "$ROOT/test/parity/objectmodel/run_gctib_probe.sh"

rm -rf "$OUT"
mkdir -p "$OUT"

env -u LD_LIBRARY_PATH cmake -S "$ROOT" -B "$OUT/cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_ASM_COMPILER=clang \
    -DCANGJIE_RUNTIME_SOURCE="$RUNTIME_ROOT"
env -u LD_LIBRARY_PATH cmake --build "$OUT/cmake" \
    --target cjcj_rt0 cjcj_rt_instance_object --parallel

mkdir -p "$OUT/empty-cwd" "$OUT/empty-object"
(
    cd "$OUT/empty-cwd"
    "$CJC" -p "$ROOT/test/hybrid_empty" --output-type staticlib \
        -o "$OUT/libhybrid_empty.a"
)
(
    cd "$OUT/empty-object"
    llvm-ar x "$OUT/libhybrid_empty.a"
)
EMPTY_OBJECT="$OUT/empty-object/hybrid_empty.o"
test -f "$EMPTY_OBJECT"

mkdir -p "$OUT/demangle-cwd" "$OUT/demangle-object" "$OUT/abi-cwd" "$OUT/abi-object"
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
if nm -u "$DEMANGLE_OBJECT" | grep -Eq 'CJ_MCC_(New|Write|Throw)'; then
    printf 'RESTRICTED DIALECT FAIL managed allocation/barrier/throw edge found\n' >&2
    exit 1
fi
printf 'RESTRICTED DIALECT PASS managed_edges=0\n'
(
    cd "$OUT/abi-cwd"
    "$CJC" -p "$ROOT/src/rt.abi" --output-type staticlib -O2 \
        --int-overflow wrapping -o "$OUT/librt.abi.a"
)
(
    cd "$OUT/abi-object"
    llvm-ar x "$OUT/librt.abi.a"
)
ABI_OBJECT="$OUT/abi-object/rt.abi.o"
test -f "$ABI_OBJECT"
if nm -u "$ABI_OBJECT" | grep -Eq 'CJ_MCC_(New|Write|Throw)'; then
    printf 'RESTRICTED DIALECT FAIL rt.abi managed allocation/barrier/throw edge found\n' >&2
    exit 1
fi
printf 'RESTRICTED DIALECT PASS rt.abi_managed_edges=0\n'

HYBRID="$OUT/hybrid/libcangjie-runtime.so"
python3 "$ROOT/build/link_hybrid.py" \
    --runtime-root "$RUNTIME_ROOT" \
    --toolchain "$CANGJIE_HOME" \
    --rt0-archive "$OUT/cmake/lib/libcjcj_rt0.a" \
    --instance-bridge "$OUT/cmake/lib/instance_bridge.o" \
    --inject "$EMPTY_OBJECT" \
    --inject "$DEMANGLE_OBJECT" \
    --inject "$ABI_OBJECT" \
    --preserve-collision MRT_DumpLog=CJRT_BaseDumpLog \
    --preserve-collision _ZN12MapleRuntime7CString15ParseNumFromEnvERKS0_=CJRT_BaseParseNumFromEnv \
    --preserve-collision _ZN12MapleRuntime7CString12IsPosDecimalERKS0_=CJRT_BaseIsPosDecimal \
    --preserve-collision _ZN12MapleRuntime7CString8IsNumberERKS0_=CJRT_BaseIsNumber \
    --preserve-collision _ZN12MapleRuntime7LogFile13CloseLogFilesEv=CJRT_BaseCloseLogFiles \
    --preserve-collision _ZN12MapleRuntime7LogFile8SetFlagsEv=CJRT_BaseSetLogFlags \
    --preserve-collision _ZN12MapleRuntime7LogFile14SetFlagWithEnvEPKcNS_7LogTypeE=CJRT_BaseSetLogFlagWithEnv \
    --output "$HYBRID"
python3 "$ROOT/build/symcheck.py" \
    "$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so" \
    "$HYBRID"

injected_objects=("$OUT/cmake/lib/instance_bridge.o" "$EMPTY_OBJECT" "$DEMANGLE_OBJECT" "$ABI_OBJECT")
for object in "${injected_objects[@]}"; do
    map_hits=$(grep -Fc "$object" "$HYBRID.map" || true)
    if [ "$map_hits" -eq 0 ]; then
        printf 'INJECT FAIL object absent from link map: %s\n' "$object" >&2
        exit 1
    fi
done
inject_count=${#injected_objects[@]}
printf 'INJECT PASS objects=%s\n' "$inject_count"

MANAGED_HOST_STAGE="$OUT/managed-host"
bash "$ROOT/test/contract/instance/run_staged_managed_host.sh" \
    "$HYBRID" "$MANAGED_HOST_STAGE"

HYBRID="$HYBRID" OUT="$OUT/instance-contract" \
    bash "$ROOT/test/contract/instance/run_contract.sh"

HYBRID="$HYBRID" SELFHOST="$REPO" \
    BUILD="$OUT/demangle-parity" bash "$ROOT/test/parity/demangle/run_parity.sh" \
    | tee "$OUT/demangle-parity.log"

if [ "${SKIP_DIFFTEST:-0}" = 1 ]; then
    printf 'DIFFTEST SKIP SKIP_DIFFTEST=1\n'
    exit 0
fi

DIFFTEST_ROOT="$OUT/difftest-selfhost"
mkdir -p "$DIFFTEST_ROOT/scripts" "$DIFFTEST_ROOT/target/release/bin"
cp "$REPO/scripts/difftest.sh" "$DIFFTEST_ROOT/scripts/difftest.sh"
ln -s "$ROOT/test/published_cjc.sh" "$DIFFTEST_ROOT/target/release/bin/cjcj::cjc"

(
    cd "$DIFFTEST_ROOT"
    LD_PRELOAD="$HYBRID${LD_PRELOAD:+:$LD_PRELOAD}" \
        bash scripts/difftest.sh "$REPO/scripts/difftest_corpus" -j "${DIFFTEST_JOBS:-8}"
) | tee "$OUT/difftest.log"
grep -Fq 'TOTAL=114  PASS=114  MISMATCH=0  FAIL=0' "$OUT/difftest.log"
printf 'W2 GATE PASS rt0=1 instance=1 inject=%s symcheck=2692/2695 demangle=byte-identical TOTAL=114 PASS=114 MISMATCH=0 FAIL=0\n' \
    "$inject_count"
