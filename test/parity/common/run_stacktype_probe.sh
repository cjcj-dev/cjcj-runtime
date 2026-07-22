#!/usr/bin/env bash
# Common/StackType.h:25-73,83-98 and Common/TypeDef.h:36-40 full executable byte parity.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
ORACLE_ROOT=/root/cj_build/cangjie_runtime/runtime
export PATH=/root/.cjv/bin:$PATH
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

for pkg in rt.base rt.sync rt.heap.allocator rt.common; do
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping --import-path "$TMP" --output-dir "$TMP" -o "lib$pkg.a")
done

# Existing genuine rt.common package-closure Layer0 dependencies; StackType itself adds none.
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/PagePoolMutex.cpp" -o "$TMP/PagePoolMutex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/SpinLock.cpp" -o "$TMP/SpinLock.o"
NATIVE_INCLUDES=(-I"$ORACLE_ROOT/include")
while IFS= read -r directory; do NATIVE_INCLUDES+=(-I"$directory"); done < <(find "$ORACLE_ROOT/src" -type d)
NATIVE_FLAGS=(-std=c++17 -O2 -pthread -DMRT_USE_CJTHREAD_RENAME
    -I"$ORACLE_ROOT/output/temp/include"
    -I"$ORACLE_ROOT/third_party/third_party_bounds_checking_function/include"
    "${NATIVE_INCLUDES[@]}")
g++ "${NATIVE_FLAGS[@]}" -fPIC -c "$ROOT/rt0/AllocBufferNative.cpp" -o "$TMP/AllocBufferNative.o"
g++ "${NATIVE_FLAGS[@]}" -fPIC -c "$ROOT/rt0/ScopedSaferegion.cpp" -o "$TMP/ScopedSaferegion.o"

(cd "$TMP" && "$SELFHOST_CJC" "$ROOT/test/parity/common/stacktype_probe.cj" \
    --import-path "$TMP" --int-overflow wrapping \
    "$TMP/librt.common.a" "$TMP/librt.heap.allocator.a" "$TMP/librt.sync.a" \
    "$TMP/librt.base.a" "$TMP/Panic.o" "$TMP/Atomic.o" \
    "$TMP/PagePoolMutex.o" "$TMP/SpinLock.o" "$TMP/AllocBufferNative.o" \
    "$TMP/ScopedSaferegion.o" --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread \
    -o "$TMP/stacktype_probe")

"$TMP/stacktype_ref" > "$TMP/cpp.records"
"$TMP/stacktype_probe" > "$TMP/cangjie.records"
cmp "$TMP/cpp.records" "$TMP/cangjie.records"
cat "$TMP/cpp.records"
echo "STACKTYPE_PROBE PASS records=29 byte_structs=4"
