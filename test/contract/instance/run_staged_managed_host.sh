#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"

if [[ "$#" -lt 2 ]]; then
    printf 'usage: %s HYBRID STAGE [CJC_ARGS...]\n' "$0" >&2
    exit 2
fi

HYBRID=$1
STAGE=$2
shift 2

test -x "$SELFHOST_CJC"
test -f "$HYBRID"

STAGED_CJC="$STAGE/bin/$(basename "$SELFHOST_CJC")"
STAGED_RUNTIME_DIR="$STAGE/runtime/lib/linux_x86_64_cjnative"
STAGED_RUNTIME="$STAGED_RUNTIME_DIR/libcangjie-runtime.so"

rm -rf "$STAGE"
mkdir -p "$(dirname "$STAGED_CJC")" "$STAGED_RUNTIME_DIR"
cp "$SELFHOST_CJC" "$STAGED_CJC"
cp "$HYBRID" "$STAGED_RUNTIME"
runtime_check_file_identity staged-compiler "$STAGED_CJC" "$COMPILER_SHA256" "$COMPILER_SIZE"

printf 'MANAGED_HOST_STAGE compiler=%s runtime=%s\n' "$STAGED_CJC" "$STAGED_RUNTIME"
sha256sum "$STAGED_CJC" "$STAGED_RUNTIME"

if [[ "$#" -eq 0 ]]; then
    exit 0
fi

env -u LD_PRELOAD LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$STAGED_CJC" "$@"
