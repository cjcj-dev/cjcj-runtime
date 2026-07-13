#!/usr/bin/env bash
# Builds the rt.base -> rt.sync -> rt.heap.allocator chain with the selfhost cjcj
# compiler and runs the LocalDeque parity probe, which exercises RTAllocatorT
# (bump allocation + intrusive free-list reuse), SingleUseDeque (queue front +
# stack top over a MemMap), and LocalDeque (inline 512-slot array spilling into a
# SingleUseDeque). Prints LOCALDEQUE_PROBE PASS on success.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-8GB}

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_localdeque_probe.XXXXXX")
OUT="$IMP/localdeque_probe"
trap 'rm -rf "$IMP"' EXIT

for pkg in rt.base rt.sync rt.heap.allocator; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping --import-path "$IMP" --output-dir "$IMP" -o "lib$pkg.a"
done

g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$IMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$IMP/Panic.o"

"$SELFHOST_CJC" "$ROOT/test/parity/heap/localdeque_probe.cj" \
    --import-path "$IMP" --int-overflow wrapping \
    "$IMP/librt.heap.allocator.a" "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$OUT"

OUTPUT=$("$OUT")
echo "$OUTPUT"
case "$OUTPUT" in
    *"LOCALDEQUE_PROBE PASS"*) echo "run_localdeque_probe: PASS" ;;
    *) echo "run_localdeque_probe: FAIL (no PASS marker)" >&2; exit 1 ;;
esac
