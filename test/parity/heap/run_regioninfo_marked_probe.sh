#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH"
export cjHeapSize=${cjHeapSize:-24GB}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_regioninfo_marked.XXXXXX")
trap 'find "$TMP" -depth -delete' EXIT

CJTHREAD_INCLUDE_ARGS=()
while IFS= read -r include_dir; do CJTHREAD_INCLUDE_ARGS+=("-I$include_dir"); done < <(find "$RUNTIME_ROOT/src/CJThread/src" -type d)
CPP_FLAGS=(-std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/output/temp/include" -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" "${CJTHREAD_INCLUDE_ARGS[@]}")
g++ "${CPP_FLAGS[@]}" -fPIC -c "$ROOT/test/parity/heap/regioninfo_marked_bridge.cpp" -o "$TMP/RegionInfoMarkedBridge.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/Atomic.cpp" -o "$TMP/Atomic.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$TMP/Futex.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/SpinLock.cpp" -o "$TMP/SpinLock.o"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/os/Linux/PagePoolMutex.cpp" -o "$TMP/PagePoolMutex.o"

for pkg in rt.base rt.sync rt.gc; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib --int-overflow wrapping -Woff unused \
        --import-path "$TMP" --output-dir "$TMP" -o "lib$pkg.a"
done
cp -a "$ROOT/src/rt.heap.allocator" "$TMP/rt.heap.allocator.probe"
cp "$ROOT/test/parity/heap/regioninfo_marked_probe.cj" "$TMP/rt.heap.allocator.probe/Probe.cj"
"$SELFHOST_CJC" --package "$TMP/rt.heap.allocator.probe" --import-path "$TMP" --int-overflow wrapping -Woff unused \
    "$TMP/librt.gc.a" "$TMP/librt.sync.a" "$TMP/librt.base.a" "$TMP/Atomic.o" "$TMP/Futex.o" \
    "$TMP/Panic.o" "$TMP/SpinLock.o" "$TMP/PagePoolMutex.o" "$TMP/RegionInfoMarkedBridge.o" \
    -L"$CPP_RUNTIME_LIB" --link-option=-lcangjie-runtime --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/probe"
"$TMP/probe" | tee "$TMP/transcript.txt"
[[ $(grep -c '^REGIONINFO_MARKED ' "$TMP/transcript.txt") -eq 6 ]]
echo "REGIONINFO_MARKED_PARITY cases=6 sha256=$(sha256sum "$TMP/transcript.txt" | awk '{print $1}') status=PASS"
