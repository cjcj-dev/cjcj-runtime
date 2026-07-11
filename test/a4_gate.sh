#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-"$ROOT/out/a4-gate"}
SELFHOST=${SELFHOST:-/root/cj_build/cjcj}
CJC=${CJC:-"$SELFHOST/target/release/bin/cjcj::cjc"}
CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}
ORACLE=${ORACLE:-"$RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"}
HYBRID=${HYBRID:-"$ROOT/out/gate/hybrid/libcangjie-runtime.so"}
RTLIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
export CANGJIE_HOME
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$RTLIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

rm -rf "$OUT"
mkdir -p "$OUT/compile" "$OUT/object" "$OUT/driver"

if [ ! -f "$HYBRID" ]; then
    SKIP_DIFFTEST=1 OUT="$ROOT/out/gate" bash "$ROOT/test/gate.sh"
fi

bash "$SELFHOST/scripts/w4annot_gate.sh" "$CJC" | tee "$OUT/w4annot.log"
grep -Fq 'W4ANNOT: PASS=11 FAIL=0' "$OUT/w4annot.log"

python3 "$ROOT/tools/a4_gate.py" inventory \
    --source "$ROOT/test/a4_gate/noheap_tls_probe.cj" --output "$OUT/noheap-roots.tsv" \
    | tee "$OUT/inventory.log"
python3 "$ROOT/tools/a4_gate.py" inventory --allow-empty \
    --source "$ROOT/src" --output "$OUT/production-noheap-roots.tsv" \
    | tee "$OUT/production-inventory.log"

(
    cd "$OUT/compile"
    "$CJC" "$ROOT/test/a4_gate/noheap_tls_probe.cj" --output-type=staticlib -O2 \
        --int-overflow wrapping -o "$OUT/liba4_gate.a"
)
(
    cd "$OUT/object"
    llvm-ar x "$OUT/liba4_gate.a"
)
PROBE_OBJECT=$(find "$OUT/object" -maxdepth 1 -type f -name '*.o' -print -quit)
test -n "$PROBE_OBJECT"

python3 "$ROOT/tools/a4_gate.py" inspect-object \
    --manifest "$OUT/noheap-roots.tsv" --image "$PROBE_OBJECT" | tee "$OUT/static.log"
python3 "$ROOT/tools/a4_gate.py" inspect-runtime --image "$ORACLE" | tee "$OUT/oracle-runtime.log"
python3 "$ROOT/tools/a4_gate.py" inspect-runtime --image "$HYBRID" | tee "$OUT/hybrid-runtime.log"

(
    cd "$OUT/driver"
    "$CJC" "$ROOT/test/a4_gate/probe_driver.cj" --set-runtime-rpath \
        --link-option "$PROBE_OBJECT" -o "$OUT/probe"
)

for label in oracle hybrid; do
    runtime=$ORACLE
    if [ "$label" = hybrid ]; then runtime=$HYBRID; fi
    LD_PRELOAD="$runtime" "$OUT/probe" | tee "$OUT/$label-probe.log"
    gdb -q -batch -ex "set environment LD_PRELOAD=$runtime" \
        -x "$ROOT/test/a4_gate/scoped_breakpoints.gdb" --args "$OUT/probe" \
        | tee "$OUT/$label-dynamic.log"
    grep -Eq 'DYNAMIC_SUMMARY roots=2 malloc_hits=0 mcc_new_hits=0 tls_hits=[1-9][0-9]*' "$OUT/$label-dynamic.log"
done

oracle_dynamic=$(grep -Eo 'DYNAMIC_SUMMARY .*' "$OUT/oracle-dynamic.log" | tail -1)
hybrid_dynamic=$(grep -Eo 'DYNAMIC_SUMMARY .*' "$OUT/hybrid-dynamic.log" | tail -1)
test "$oracle_dynamic" = "$hybrid_dynamic"
production_roots=$(($(wc -l < "$OUT/production-noheap-roots.tsv") - 1))
printf 'A4 HARNESS PASS probe_annotations=2 production_annotations=%s compiler_w4=11/11 static_managed_refs=0 static_tls_refs=1 %s\n' \
    "$production_roots" "$oracle_dynamic"
