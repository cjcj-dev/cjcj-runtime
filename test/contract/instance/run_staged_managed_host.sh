#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 3 ]]; then
    printf 'usage: %s SELFHOST_CJC HYBRID STAGE [CJC_ARGS...]\n' "$0" >&2
    exit 2
fi

SELFHOST_CJC=$1
HYBRID=$2
STAGE=$3
shift 3

test -x "$SELFHOST_CJC"
test -f "$HYBRID"

STAGED_CJC="$STAGE/bin/$(basename "$SELFHOST_CJC")"
STAGED_RUNTIME_DIR="$STAGE/runtime/lib/linux_x86_64_cjnative"
STAGED_RUNTIME="$STAGED_RUNTIME_DIR/libcangjie-runtime.so"

rm -rf "$STAGE"
mkdir -p "$(dirname "$STAGED_CJC")" "$STAGED_RUNTIME_DIR"
cp "$SELFHOST_CJC" "$STAGED_CJC"
cp "$HYBRID" "$STAGED_RUNTIME"

printf 'MANAGED_HOST_STAGE compiler=%s runtime=%s\n' "$STAGED_CJC" "$STAGED_RUNTIME"
sha256sum "$STAGED_CJC" "$STAGED_RUNTIME"

if [[ "$#" -eq 0 ]]; then
    exit 0
fi

CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
RTLIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
LD_LIBRARY_PATH="$STAGED_RUNTIME_DIR:$CANGJIE_HOME/third_party/llvm/lib:$RTLIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}" \
    "$STAGED_CJC" "$@"
