#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${OUT:-"$ROOT/out/official-instance-control"}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
ORACLE="$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
RTLIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"

rm -rf "$OUT"
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

clang -std=gnu11 -O2 -Wall -Wextra -Werror \
    -I"$RUNTIME_ROOT/src" \
    "$ROOT/test/contract/instance/official_subscheduler_probe.c" \
    -ldl -o "$OUT/official_subscheduler_probe"

set +e
LD_LIBRARY_PATH="$RTLIB:$CANGJIE_HOME/third_party/llvm/lib:${LD_LIBRARY_PATH:-}" \
    timeout --signal=KILL 30s "$OUT/official_subscheduler_probe" "$ORACLE" \
    2>&1 | tee "$OUT/official.log"
rc=${PIPESTATUS[0]}
set -e
printf 'OFFICIAL_GNU_CONTROL_RESULT rc=%s timeout=30s\n' "$rc"
if [[ "$rc" -ne 0 ]]; then
    exit "$rc"
fi
grep -Fq 'OFFICIAL_GNU_CONTROL PASS' "$OUT/official.log"
