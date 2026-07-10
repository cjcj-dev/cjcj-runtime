#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-"$ROOT/out/gate"}
REPO=${REPO:-/root/cj_build/cangjie_compiler_selfhost}
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
CJC=${CJC:-"$REPO/target/release/bin/cangjie_compiler::cjc"}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}
RTLIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$RTLIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

rm -rf "$OUT"
mkdir -p "$OUT"

env -u LD_LIBRARY_PATH cmake -S "$ROOT" -B "$OUT/cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_ASM_COMPILER=clang \
    -DCANGJIE_RUNTIME_SOURCE="$RUNTIME_ROOT"
env -u LD_LIBRARY_PATH cmake --build "$OUT/cmake" --target cjcj_rt0 --parallel

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

HYBRID="$OUT/hybrid/libcangjie-runtime.so"
python3 "$ROOT/build/link_hybrid.py" \
    --runtime-root "$RUNTIME_ROOT" \
    --toolchain "$CANGJIE_HOME" \
    --rt0-archive "$OUT/cmake/lib/libcjcj_rt0.a" \
    --inject "$EMPTY_OBJECT" \
    --output "$HYBRID"
python3 "$ROOT/build/symcheck.py" \
    "$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so" \
    "$HYBRID"

map_hits=$(grep -Fc "$EMPTY_OBJECT" "$HYBRID.map" || true)
if [ "$map_hits" -eq 0 ]; then
    printf 'EMPTY INJECT FAIL object absent from link map: %s\n' "$EMPTY_OBJECT" >&2
    exit 1
fi
printf 'EMPTY INJECT PASS objects=1 map_hits=%s\n' "$map_hits"

if [ "${SKIP_DIFFTEST:-0}" = 1 ]; then
    printf 'DIFFTEST SKIP SKIP_DIFFTEST=1\n'
    exit 0
fi

(
    cd "$REPO"
    LD_PRELOAD="$HYBRID${LD_PRELOAD:+:$LD_PRELOAD}" bash scripts/difftest.sh
) | tee "$OUT/difftest.log"
grep -Fq 'TOTAL=114  PASS=114  MISMATCH=0  FAIL=0' "$OUT/difftest.log"
printf 'W1 GATE PASS rt0=1 inject=1 symcheck=2692/2692 difftest=114/114\n'
