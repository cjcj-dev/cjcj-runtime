#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
IMPORT_PATH="$RUNTIME_COMPILER_ROOT"
OUT=${TMPDIR:-/tmp}/rt_sync_futex_probe_$$
trap 'rm -f "$OUT" "$OUT.o"' EXIT

g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$OUT.o"
"$SELFHOST_CJC" "$ROOT/src/rt.sync/SysCall.cj" "$ROOT/test/parity/sync/futex_probe.cj" \
    --import-path "$IMPORT_PATH" --int-overflow wrapping \
    --link-option "$OUT.o" --link-option=-lstdc++ --link-option=-lgcc_s -o "$OUT"
"$OUT"
echo "FUTEX_PROBE PASS"
