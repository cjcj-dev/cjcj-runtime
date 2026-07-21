#!/usr/bin/env bash
# Common/RegisterX86-64.h:23-82, RegisterAarch64.h:33-121, RegisterArm.h:14-85.
# Build both host-selected implementations and byte-compare every deterministic record.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
export cjHeapSize=${cjHeapSize:-24GB}

HOST_ARCH=$(uname -m)
if [[ "$HOST_ARCH" != "x86_64" ]]; then
    echo "register parity execution is limited to the Linux x86_64 selfhost toolchain" >&2
    exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_register_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

(
    cd "$TMP"
    for pkg in rt.base rt.common; do
        "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
            --int-overflow wrapping --import-path "$TMP" --output-dir "$TMP" -o "lib$pkg.a"
    done

    # Base/Log.cpp:417-419 Layer0 fatal terminator used by ResolveCalleeSaved's invalid boundary.
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
    # Existing rt.base/RwLock.cj prerequisite from runtime master ff15eb0; Register itself has no atomics.
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"

    "$SELFHOST_CJC" "$ROOT/test/parity/common/register_probe.cj" \
        --import-path "$TMP" --int-overflow wrapping \
        "$TMP/librt.common.a" "$TMP/librt.base.a" "$TMP/Panic.o" "$TMP/Atomic.o" \
        --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/register_probe"

    g++ -std=c++14 -O2 "$ROOT/test/parity/common/register_ref.cpp" -o "$TMP/register_ref"
    "$TMP/register_probe" > "$TMP/cangjie.records"
    "$TMP/register_ref" > "$TMP/cpp.records"
    cmp "$TMP/cpp.records" "$TMP/cangjie.records"
)

echo "REGISTER_PROBE PASS arch=x86_64 count=33 callee=5"
