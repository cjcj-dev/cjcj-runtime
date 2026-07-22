#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
SELFHOST_RUNTIME=/root/cj_build/cjcj/target/release/runtime/lib/linux_x86_64_cjnative
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_allocbuffer_probe.XXXXXX")
CPP_OUT="$TMP/cpp.txt"
CJ_OUT="$TMP/cj.txt"
PKG="$TMP/rt.heap.allocator"
mkdir -p "$PKG"

CJTHREAD_INCLUDE_ARGS=()
while IFS= read -r include_dir; do
    CJTHREAD_INCLUDE_ARGS+=("-I$include_dir")
done < <(find "$RUNTIME_ROOT/src/CJThread/src" -type d)

COMMON_CXX_ARGS=(
    -std=c++14 -O2 -DMRT_USE_CJTHREAD_RENAME
    -I"$RUNTIME_ROOT/src"
    -I"$RUNTIME_ROOT/output/temp/include"
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    "${CJTHREAD_INCLUDE_ARGS[@]}"
)

g++ "${COMMON_CXX_ARGS[@]}" "$ROOT/test/parity/heap/allocbuffer_ref.cpp" \
    -L"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" \
    -Wl,-rpath,"$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" \
    -lcangjie-runtime -lpthread -ldl -o "$TMP/cpp_probe"
"$TMP/cpp_probe" > "$CPP_OUT"

for pkg in rt.base rt.sync; do
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" -o "lib$pkg.a")
done
cp -a "$ROOT/src/rt.heap.allocator/." "$PKG/"
cp "$ROOT/test/parity/heap/allocbuffer_probe.cj" "$PKG/AllocBufferProbe.cj"

g++ "${COMMON_CXX_ARGS[@]}" -fPIC -c "$ROOT/rt0/AllocBufferNative.cpp" -o "$TMP/AllocBufferNative.o"
g++ "${COMMON_CXX_ARGS[@]}" -fPIC -c "$ROOT/rt0/os/Linux/PagePoolMutex.cpp" -o "$TMP/PagePoolMutex.o"
g++ "${COMMON_CXX_ARGS[@]}" -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$TMP/Futex.o"
g++ "${COMMON_CXX_ARGS[@]}" -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ "${COMMON_CXX_ARGS[@]}" -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"
g++ "${COMMON_CXX_ARGS[@]}" -fPIC -c "$ROOT/rt0/os/Linux/SpinLock.cpp" -o "$TMP/SpinLock.o"
g++ "${COMMON_CXX_ARGS[@]}" -fPIC -c "$ROOT/test/parity/heap/allocbuffer_probe_bridge.cpp" \
    -o "$TMP/AllocBufferProbeBridge.o"

(cd "$TMP" && "$SELFHOST_CJC" --package "$PKG" --int-overflow wrapping -Woff unused \
    --import-path "$TMP" "$TMP/librt.sync.a" "$TMP/librt.base.a" \
    "$TMP/AllocBufferNative.o" "$TMP/PagePoolMutex.o" "$TMP/Futex.o" "$TMP/Panic.o" \
    "$TMP/Atomic.o" "$TMP/SpinLock.o" "$TMP/AllocBufferProbeBridge.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread -o "$TMP/cj_probe")
"$TMP/cj_probe" > "$CJ_OUT"

diff -u "$CPP_OUT" "$CJ_OUT"
cat "$CJ_OUT"
echo "ALLOC_BUFFER_TRANSCRIPT lines=$(wc -l < "$CJ_OUT") bytes=$(wc -c < "$CJ_OUT") mismatches=0 status=PASS"
echo "ALLOC_BUFFER_COMPILER path=$SELFHOST_CJC status=PASS"
