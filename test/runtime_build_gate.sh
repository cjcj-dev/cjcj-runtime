#!/usr/bin/env bash
# Fail-closed build gate for every production package below src/. The repository
# root is intentionally not a Cangjie package, so bare cjpm build is not evidence.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/test/compiler_identity.sh"
MODE=${1:-full}
export cjHeapSize=24GB

fail() { echo "runtime_build_gate: FAIL $*" >&2; exit 1; }
[[ $MODE == full || $MODE == delta ]] || fail "mode must be full or delta"

EXPECTED=(
    rt.base rt.sync rt.heap.allocator rt.common rt.demangle rt.stackmap rt.abi
    rt.exception rt.gc rt.objectmodel rt.runtime rt.sched rt.gc.forwarddata
)
mapfile -t DISCOVERED < <(find "$ROOT/src" -mindepth 1 -maxdepth 1 -type d \
    -exec sh -c 'find "$1" -maxdepth 1 -type f -name "*.cj" -print -quit | grep -q .' _ {} \; \
    -printf '%f\n' | sort)
mapfile -t EXPECTED_SORTED < <(printf '%s\n' "${EXPECTED[@]}" | sort)
[[ ${#DISCOVERED[@]} -eq 13 ]] || fail "package count expected=13 actual=${#DISCOVERED[@]}"
[[ ${DISCOVERED[*]} == "${EXPECTED_SORTED[*]}" ]] || {
    printf 'expected=%s\nactual=%s\n' "${EXPECTED_SORTED[*]}" "${DISCOVERED[*]}" >&2
    fail "package inventory drift"
}
SOURCE_COUNT=$(find "$ROOT/src" -mindepth 2 -maxdepth 2 -type f -name '*.cj' | wc -l)
[[ $SOURCE_COUNT -eq 58 ]] || fail "source count expected=58 actual=$SOURCE_COUNT"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/runtime_build_gate.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
for package in "${EXPECTED[@]}"; do
    "$SELFHOST_CJC" --package "$ROOT/src/$package" --output-type=staticlib -O2 \
        --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" \
        -o "lib$package.a"
    archive="$TMP/lib$package.a"
    [[ -s $archive ]] || fail "empty or missing archive package=$package"
    echo "RUNTIME_PACKAGE_BUILD package=$package sources=$(find "$ROOT/src/$package" -maxdepth 1 -type f -name '*.cj' | wc -l) archive_size=$(stat -c %s "$archive") status=PASS"
done

fallback=none
[[ $MODE == delta ]] && fallback=full-no-runtime-manifest
echo "RUNTIME_BUILD_GATE mode=$MODE fallback=$fallback packages=${#DISCOVERED[@]} sources=$SOURCE_COUNT empty_root=REJECTED compiler_source=$COMPILER_SOURCE status=PASS"
