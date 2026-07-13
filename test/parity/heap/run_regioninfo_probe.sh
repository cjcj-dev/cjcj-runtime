#!/usr/bin/env bash
# Builds the C++ layout oracle and the selfhost rt.base -> rt.sync ->
# rt.heap.allocator chain, asserts every UnitMetadata offset, and runs RegionInfo.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RT_LIB="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$RT_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_regioninfo_probe.XXXXXX")
OUT="$IMP/regioninfo_probe"
REF="$IMP/regioninfo_layout_ref"
STUB_OUT="$IMP/regioninfo_stub_link_probe"
ABORT_OUT="$IMP/regioninfo_abort_probe"
PROBE_SRC="$IMP/rt.heap.allocator.probe"
trap 'rm -rf "$IMP"' EXIT

g++ -std=c++14 -O2 "$ROOT/test/parity/heap/regioninfo_layout_ref.cpp" -o "$REF"
CPP_LAYOUT=$($REF)

for pkg in rt.base rt.sync rt.heap.allocator; do
    "$SELFHOST_CJC" --package "$ROOT/src/$pkg" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$IMP" --output-dir "$IMP" -o "lib$pkg.a"
done

g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Futex.cpp" -o "$IMP/Futex.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$IMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$IMP/Atomic.o"

# Compile the deferred interface probe in the owning package so CPointer<RegionInfo>
# extension methods remain receiver-faithful. The selfhost CJO importer does not
# re-export extensions of core CPointer to a standalone package.
STUB_SRC="$IMP/rt.heap.allocator.stubcheck"
cp -a "$ROOT/src/rt.heap.allocator" "$STUB_SRC"
cat > "$STUB_SRC/RegionInfoStubProbe.cj" <<'EOF'
package rt.heap.allocator

import rt.base.REPORT

foreign { func getpid(): Int32 }

func LinkDeferredStubs(runtimeFalse: Bool): Unit {
    var regionValue = RegionInfo()
    let region = unsafe { CPointer<RegionInfo>(inout regionValue) }
    let opaque = CPointer<Unit>()
    if (runtimeFalse) {
        let _ = region.CompareExchangeRouteState(NORMAL, ROUTING)
        let _ = region.GetRouteState()
        region.SetRouteState(NORMAL)
        let _ = region.IsCompacted()
        let _ = region.IsRoutingState()
        let _ = region.TryLockRouting(NORMAL)
        let _ = region.GetPreLiveBytesInGhostRegion(0)
        let _ = region.GetLiveInfo()
        let _ = region.GetOrAllocLiveInfo()
        let _ = region.GetMarkBitmap()
        let _ = region.GetOrAllocMarkBitmap()
        let _ = region.GetResurrectBitmap()
        let _ = region.GetOrAllocResurrectBitmap()
        let _ = region.GetEnqueueBitmap()
        let _ = region.GetOrAllocEnqueueBitmap()
        region.ResetMarkBit()
        let _ = region.MarkObject(opaque)
        let _ = region.MarkObject(opaque, 1)
        let _ = region.ResurrectObject(opaque, 0)
        let _ = region.EnqueueObject(opaque, 0)
        let _ = region.IsResurrectedObject(opaque)
        let _ = region.IsResurrectedObject(UIntNative(0))
        let _ = region.IsMarkedObject(opaque)
        let _ = region.IsMarkedObject(UIntNative(0))
        let _ = region.IsSurvivedObject(0)
        let _ = region.IsEnqueuedObject(0)
        let _ = RegionInfo.InGhostFromRegion(opaque)
        let _ = RegionInfo.GetGhostFromRegionAt(0)
        let _ = region.GetGhostRegionSize()
        let _ = region.GetGhostRegionUnitCount()
        region.DumpRegionInfo(REPORT)
        let _ = region.GetTypeName()
        region.VisitAllObjects(opaque)
        let _ = region.VisitLiveObjectsUntilFalse(opaque)
        region.SetRouteInfo(0)
        let _ = region.GetRoute(opaque)
        region.PrepareForwardableRegion()
        region.ClearGhostRegionBit()
        region.DispelGhostFromRegion()
        let _ = region.IsGhostFromRegion()
        region.CheckAndClearLiveInfo(opaque)
        region.ClearLiveInfo()
    }
}

main(): Int64 {
    LinkDeferredStubs(unsafe { getpid() } < 0)
    return 0
}
EOF

"$SELFHOST_CJC" --package "$STUB_SRC" --import-path "$IMP" --int-overflow wrapping -Woff unused \
    "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$STUB_OUT"
"$STUB_OUT"

ABORT_SRC="$IMP/rt.heap.allocator.abortcheck"
cp -a "$ROOT/src/rt.heap.allocator" "$ABORT_SRC"
cat > "$ABORT_SRC/RegionInfoAbortProbe.cj" <<'EOF'
package rt.heap.allocator

main(): Int64 {
    var regionValue = RegionInfo()
    let region = unsafe { CPointer<RegionInfo>(inout regionValue) }
    let _ = region.MarkObject(CPointer<Unit>())
    return 99
}
EOF

"$SELFHOST_CJC" --package "$ABORT_SRC" --import-path "$IMP" --int-overflow wrapping -Woff unused \
    "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$ABORT_OUT"
set +e
ABORT_OUTPUT=$($ABORT_OUT 2>&1)
ABORT_RC=$?
set -e
if [[ $ABORT_RC -eq 0 ]]; then
    echo "REGIONINFO_DEFERRED_ABORT FAIL (zero exit)" >&2
    exit 1
fi
if ! grep -Fxq 'RegionInfo::MarkObject not yet ported (Collector-deferred)' <<< "$ABORT_OUTPUT"; then
    echo "REGIONINFO_DEFERRED_ABORT FAIL (message mismatch)" >&2
    printf '%s\n' "$ABORT_OUTPUT" >&2
    exit 1
fi
echo "REGIONINFO_DEFERRED_ABORT PASS rc=$ABORT_RC message=RegionInfo::MarkObject not yet ported (Collector-deferred)"

cp -a "$ROOT/src/rt.heap.allocator" "$PROBE_SRC"
cp "$ROOT/test/parity/heap/regioninfo_probe.cj" "$PROBE_SRC/RegionInfoProbe.cj"
"$SELFHOST_CJC" --package "$PROBE_SRC" --import-path "$IMP" --int-overflow wrapping -Woff unused \
    "$IMP/librt.sync.a" "$IMP/librt.base.a" \
    "$IMP/Futex.o" "$IMP/Panic.o" "$IMP/Atomic.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$OUT"

CJ_OUTPUT=$($OUT)
CJ_LAYOUT=$(printf '%s\n' "$CJ_OUTPUT" | grep '^REGIONINFO_LAYOUT ')
printf '%s\n' "$CPP_LAYOUT"
printf '%s\n' "$CJ_OUTPUT"

if [[ "$CJ_LAYOUT" != "$CPP_LAYOUT" ]]; then
    echo "REGIONINFO_LAYOUT ASSERT FAIL" >&2
    echo "C++: $CPP_LAYOUT" >&2
    echo "CJ : $CJ_LAYOUT" >&2
    exit 1
fi
echo "REGIONINFO_LAYOUT ASSERT PASS $CJ_LAYOUT"

case "$CJ_OUTPUT" in
    *"REGIONINFO_PROBE PASS"*) echo "run_regioninfo_probe: PASS" ;;
    *) echo "run_regioninfo_probe: FAIL (no PASS marker)" >&2; exit 1 ;;
esac
