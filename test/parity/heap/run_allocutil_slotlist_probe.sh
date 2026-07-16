#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
SELFHOST_RUNTIME=/root/cj_build/cjcj/target/release/runtime/lib/linux_x86_64_cjnative
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_allocutil_slotlist.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
CPP_OUT="$TMP/cpp.transcript"
CJ_OUT="$TMP/cj.transcript"
PKG="$TMP/rt.heap.allocator"
mkdir -p "$PKG"

g++ -std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME \
    -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/output/temp/include" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/heap/allocutil_slotlist_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -L"$SELFHOST_RUNTIME" -lsecurec -o "$TMP/cpp_probe"
"$TMP/cpp_probe" > "$CPP_OUT"

cp "$ROOT/src/rt.heap.allocator/AllocUtil.cj" "$PKG/"
cp "$ROOT/src/rt.heap.allocator/RouteInfo.cj" "$PKG/"
cp "$ROOT/src/rt.heap.allocator/SlotList.cj" "$PKG/"
cp "$ROOT/test/parity/heap/allocutil_slotlist_foreign_probe.cj" "$PKG/ForeignProbe.cj"
cp "$ROOT/test/parity/heap/allocutil_slotlist_probe.cj" "$PKG/Probe.cj"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/test/parity/heap/allocutil_slotlist_bridge.cpp" \
    -o "$TMP/bridge.o"
(cd "$TMP" && "$SELFHOST_CJC" --package "$PKG" --int-overflow wrapping -Woff unused \
    "$TMP/bridge.o" -L"$SELFHOST_RUNTIME" -lsecurec --link-option=-lstdc++ -o "$TMP/cj_probe")
"$TMP/cj_probe" > "$CJ_OUT"

diff -u "$CPP_OUT" "$CJ_OUT"
cat "$CJ_OUT"
echo "ALLOCUTIL_SLOTLIST_PARITY lines=$(wc -l < "$CJ_OUT") mismatches=0 status=PASS"
echo "ALLOCUTIL_SLOTLIST_COMPILER path=$SELFHOST_CJC status=PASS"
