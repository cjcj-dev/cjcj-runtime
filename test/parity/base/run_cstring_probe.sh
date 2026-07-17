#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_cstring_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

(
    cd "$TMP"
    "$SELFHOST_CJC" --package "$ROOT/src/rt.base" --output-type=staticlib \
        --int-overflow wrapping --import-path "$TMP" --output-dir "$TMP" -o librt.base.a
    "$SELFHOST_CJC" --package "$ROOT/src/rt.cstring" --output-type=staticlib \
        --int-overflow wrapping --import-path "$TMP" --output-dir "$TMP" -o librt.cstring.a
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o Panic.o
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o Atomic.o
    "$SELFHOST_CJC" "$ROOT/test/parity/base/cstring_probe.cj" \
        --import-path "$TMP" --int-overflow wrapping \
        "$TMP/librt.cstring.a" "$TMP/librt.base.a" "$TMP/Panic.o" "$TMP/Atomic.o" \
        --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/cstring_probe"
)

OUTPUT=$("$TMP/cstring_probe")
echo "$OUTPUT"
case "$OUTPUT" in
    *"CSTRING_PROBE PASS members=4 branches=nonempty,null,spaces"*)
        echo "run_cstring_probe: PASS"
        ;;
    *)
        echo "run_cstring_probe: FAIL (no PASS marker)" >&2
        exit 1
        ;;
esac
