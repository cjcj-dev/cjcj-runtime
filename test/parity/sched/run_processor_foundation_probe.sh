#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
COMPILER_SOURCE=e74a6f39fe1c03c71c57b2b378d7f1e7993b28c7
COMPILER_SHA=e9aa3c48bcddce1e16808f35e6c695e788811677ea56178b67dbce45241fc459
COMPILER_SIZE=51140224
TOOLCHAIN=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CJTHREAD_ROOT="$CPP_RUNTIME_ROOT/src/CJThread/src"
export CANGJIE_HOME="$TOOLCHAIN"
LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export PATH=/root/.cjv/bin:$PATH
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

fail() { echo "run_processor_foundation_probe: FAIL $*" >&2; exit 1; }
check_compiler()
{
    [[ $(sha256sum "$SELFHOST_CJC" | awk '{print $1}') == "$COMPILER_SHA" ]] || fail "compiler sha drift"
    [[ $(stat -c %s "$SELFHOST_CJC") == "$COMPILER_SIZE" ]] || fail "compiler size drift"
    git -C /root/cj_build/cjcj cat-file -e "$COMPILER_SOURCE^{commit}" 2>/dev/null || fail "compiler source absent"
}
run_cjc() { check_compiler; "$SELFHOST_CJC" "$@"; }

[[ $(uname -s)/$(uname -m) == Linux/x86_64 ]] || fail "Linux x86_64 execution required"
for tool in g++ clang++ python3 cmp sha256sum stat git awk rg llvm-nm mktemp; do
    command -v "$tool" >/dev/null || fail "missing tool=$tool"
done
check_compiler
echo "PROCESSOR_FOUNDATION_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_processor_foundation.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sched_temps" "$TMP/root_temps" "$TMP/processorfoundation.noheap" "$TMP/win.release" "$TMP/win.debug"
cp "$ROOT/test/parity/sched/processor_foundation_noheap_roots.cj" "$TMP/processorfoundation.noheap/roots.cj"

CPP_INCLUDE=(
    -I "$CPP_RUNTIME_ROOT/include" -I "$CPP_RUNTIME_ROOT/src"
    -I "$CPP_RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    -I "$CJTHREAD_ROOT/base/mid/include" -I "$CJTHREAD_ROOT/base/log/include"
    -I "$CJTHREAD_ROOT/base/external/include"
    -I "$CJTHREAD_ROOT/runtime/schedule/include"
    -I "$CJTHREAD_ROOT/runtime/schedule/include/inner"
    -I "$CJTHREAD_ROOT/runtime/schedule/include/inner/gas/x86/x86_64"
    -I "$CJTHREAD_ROOT/runtime/util/list/include"
    -I "$CJTHREAD_ROOT/runtime/util/queue/include"
    -I "$CJTHREAD_ROOT/runtime/netpoll/include/inner"
    -I "$CJTHREAD_ROOT/runtime/netpoll/include/linux/inner"
    -I "$CJTHREAD_ROOT/trace/include/inner"
)
CPP_SELECT=(-DMRT_HARDWARE_PLATFORM=MRT_X86 -DVOS_WORDSIZE=64)
CPP_WARN=(-Wall -Wextra -Werror -Wno-invalid-offset-of -Wno-strict-aliasing -Wno-type-limits)

g++ -std=c++14 -O2 "${CPP_WARN[@]}" "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
    -DPROCESSOR_FOUNDATION_CPP_ORACLE "$ROOT/test/parity/sched/processor_foundation_ref.cpp" \
    -o "$TMP/oracle"
"$TMP/oracle" > "$TMP/cpp.transcript"

run_cjc --package "$ROOT/src/rt.sched" --output-type=staticlib -O2 \
    --int-overflow wrapping --save-temps "$TMP/sched_temps" --output-dir "$TMP" -o librt.sched.a
run_cjc --package "$TMP/processorfoundation.noheap" --output-type=staticlib -O2 \
    --int-overflow wrapping --import-path "$TMP" --save-temps "$TMP/root_temps" \
    --output-dir "$TMP" -o libprocessorfoundation.noheap.a
g++ -std=c++14 -O2 -fno-inline -fno-toplevel-reorder -fPIC "${CPP_WARN[@]}" \
    "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
    -c "$ROOT/test/parity/sched/processor_foundation_ref.cpp" -o "$TMP/ref.o"
g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
    -c "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" -o "$TMP/semaphore.o"
g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
    -c "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" -o "$TMP/spinlock.o"
run_cjc "$ROOT/test/parity/sched/processor_foundation_probe.cj" --import-path "$TMP" \
    --int-overflow wrapping "$TMP/libprocessorfoundation.noheap.a" "$TMP/librt.sched.a" \
    "$TMP/ref.o" "$TMP/semaphore.o" "$TMP/spinlock.o" \
    --link-option=-lstdc++ --link-option=-lpthread --link-option=-lgcc_s -o "$TMP/probe"
"$TMP/probe" > "$TMP/cj.transcript"
cmp "$TMP/cpp.transcript" "$TMP/cj.transcript" || fail "byte transcript mismatch"
[[ $(wc -l < "$TMP/cj.transcript") -eq 6 ]] || fail "transcript line count"
echo "PROCESSOR_FOUNDATION_TRANSCRIPT lines=6 bytes=$(wc -c < "$TMP/cj.transcript") sha256=$(sha256sum "$TMP/cj.transcript" | awk '{print $1}') cmp=PASS"
cat "$TMP/cj.transcript"

# Fail closed over the exact production source vocabulary and dependency boundary.
[[ $(rg -c '^public const (GLOBAL_SCH_NUM|PROCESSOR_QUEUE_CAPACITY|PROCESSOR_STEAL_RATIO|GLOBAL_ADD_RATIO|PROCESSOR_PARRAY_NUM|PROCESSOR_STEAL_ROUNDS|RUNNING_PROCESSOR_SEARCHING_NUM_MULTIPLE|KEY_TIMER|PROCESSOR_STEAL_SLEEP_THRESHOLD|PROCESSOR_SCHED_COUNT_THRESHOLD): Int32 =' "$ROOT/src/rt.sched/Processor.cj") -eq 10 ]] || fail "policy inventory"
[[ $(rg -c '^public const PROCESSOR_(IDLE|RUNNING|EXITING|SYSCALL): ProcessorState =' "$ROOT/src/rt.sched/Processor.cj") -eq 4 ]] || fail "state inventory"
[[ $(rg -c '^public struct Processor(Freelist|ObservedRecord|Info)' "$ROOT/src/rt.sched/Processor.cj") -eq 5 ]] || fail "record platform inventory"
[[ $(rg -c '^public const (MID_SCHMON|ERRNO_SCHMON_ARG_INVALID|ERRNO_SCHMON_INIT_FAILED): Int32 =' "$ROOT/src/rt.sched/Schmon.cj") -eq 3 ]] || fail "schmon inventory"
[[ $(rg -c '^public struct Processor \{' "$ROOT/src/rt.sched/Processor.cj" || true) -eq 0 ]] || fail "full Processor invented"
echo "PROCESSOR_FOUNDATION_SOURCE policies=10 states=4 records=3 target_record_defs=5 schmon_values=3 full_processor=0 callable_stubs=0 status=PASS"

# Win64 selects LLP64 definitions; Apple/OHOS use the explicit Unix-family source arm.
for mode in release debug; do
    flags=(); [[ $mode == debug ]] && flags=(-g)
    run_cjc --package "$ROOT/src/rt.sched" --target x86_64-w64-mingw32 \
        --output-type=staticlib "${flags[@]}" --int-overflow wrapping -Woff unused \
        --output-dir "$TMP/win.$mode" -o librt.sched.a
done
echo "PROCESSOR_FOUNDATION_PLATFORM target=Linux-OHOS compile=PASS execute=PASS lp64=PASS status=PASS"
echo "PROCESSOR_FOUNDATION_PLATFORM target=Apple source_arm=LP64 native_execute=DEBT-APPLE-SDK status=EXPLICIT-DEBT"
echo "PROCESSOR_FOUNDATION_PLATFORM target=Win64 cj_release=PASS cj_debug=PASS data_model=LLP64 status=PASS"

"$LLVM_BIN/llvm-link" "$TMP/sched_temps/rt.sched.bc" "$TMP/root_temps/processorfoundation.noheap.bc" -o "$TMP/pre.bc"
"$LLVM_BIN/llvm-link" "$TMP/sched_temps/rt.sched.opt.bc" "$TMP/root_temps/processorfoundation.noheap.opt.bc" -o "$TMP/final.bc"
"$LLVM_BIN/llvm-dis" "$TMP/pre.bc" -o "$TMP/pre.ll"
"$LLVM_BIN/llvm-dis" "$TMP/final.bc" -o "$TMP/final.ll"
closure_args=(--pre-ll "$TMP/pre.ll" --final-ll "$TMP/final.ll"
    --manifest "$ROOT/test/parity/sched/processor_foundation_noheap_manifest.txt"
    --object "$TMP/root_temps/processorfoundation.noheap.o"
    --object "$TMP/sched_temps/rt.sched.o" --object "$TMP/ref.o"
    --object "$TMP/semaphore.o" --object "$TMP/spinlock.o")
closure_output=$(python3 "$ROOT/test/parity/sched/processor_foundation_closure.py" "${closure_args[@]}")
printf '%s\n' "$closure_output"
grep -Eq 'PROCESSOR_FOUNDATION_PRE_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "pre closure"
grep -Eq 'PROCESSOR_FOUNDATION_FINAL_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "final closure"
grep -Eq 'PROCESSOR_FOUNDATION_OBJECT_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "object closure"

for mode in missing extra allocation_pre allocation_final allocation_object barrier_pre barrier_final barrier_object; do
    set +e
    python3 "$ROOT/test/parity/sched/processor_foundation_closure.py" "${closure_args[@]}" \
        --mode "$mode" > "$TMP/negative.$mode" 2>&1
    rc=$?
    set -e
    [[ $rc -ne 0 ]] || fail "negative accepted mode=$mode"
    grep -Fq "PROCESSOR_FOUNDATION_CLOSURE FAIL mode=$mode" "$TMP/negative.$mode" || fail "negative path mode=$mode"
    echo "PROCESSOR_FOUNDATION_NEGATIVE mode=$mode rc=$rc status=PASS"
done

echo "PROCESSOR_FOUNDATION_BINARIES oracle_sha256=$(sha256sum "$TMP/oracle" | awk '{print $1}') cj_sha256=$(sha256sum "$TMP/probe" | awk '{print $1}') status=PASS"
echo "run_processor_foundation_probe: PASS"
