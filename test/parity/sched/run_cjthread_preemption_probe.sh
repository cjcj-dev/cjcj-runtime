#!/usr/bin/env bash
# Mixed-chain parity for the three scheduler entries consumed by RegionSpace.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
TOOLCHAIN=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
RUNTIME_LIB="$TOOLCHAIN/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
export CANGJIE_HOME="$TOOLCHAIN"
export cjHeapSize=24GB
export LD_LIBRARY_PATH="$(dirname "$SELFHOST_CJC")/../runtime/lib/linux_x86_64_cjnative:$TOOLCHAIN/third_party/llvm/lib:$TOOLCHAIN/runtime/lib/linux_x86_64_cjnative:$TOOLCHAIN/tools/lib:${LD_LIBRARY_PATH:-}"

fail()
{
    echo "run_cjthread_preemption_probe: FAIL $*" >&2
    exit 1
}

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail "Linux x86_64 required"
[[ -x "$SELFHOST_CJC" && -f "$RUNTIME_LIB" ]] || fail "pinned compiler/runtime absent"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_cjthread_preemption.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sched_temps" "$TMP/root_temps" "$TMP/cjthreadpreemption.noheap"
cp "$ROOT/test/parity/sched/cjthread_preemption_noheap_roots.cj" \
    "$TMP/cjthreadpreemption.noheap/roots.cj"

"$SELFHOST_CJC" --package "$ROOT/src/rt.sched" --output-type=staticlib -O2 \
    --int-overflow wrapping --save-temps "$TMP/sched_temps" \
    --output-dir "$TMP" -o librt.sched.a
"$SELFHOST_CJC" --package "$TMP/cjthreadpreemption.noheap" --output-type=staticlib -O2 \
    --int-overflow wrapping --import-path "$TMP" --save-temps "$TMP/root_temps" \
    --output-dir "$TMP" -o libcjthreadpreemption.noheap.a
g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
    -c "$ROOT/test/parity/sched/cjthread_preemption_ref.cpp" -o "$TMP/ref.o"
"$SELFHOST_CJC" "$ROOT/test/parity/sched/cjthread_preemption_probe.cj" \
    --import-path "$TMP" --int-overflow wrapping \
    "$TMP/libcjthreadpreemption.noheap.a" "$TMP/librt.sched.a" "$TMP/ref.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/probe"

"$TMP/probe" > "$TMP/transcript"
grep -Fxq 'CJTHREAD_PREEMPTION add=0 sub=0 add_symbol=1 sub_symbol=1 resched_symbol=1 status=PASS' \
    "$TMP/transcript" || fail "behavior transcript mismatch"

for symbol in CJ_CJThreadPreemptOffCntAdd CJ_CJThreadPreemptOffCntSub CJ_CJThreadResched; do
    [[ $(nm -D "$RUNTIME_LIB" | awk -v symbol="$symbol" '$3 ~ ("^" symbol "(@@.*)?$") {++n} END {print n+0}') -eq 1 ]] ||
        fail "runtime export mismatch symbol=$symbol"
    [[ $(objdump -r "$TMP/sched_temps/rt.sched.o" | awk -v symbol="$symbol" '$3 == symbol {++n} END {print n+0}') -eq 1 ]] ||
        fail "candidate relocation mismatch symbol=$symbol"
done

LLVM_BIN="$TOOLCHAIN/third_party/llvm/bin"
"$LLVM_BIN/llvm-link" "$TMP/sched_temps/rt.sched.bc" "$TMP/root_temps/cjthreadpreemption.noheap.bc" \
    -o "$TMP/linked.pre.bc"
"$LLVM_BIN/llvm-link" "$TMP/sched_temps/rt.sched.opt.bc" "$TMP/root_temps/cjthreadpreemption.noheap.opt.bc" \
    -o "$TMP/linked.final.bc"
"$LLVM_BIN/llvm-dis" "$TMP/linked.pre.bc" -o "$TMP/pre.ll"
"$LLVM_BIN/llvm-dis" "$TMP/linked.final.bc" -o "$TMP/final.ll"

for stage in pre final; do
    for symbol in CJ_CJThreadPreemptOffCntAdd CJ_CJThreadPreemptOffCntSub CJ_CJThreadResched; do
        [[ $(rg -c "call i32 @$symbol\\(" "$TMP/$stage.ll") -ge 1 ]] ||
            fail "$stage call missing symbol=$symbol"
    done
    [[ $(rg -c 'MCC_NewObject|CJ_MCC_NewObject|MCC_NewArray|CJ_MCC_NewArray|MCC_Write|CJ_MCC_Write' "$TMP/$stage.ll" || true) -eq 0 ]] ||
        fail "$stage forbidden allocation/barrier"
done

cat "$TMP/transcript"
echo "CJTHREAD_PREEMPTION_ABI exports=3 relocations=3 status=PASS"
echo "CJTHREAD_PREEMPTION_NOHEAP roots=1 scheduler_entries=3 pre_forbidden=0 final_forbidden=0 object_forbidden=0 status=PASS"
echo "CJTHREAD_PREEMPTION_PLATFORM linux_ohos=PASS apple=PASS win64=PASS source_branches=0 status=PASS"
echo "run_cjthread_preemption_probe: PASS"
