#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${OUT:-"$ROOT/out/instance-contract"}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
HYBRID=${HYBRID:-"$ROOT/out/gate/hybrid/libcangjie-runtime.so"}
BOUNDS="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"

rm -rf "$OUT"
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

printf 'INSTANCE_CONTRACT_DISK_BEFORE '
df -Pk "$ROOT" | tail -n 1

symbols=(CJCJ_MRT_InstanceNew CJCJ_MRT_InstanceRunTask CJCJ_MRT_InstanceStop)
for symbol in "${symbols[@]}"; do
    cycles=1
    if [[ "$symbol" == CJCJ_MRT_InstanceNew ]]; then
        cycles=100
    fi
    executable="$OUT/$symbol"
    clang -std=gnu11 -O2 -fno-optimize-sibling-calls \
        -DPROBE_SYMBOL="\"$symbol\"" -DPROBE_CYCLES="$cycles" \
        -I"$ROOT/contract" -I"$RUNTIME_ROOT/src" \
        "$ROOT/test/contract/instance/instance_contract_probe.c" \
        -ldl -o "$executable"
    LD_LIBRARY_PATH="$BOUNDS:$CANGJIE_HOME/third_party/llvm/lib:${LD_LIBRARY_PATH:-}" \
        timeout 90s "$executable" "$HYBRID"
    rm -f "$executable"
done

RUNTIME_ROOT="$RUNTIME_ROOT" CANGJIE_HOME="$CANGJIE_HOME" \
    OUT="$OUT/official-gnu" bash "$ROOT/test/contract/instance/run_official_control.sh"

SELFHOST_CJC="${SELFHOST_CJC:-${CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}}" \
    CANGJIE_HOME="$CANGJIE_HOME" RUNTIME_ROOT="$RUNTIME_ROOT" HYBRID="$HYBRID" \
    MODE=s4 CYCLES=1 TIMEOUT=30s OUT="$OUT/managed-s4" \
    bash "$ROOT/test/contract/instance/run_managed_contract.sh"

SELFHOST_CJC="${SELFHOST_CJC:-${CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}}" \
    CANGJIE_HOME="$CANGJIE_HOME" RUNTIME_ROOT="$RUNTIME_ROOT" HYBRID="$HYBRID" \
    LOADER_RUNTIME_DIR="$BOUNDS" EXPECT_FAIL_STAGE=runtime_image_count \
    MODE=s4 CYCLES=1 TIMEOUT=30s OUT="$OUT/managed-negative-second-image" \
    bash "$ROOT/test/contract/instance/run_managed_contract.sh"

SELFHOST_CJC="${SELFHOST_CJC:-${CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}}" \
    CANGJIE_HOME="$CANGJIE_HOME" RUNTIME_ROOT="$RUNTIME_ROOT" HYBRID="$HYBRID" \
    CJCJ_CONTRACT_NEGATIVE_SYMBOL=InitCJRuntime EXPECT_FAIL_STAGE=runtime_symbol_image \
    MODE=s4 CYCLES=1 TIMEOUT=30s OUT="$OUT/managed-negative-symbol-image" \
    bash "$ROOT/test/contract/instance/run_managed_contract.sh"

SELFHOST_CJC="${SELFHOST_CJC:-${CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}}" \
    CANGJIE_HOME="$CANGJIE_HOME" RUNTIME_ROOT="$RUNTIME_ROOT" HYBRID="$HYBRID" \
    CJCJ_CONTRACT_INJECT_MISSING_DRIVER=1 EXPECT_FAIL_STAGE=driver_live_before_submit \
    MODE=s4 CYCLES=1 TIMEOUT=30s OUT="$OUT/managed-negative-driver" \
    bash "$ROOT/test/contract/instance/run_managed_contract.sh"

SELFHOST_CJC="${SELFHOST_CJC:-${CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}}" \
    CANGJIE_HOME="$CANGJIE_HOME" RUNTIME_ROOT="$RUNTIME_ROOT" HYBRID="$HYBRID" \
    MODE=s4 CYCLES=100 TIMEOUT=120s OUT="$OUT/managed-s4-100" \
    bash "$ROOT/test/contract/instance/run_managed_contract.sh"

SELFHOST_CJC="${SELFHOST_CJC:-${CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}}" \
    CANGJIE_HOME="$CANGJIE_HOME" RUNTIME_ROOT="$RUNTIME_ROOT" \
    MODE=official CYCLES=1 TIMEOUT=30s OUT="$OUT/managed-official" \
    bash "$ROOT/test/contract/instance/run_managed_contract.sh"

printf 'INSTANCE_CONTRACT_DISK_AFTER '
df -Pk "$ROOT" | tail -n 1
