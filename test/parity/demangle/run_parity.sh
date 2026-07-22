#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
SELFHOST=${SELFHOST:-/root/cj_build/cjcj}
HYBRID=${HYBRID:-"$ROOT/out/gate/hybrid/libcangjie-runtime.so"}
BUILD=${BUILD:-"$ROOT/out/demangle-parity"}
PREFIX=${PREFIX:-_CN}

test -x "$CJC"
test -f "$HYBRID"
rm -rf "$BUILD"
mkdir -p "$BUILD"

# The native oracle aborts on some compiler-generated _CC/_CPI support names;
# _CN is its declaration-symbol domain and spans every selfhost object.
mapfile -d '' objects < <(find "$SELFHOST" -type f -name '*.o' -print0 | sort -z)
if [[ ${#objects[@]} -eq 0 ]]; then
    printf 'no selfhost objects under %s\n' "$SELFHOST" >&2
    exit 2
fi

corpus="$BUILD/symbols.txt"
for object in "${objects[@]}"; do
    nm --defined-only --format=posix "$object" | awk -v prefix="$PREFIX" \
        'index($1, prefix) == 1 { print $1 }'
done | LC_ALL=C sort -u > "$corpus"

symbol_count=$(wc -l < "$corpus")
if [[ "$symbol_count" -eq 0 ]]; then
    printf 'empty demangle corpus for prefix %s\n' "$PREFIX" >&2
    exit 2
fi

clang++ -std=c++17 -O2 -Wall -Wextra -c \
    "$ROOT/test/parity/demangle/driver_support.cpp" -o "$BUILD/driver_support.o"
(
    cd "$BUILD"
    "$CJC" "$ROOT/test/parity/demangle/cangjie_driver.cj" \
        -o "$BUILD/demangle_driver" --set-runtime-rpath --int-overflow wrapping \
        --link-option "$BUILD/driver_support.o" --link-option=-lstdc++ --link-option=-lgcc_s
)

oracle="$BUILD/oracle.bin"
candidate="$BUILD/candidate.bin"
CJRT_DEMANGLE_SYMBOLS="$corpus" "$BUILD/demangle_driver" > "$oracle"
CJRT_DEMANGLE_SYMBOLS="$corpus" LD_PRELOAD="$HYBRID" "$BUILD/demangle_driver" > "$candidate"
cmp "$oracle" "$candidate"

oracle_bytes=$(wc -c < "$oracle")
candidate_bytes=$(wc -c < "$candidate")
digest=$(sha256sum "$oracle" | awk '{print $1}')
printf 'DEMANGLE_PARITY_PREFIX=%s\n' "$PREFIX"
printf 'DEMANGLE_PARITY_OBJECTS=%s\n' "${#objects[@]}"
printf 'DEMANGLE_PARITY_SYMBOLS=%s\n' "$symbol_count"
printf 'DEMANGLE_PARITY_ORACLE_BYTES=%s\n' "$oracle_bytes"
printf 'DEMANGLE_PARITY_CANDIDATE_BYTES=%s\n' "$candidate_bytes"
printf 'DEMANGLE_PARITY_BYTE_DIFF=0\n'
printf 'DEMANGLE_PARITY_SHA256=%s\n' "$digest"
