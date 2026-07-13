#!/usr/bin/env bash
# Builds rt.base -> rt.common with the selfhost cjcj compiler and runs the RunType parity
# probe, which initialises the run (size-class) config map and verifies every config size
# maps to its own index, that 8-aligned inexact sizes round up, and the boundary invariants.
# Prints RUNTYPE_PROBE PASS on success.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-8GB}

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_runtype_probe.XXXXXX")
OUT="$IMP/runtype_probe"
trap 'rm -rf "$IMP"' EXIT

for pkg in rt.base rt.common; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping --import-path "$IMP" --output-dir "$IMP" -o "lib$pkg.a"
done

# rt0 Linux Layer0 bridge: Panic.cpp (RtFatal, the RTLOG_FATAL abort terminator used by rt.base LOG).
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$IMP/Panic.o"

"$SELFHOST_CJC" "$ROOT/test/parity/common/runtype_probe.cj" \
    --import-path "$IMP" --int-overflow wrapping \
    "$IMP/librt.common.a" "$IMP/librt.base.a" "$IMP/Panic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$OUT"

OUTPUT=$("$OUT")
echo "$OUTPUT"
case "$OUTPUT" in
    *"RUNTYPE_PROBE PASS"*) echo "run_runtype_probe: PASS" ;;
    *) echo "run_runtype_probe: FAIL (no PASS marker)" >&2; exit 1 ;;
esac
