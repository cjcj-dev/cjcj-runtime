#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH"
export cjHeapSize=${cjHeapSize:-24GB}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_baseobject_size.XXXXXX")
trap 'find "$TMP" -depth -delete' EXIT

CPP_FLAGS=(-std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/output/temp/include" -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include")
g++ "${CPP_FLAGS[@]}" -fPIC -c "$ROOT/test/parity/objectmodel/baseobject_size_bridge.cpp" -o "$TMP/BaseObjectSizeBridge.o"
cp -a "$ROOT/src/rt.objectmodel" "$TMP/rt.objectmodel.probe"
cp "$ROOT/test/parity/objectmodel/baseobject_size_probe.cj" "$TMP/rt.objectmodel.probe/Probe.cj"
"$SELFHOST_CJC" --package "$TMP/rt.objectmodel.probe" --int-overflow wrapping -Woff unused \
    "$TMP/BaseObjectSizeBridge.o" -L"$CPP_RUNTIME_LIB" --link-option=-lcangjie-runtime \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/probe"
"$TMP/probe" | tee "$TMP/transcript.txt"
[[ $(grep -c '^BASEOBJECT_SIZE ' "$TMP/transcript.txt") -eq 8 ]]
echo "BASEOBJECT_SIZE_PARITY cases=8 sha256=$(sha256sum "$TMP/transcript.txt" | awk '{print $1}') status=PASS"
