#!/usr/bin/env bash
# Builds rt.base with the selfhost cjcj compiler and runs the deterministic RwLock state probe.
# Prints RWLOCK_PROBE PASS on success.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-8GB}

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_rwlock_probe.XXXXXX")
OUT="$IMP/rwlock_probe"
trap 'rm -rf "$IMP"' EXIT

(
    cd "$IMP"
    "$SELFHOST_CJC" --package "$ROOT/src/rt.base" --output-type=staticlib \
        --int-overflow wrapping --import-path "$IMP" --output-dir "$IMP" -o librt.base.a

    # rt0 Linux Layer0 bridges: Panic.cpp terminates RTLOG_FATAL; Atomic.cpp provides
    # inline Int32 atomics without changing RwLock's four-byte value layout.
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o Panic.o
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o Atomic.o

    "$SELFHOST_CJC" "$ROOT/test/parity/base/rwlock_probe.cj" \
        --import-path "$IMP" --int-overflow wrapping \
        "$IMP/librt.base.a" "$IMP/Panic.o" "$IMP/Atomic.o" \
        --link-option=-lstdc++ --link-option=-lgcc_s -o "$OUT"
)

OUTPUT=$("$OUT")
echo "$OUTPUT"
case "$OUTPUT" in
    *"RWLOCK_PROBE PASS"*) echo "run_rwlock_probe: PASS" ;;
    *) echo "run_rwlock_probe: FAIL (no PASS marker)" >&2; exit 1 ;;
esac
