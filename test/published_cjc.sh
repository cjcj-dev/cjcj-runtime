#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/test/compiler_identity.sh"

# A tested runtime is injected only into produced programs, never into the
# compiler process that creates them.
exec env -u LD_PRELOAD "$SELFHOST_CJC" "$@"
