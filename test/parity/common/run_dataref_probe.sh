#!/usr/bin/env bash
# Common/Dataref.h:16-50. Build the actual C++ oracle and byte-compare its records with Cangjie.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
REFERENCE_ROOT=/root/cj_build/cangjie_runtime/runtime/src
REFERENCE_SECUREC=/root/cj_build/cangjie_runtime/runtime/third_party/third_party_bounds_checking_function/include
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    echo "dataref parity execution requires Linux x86_64" >&2
    exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_dataref_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

(
    cd "$TMP"
    for pkg in rt.base rt.common; do
        "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
            --int-overflow wrapping --import-path "$TMP" --output-dir "$TMP" -o "lib$pkg.a"
    done

    # Existing rt.common leaves reference these Layer0 bridges; Dataref itself adds no bridge.
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"

    "$SELFHOST_CJC" "$ROOT/test/parity/common/dataref_probe.cj" \
        --import-path "$TMP" --int-overflow wrapping \
        "$TMP/librt.common.a" "$TMP/librt.base.a" "$TMP/Panic.o" "$TMP/Atomic.o" \
        --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/dataref_probe"

    g++ -std=c++14 -O2 -I"$REFERENCE_ROOT" -I"$REFERENCE_SECUREC" \
        "$ROOT/test/parity/common/dataref_ref.cpp" -o "$TMP/dataref_ref"

    "$TMP/dataref_probe" > "$TMP/cangjie.records"
    "$TMP/dataref_ref" > "$TMP/cpp.records"
    cmp "$TMP/cpp.records" "$TMP/cangjie.records"

    layout_record=$(head -n 1 "$TMP/cangjie.records")
    [[ "$layout_record" == \
        "DATAREF_LAYOUT d32_size=4 d32_align=4 d32_refOffset=0 d64_size=8 d64_align=8 d64_refOffset=0" ]]
    layout_t_record=$(sed -n '2p' "$TMP/cangjie.records")
    [[ "$layout_t_record" == \
        "DATAREF_LAYOUT_T d32_u64_size=4 d32_u64_align=4 d32_u64_refOffset=0 d64_u64_size=8 d64_u64_align=8 d64_u64_refOffset=0" ]]
    if grep -Eq '(null|exact)=0' "$TMP/cangjie.records"; then
        echo "dataref parity record contains a failed comparison" >&2
        exit 1
    fi
    case_count=$(grep -c '^DATAREF_CASE ' "$TMP/cangjie.records")
    [[ "$case_count" -eq 12 ]]
    echo "$layout_record"
    echo "DATAREF_PROBE PASS cases=$case_count"
)
