#!/usr/bin/env bash
# Common/StackType.h:25-73,83-98 and Common/TypeDef.h:36-40 full executable byte parity.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
ORACLE_ROOT=/root/cj_build/cangjie_runtime/runtime
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export PATH=/root/.cjv/bin:$PATH
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "stacktype parity execution requires Linux x86_64" >&2
    exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_stacktype_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

g++ -std=c++14 -O2 -I"$ORACLE_ROOT/src" \
    -I"$ORACLE_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/common/stacktype_ref.cpp" -o "$TMP/stacktype_ref"

for pkg in rt.base rt.common; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping --import-path "$TMP" --output-dir "$TMP" -o "lib$pkg.a"
done

# Existing genuine rt.common -> rt.base/Layer0 link dependencies; StackType itself adds none.
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"

"$SELFHOST_CJC" "$ROOT/test/parity/common/stacktype_probe.cj" \
    --import-path "$TMP" --int-overflow wrapping \
    "$TMP/librt.common.a" "$TMP/librt.base.a" "$TMP/Panic.o" "$TMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/stacktype_probe"

"$TMP/stacktype_ref" > "$TMP/cpp.records"
"$TMP/stacktype_probe" > "$TMP/cangjie.records"
cmp "$TMP/cpp.records" "$TMP/cangjie.records"
cat "$TMP/cpp.records"
echo "STACKTYPE_PROBE PASS records=29 byte_structs=4"
