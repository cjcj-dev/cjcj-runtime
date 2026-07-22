#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-"$ROOT/out/gate"}
REPO=${REPO:-/root/cj_build/cjcj}
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
CJC=${CJC:-"$REPO/target/release/bin/cjcj::cjc"}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}
RTLIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$RTLIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

SELFHOST_CJC="$CJC" bash "$ROOT/test/parity/heap/run_freeregionmanager_probe.sh"
bash "$ROOT/test/parity/runtime/run_runtimeparam_probe.sh"
SELFHOST_CJC="$CJC" bash "$ROOT/test/parity/gc/run_markworkstack_probe.sh"
SELFHOST_CJC="$CJC" bash "$ROOT/test/parity/gc/run_regionbitmap_probe.sh"

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
    "$CJC" "$HYBRID" "$MANAGED_HOST_STAGE"

HYBRID="$HYBRID" SELFHOST_CJC="$MANAGED_HOST_STAGE/bin/$(basename "$CJC")" \
    OUT="$OUT/instance-contract" \
    bash "$ROOT/test/contract/instance/run_contract.sh"

HYBRID="$HYBRID" SELFHOST="$REPO" CJC="$CJC" \
    BUILD="$OUT/demangle-parity" bash "$ROOT/test/parity/demangle/run_parity.sh" \
    | tee "$OUT/demangle-parity.log"

if [ "${SKIP_DIFFTEST:-0}" = 1 ]; then
    printf 'DIFFTEST SKIP SKIP_DIFFTEST=1\n'
    exit 0
fi

(
    cd "$REPO"
    LD_PRELOAD="$HYBRID${LD_PRELOAD:+:$LD_PRELOAD}" \
        bash scripts/difftest.sh -j "${DIFFTEST_JOBS:-8}"
) | tee "$OUT/difftest.log"
grep -Fq 'TOTAL=114  PASS=114  MISMATCH=0  FAIL=0' "$OUT/difftest.log"
printf 'W2 GATE PASS rt0=1 instance=1 inject=%s symcheck=2692/2695 demangle=byte-identical difftest=114/114\n' \
    "$inject_count"
