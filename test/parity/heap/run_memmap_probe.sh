#!/usr/bin/env bash
# Builds the rt.base -> rt.sync -> rt.heap.allocator chain with the selfhost cjcj
# compiler, links the MemMap parity probe against the rt0 Linux Layer0 bridges, and
# runs it. The probe reserves a region through MemMap.MapMemory, writes/reads the
# first and last mapped bytes (proving mmap + mprotect made the range accessible),
# then MemMap.DestroyMemMap unmaps it. Prints MEMMAP_PROBE PASS on success.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
# CANGJIE_HOME supplies the std modules and llvm libs the selfhost compiler loads.
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-8GB}

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_memmap_probe.XXXXXX")
OUT="$IMP/memmap_probe"
trap 'rm -rf "$IMP"' EXIT

for pkg in rt.base rt.sync rt.heap.allocator; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping --import-path "$IMP" --output-dir "$IMP" -o "lib$pkg.a"
done

# rt0 Linux Layer0 bridges: Futex.cpp (_ZN12MapleRuntime5FutexEPVKiii, pulled in with
# rt.sync), Panic.cpp (RtFatal), and Atomic.cpp (inline atomics in the allocator package).
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$IMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$IMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$IMP/Atomic.o"

"$SELFHOST_CJC" "$ROOT/test/parity/heap/memmap_probe.cj" \
    --import-path "$IMP" --int-overflow wrapping \
    "$IMP/librt.heap.allocator.a" "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$OUT"

OUTPUT=$("$OUT")
echo "$OUTPUT"
case "$OUTPUT" in
    *"MEMMAP_PROBE PASS"*) echo "run_memmap_probe: PASS" ;;
    *) echo "run_memmap_probe: FAIL (no PASS marker)" >&2; exit 1 ;;
esac
