#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${OUT:-"$ROOT/out/managed-instance-contract"}
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}
HYBRID=${HYBRID:-"$ROOT/out/gate/hybrid/libcangjie-runtime.so"}
MODE=${MODE:-s4}
CYCLES=${CYCLES:-1}
TIMEOUT=${TIMEOUT:-30s}
ORACLE="$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
RTLIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"

export PATH=/root/.cjv/bin:$PATH
export CANGJIE_HOME
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$RTLIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}

rm -rf "$OUT"
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

printf 'MANAGED_CONTRACT_DISK_BEFORE '
df -Pk "$ROOT" | tail -n 1

clang -std=gnu11 -O2 -Wall -Wextra -Werror -c \
    "$ROOT/test/contract/instance/managed_host_support.c" -o "$OUT/managed_host_support.o"
(
    cd "$OUT"
    "$SELFHOST_CJC" "$ROOT/test/contract/instance/managed_host_contract.cj" \
        --set-runtime-rpath --link-option "$OUT/managed_host_support.o" \
        --link-option=-ldl -o "$OUT/managed_host_contract"
)

runtime=$HYBRID
if [[ "$MODE" == official ]]; then
    runtime=$ORACLE
fi
test -f "$runtime"

set +e
CJCJ_CONTRACT_MODE="$MODE" CJCJ_CONTRACT_CYCLES="$CYCLES" \
    LD_PRELOAD="$runtime" timeout --signal=KILL "$TIMEOUT" \
    "$OUT/managed_host_contract" 2>&1 | tee "$OUT/$MODE.log"
rc=${PIPESTATUS[0]}
set -e
printf 'MANAGED_CONTROL mode=%s rc=%s timeout=%s cycles=%s\n' "$MODE" "$rc" "$TIMEOUT" "$CYCLES"
if [[ "$rc" -ne 0 ]]; then
    exit "$rc"
fi
grep -Fq "MANAGED_CONTRACT PASS mode=$MODE cycles=$CYCLES" "$OUT/$MODE.log"

rm -f "$OUT/managed_host_contract" "$OUT/managed_host_support.o"
printf 'MANAGED_CONTRACT_DISK_AFTER '
df -Pk "$ROOT" | tail -n 1
