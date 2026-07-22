#!/usr/bin/env bash
# Fail-closed schedule.h:344-353 value, owner-index, inventory, and closure parity.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
RUNTIME_SOURCE_ROOT="$CPP_RUNTIME_ROOT/src"
CJTHREAD_ROOT="$RUNTIME_SOURCE_ROOT/CJThread/src"
SCHEDULE_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/schedule.h"
SCHEDULE_IMPL="$CJTHREAD_ROOT/runtime/schedule/include/inner/schedule_impl.h"
SCHEDULE_RENAME="$CJTHREAD_ROOT/base/mid/include/schedule_rename.h"
SCHEDULE_SOURCE="$CJTHREAD_ROOT/runtime/schedule/src/cjthread.cpp"
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export PATH=/root/.cjv/bin:$PATH
export LD_LIBRARY_PATH="$SELFHOST_RT:$LD_LIBRARY_PATH"
export cjHeapSize=24GB

fail()
{
    echo "run_cjthread_state_hook_probe: FAIL $*" >&2
    exit 1
}

check_compiler()
{
    local actual_sha actual_size
    [[ -x "$SELFHOST_CJC" ]] || fail "pinned compiler is not executable"
    actual_sha=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}')
    actual_size=$(stat -c %s "$SELFHOST_CJC")
    [[ "$actual_sha" == "$COMPILER_SHA" ]] || fail "compiler sha drift actual=$actual_sha"
    [[ "$actual_size" == "$COMPILER_SIZE" ]] || fail "compiler size drift actual=$actual_size"
    git -C /root/cj_build/cjcj cat-file -e "$COMPILER_SOURCE^{commit}" 2>/dev/null ||
        fail "compiler source commit absent"
}

run_cjc()
{
    check_compiler
    "$SELFHOST_CJC" "$@"
}

require_inputs()
{
    local tool input
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
        fail "executable oracle requires Linux x86_64"
    for tool in g++ objdump python3 cmp sha256sum stat git awk sed grep rg df find wc cp mktemp uname; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    [[ -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] ||
        fail "missing pinned nightly LLVM tools"
    for input in "$SCHEDULE_HEADER" "$SCHEDULE_IMPL" "$SCHEDULE_RENAME" "$SCHEDULE_SOURCE" \
        "$ROOT/src/rt.sched/Thread.cj" \
        "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" \
        "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" \
        "$ROOT/test/parity/sched/cjthread_state_hook_ref.cpp" \
        "$ROOT/test/parity/sched/cjthread_state_hook_probe.cj" \
        "$ROOT/test/parity/sched/cjthread_state_hook_noheap_roots.cj" \
        "$ROOT/test/parity/sched/cjthread_state_hook_source_check.py" \
        "$ROOT/test/parity/sched/cjthread_state_hook_consumers.txt" \
        "$ROOT/test/parity/sched/cjthread_state_hook_noheap_manifest.txt" \
        "$ROOT/test/parity/sched/cjthread_state_hook_closure.py" \
        "$ROOT/test/parity/base/atomicspinlock_closure.py"; do
        [[ -f "$input" ]] || fail "missing input $input"
    done
}

require_inputs
check_compiler
echo "CJTHREAD_STATE_HOOK_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"
disk_before=$(df -Pk / | awk 'NR==2 {print $4}')
echo "CJTHREAD_STATE_HOOK_DISK_BEFORE available_kb=$disk_before"

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_cjthread_state_hook.XXXXXX")
trap 'rm -rf "$IMP"' EXIT
ulimit -c 0
mkdir -p "$IMP/sched_temps" "$IMP/root_temps" "$IMP/cjthreadstatehook.noheap"
cp "$ROOT/test/parity/sched/cjthread_state_hook_noheap_roots.cj" \
    "$IMP/cjthreadstatehook.noheap/roots.cj"

CPP_ORACLE="$IMP/cjthread_state_hook_oracle"
CJ_PROBE="$IMP/cjthread_state_hook_probe"
CPP_TRANSCRIPT="$IMP/cpp.transcript"
CJ_TRANSCRIPT="$IMP/cj.transcript"
CPP_SELECT=(-DMRT_HARDWARE_PLATFORM=MRT_X86 -DVOS_WORDSIZE=64)
CPP_INCLUDE=(
    -I "$CPP_RUNTIME_ROOT/include"
    -I "$CPP_RUNTIME_ROOT/src"
    -I "$CPP_RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    -I "$CJTHREAD_ROOT/base/mid/include"
    -I "$CJTHREAD_ROOT/base/log/include"
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
CPP_WARN=(-Wall -Wextra -Werror -Wno-invalid-offset-of -Wno-strict-aliasing
    -Wno-overloaded-virtual -Wno-type-limits)

build_cpp_oracle()
{
    g++ -std=c++14 -O2 "${CPP_WARN[@]}" "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
        -DCJTHREAD_STATE_HOOK_CPP_ORACLE \
        "$ROOT/test/parity/sched/cjthread_state_hook_ref.cpp" -o "$CPP_ORACLE"
    "$CPP_ORACLE" > "$CPP_TRANSCRIPT"
}

check_transcript()
{
    local transcript=$1
    [[ $(wc -l < "$transcript") -eq 11 ]] || fail "transcript line count mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK_REP enum_size=4 enum_align=4 enum_underlying_signed=0 alias_size=4 alias_align=4 alias_signed=0' "$transcript" || fail "unsigned representation mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK name=CJTHREAD_BEFORE_PARK value=0 bytes=00000000' "$transcript" || fail "BEFORE_PARK mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK name=CJTHREAD_AFTER_PARK value=1 bytes=01000000' "$transcript" || fail "AFTER_PARK mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK name=CJTHREAD_BEFORE_RESCHED value=2 bytes=02000000' "$transcript" || fail "BEFORE_RESCHED mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK name=CJTHREAD_AFTER_RESCHED value=3 bytes=03000000' "$transcript" || fail "AFTER_RESCHED mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK name=CJTHREAD_STATE_HOOK_BUTT value=4 bytes=04000000' "$transcript" || fail "HOOK_BUTT mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK_OWNER sizeof=704 align=8 array_offset=360 array_size=32 array_align=8 element_size=8 element_align=8 element_count=4 owner_field_address_match=1 distinct_callback_pairs=6' "$transcript" || fail "owner layout mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK_SLOT name=CJTHREAD_BEFORE_PARK index=0 slot_offset=0 stride_from_previous=0 callback_identity=0 callback_match=1' "$transcript" || fail "BEFORE_PARK slot mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK_SLOT name=CJTHREAD_AFTER_PARK index=1 slot_offset=8 stride_from_previous=8 callback_identity=1 callback_match=1' "$transcript" || fail "AFTER_PARK slot mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK_SLOT name=CJTHREAD_BEFORE_RESCHED index=2 slot_offset=16 stride_from_previous=8 callback_identity=2 callback_match=1' "$transcript" || fail "BEFORE_RESCHED slot mismatch"
    grep -Fxq 'CJTHREAD_STATE_HOOK_SLOT name=CJTHREAD_AFTER_RESCHED index=3 slot_offset=24 stride_from_previous=8 callback_identity=3 callback_match=1' "$transcript" || fail "AFTER_RESCHED slot mismatch"
}

check_source_consumers_platforms()
{
    python3 "$ROOT/test/parity/sched/cjthread_state_hook_source_check.py" \
        --source "$ROOT/src/rt.sched/Thread.cj" \
        --runtime-root "$RUNTIME_SOURCE_ROOT" \
        --inventory "$ROOT/test/parity/sched/cjthread_state_hook_consumers.txt"
    [[ $(sed -n '344,353p' "$SCHEDULE_HEADER" | rg -c '_WIN32|__APPLE__|__OHOS__|__linux__|#if|#elif' || true) -eq 0 ]] ||
        fail "target enum acquired a platform branch"
    grep -Fxq '#define CJThreadeStateHookRegister             CJ_CJThreadStateHookRegister' "$SCHEDULE_RENAME" ||
        fail "authoritative misspelled C ABI rename drift"
    sed -n '10,15p' "$SCHEDULE_RENAME" | grep -Fxq '#ifdef CANGJIE' ||
        fail "rename CANGJIE build-mode context drift"
    [[ $(sed -n '1136,1152p' "$SCHEDULE_SOURCE" | rg -c '#if|#elif|#else|#endif' || true) -eq 0 ]] ||
        fail "registration/store acquired conditional context"
    sed -n '210,223p' "$SCHEDULE_IMPL" | grep -Fxq '#ifdef __OHOS__' ||
        fail "OHOS owner trailing-field context drift"
    echo "CJTHREAD_STATE_HOOK_CONSUMERS lines=15 tokens=21 definitions=6 callback_typedefs=1 owner_arrays=1 array_reads=0 callback_dispatches=0 generic_array_stores=1 upper_bound_validations=1 api_declarations=1 gc_registrations=0 rename_macros=1 switch_consumers=0 position_enumerator_consumers=0 sentinel_bound_uses=2 status=PASS"
    echo "CJTHREAD_STATE_HOOK_PLATFORMS target_cpp_branches=0 all_target_lines=14 cangjie_build_mode_lines=1 owner_registration_validation_store_context=ALL_TARGETS linux_x86_64=COMPILED_EXECUTED macos=UNEXECUTED_DEBT ios=UNEXECUTED_DEBT aarch64_linux=UNEXECUTED_DEBT android_arm32=UNEXECUTED_DEBT android_arm64=UNEXECUTED_DEBT win64=UNEXECUTED_DEBT ohos=UNEXECUTED_DEBT sanitizer_modes=UNEXECUTED_DEBT cangjie_rename_mode=UNEXECUTED_DEBT other_targets_build_modes=UNEXECUTED_DEBT ohos_owner_size=UNCLAIMED status=PASS"
}

build_cangjie_probe()
{
    run_cjc --package "$ROOT/src/rt.sched" --output-type=staticlib -O2 \
        --int-overflow wrapping --save-temps "$IMP/sched_temps" \
        --output-dir "$IMP" -o librt.sched.a
    run_cjc --package "$IMP/cjthreadstatehook.noheap" --output-type=staticlib -O2 \
        --int-overflow wrapping --import-path "$IMP" --save-temps "$IMP/root_temps" \
        --output-dir "$IMP" -o libcjthreadstatehook.noheap.a
    g++ -std=c++14 -O2 -fno-inline -fno-toplevel-reorder -fPIC "${CPP_WARN[@]}" \
        "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
        -c "$ROOT/test/parity/sched/cjthread_state_hook_ref.cpp" \
        -o "$IMP/cjthread_state_hook_ref.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" -o "$IMP/CJThreadSemaphore.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" -o "$IMP/CJThreadSpinLock.o"
    run_cjc "$ROOT/test/parity/sched/cjthread_state_hook_probe.cj" --import-path "$IMP" \
        --int-overflow wrapping "$IMP/libcjthreadstatehook.noheap.a" "$IMP/librt.sched.a" \
        "$IMP/cjthread_state_hook_ref.o" "$IMP/CJThreadSemaphore.o" "$IMP/CJThreadSpinLock.o" \
        --link-option=-lstdc++ --link-option=-lpthread --link-option=-lgcc_s -o "$CJ_PROBE"
    "$CJ_PROBE" > "$CJ_TRANSCRIPT"
}

check_ir_and_closure()
{
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.bc" \
        "$IMP/root_temps/cjthreadstatehook.noheap.bc" -o "$IMP/linked.pre.bc"
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.opt.bc" \
        "$IMP/root_temps/cjthreadstatehook.noheap.opt.bc" -o "$IMP/linked.final.bc"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.pre.bc" -o "$IMP/linked.pre.ll"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.final.bc" -o "$IMP/linked.final.ll"
    closure_args=(
        --pre-ll "$IMP/linked.pre.ll"
        --final-ll "$IMP/linked.final.ll"
        --manifest "$ROOT/test/parity/sched/cjthread_state_hook_noheap_manifest.txt"
        --object "$IMP/root_temps/cjthreadstatehook.noheap.o"
        --object "$IMP/sched_temps/rt.sched.o"
        --object "$IMP/cjthread_state_hook_ref.o"
        --object "$IMP/CJThreadSemaphore.o"
        --object "$IMP/CJThreadSpinLock.o"
    )
    local closure_output
    closure_output=$(python3 "$ROOT/test/parity/sched/cjthread_state_hook_closure.py" "${closure_args[@]}")
    printf '%s\n' "$closure_output"
    grep -Eq 'CJTHREAD_STATE_HOOK_PRE_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "pre closure equality absent"
    grep -Eq 'CJTHREAD_STATE_HOOK_FINAL_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "final closure equality absent"
    grep -Eq 'CJTHREAD_STATE_HOOK_OBJECT_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "object closure equality absent"
}

run_negative_injections()
{
    local mode rc stage symbol reason
    for mode in value_before_park value_after_park value_before_resched \
        value_after_resched value_butt swapped omitted alias64 alias_signed initializer; do
        set +e
        python3 "$ROOT/test/parity/sched/cjthread_state_hook_source_check.py" \
            --source "$ROOT/src/rt.sched/Thread.cj" --mode "$mode" \
            > "$IMP/source-negative.$mode.log" 2>&1
        rc=$?
        set -e
        [[ $rc -ne 0 ]] || fail "source negative accepted mode=$mode"
        grep -Fq "CJTHREAD_STATE_HOOK_SOURCE FAIL mode=$mode" "$IMP/source-negative.$mode.log" ||
            fail "source negative did not execute checker mode=$mode"
        echo "CJTHREAD_STATE_HOOK_NEGATIVE mode=$mode rc=$rc stage=source symbol=CJThreadStateHook reason=representation_order_or_initializer status=PASS"
    done
    for mode in extra_registration missing_registration missing_owner_bound rename_spelling \
        missing_generic_store; do
        set +e
        python3 "$ROOT/test/parity/sched/cjthread_state_hook_source_check.py" \
            --source "$ROOT/src/rt.sched/Thread.cj" --runtime-root "$RUNTIME_SOURCE_ROOT" \
            --inventory "$ROOT/test/parity/sched/cjthread_state_hook_consumers.txt" \
            --inventory-mode "$mode" > "$IMP/inventory-negative.$mode.log" 2>&1
        rc=$?
        set -e
        [[ $rc -ne 0 ]] || fail "inventory negative accepted mode=$mode"
        grep -Fq "inventory_mode=$mode" "$IMP/inventory-negative.$mode.log" ||
            fail "inventory negative did not execute checker mode=$mode"
        echo "CJTHREAD_STATE_HOOK_NEGATIVE mode=$mode rc=$rc stage=inventory symbol=runtime_source_occurrence reason=inventory_drift status=PASS"
    done
    for mode in missing extra allocation_pre allocation_final allocation_object \
        barrier_pre barrier_final barrier_object; do
        case "$mode" in
            missing|extra) stage=pre; symbol=reached/scanned; reason="${mode}_definition" ;;
            allocation_pre) stage=pre; symbol=MCC_NewObject; reason=forbidden_allocation ;;
            allocation_final) stage=final; symbol=CJ_MCC_NewObject; reason=forbidden_allocation ;;
            allocation_object) stage=object; symbol=MCC_NewArray; reason=forbidden_allocation ;;
            barrier_pre) stage=pre; symbol=MCC_WriteRefField; reason=forbidden_barrier ;;
            barrier_final) stage=final; symbol=CJ_MCC_AtomicSwapReference; reason=forbidden_barrier ;;
            barrier_object) stage=object; symbol=CJ_MCC_WriteGenericPayload; reason=forbidden_barrier ;;
        esac
        set +e
        python3 "$ROOT/test/parity/sched/cjthread_state_hook_closure.py" "${closure_args[@]}" \
            --mode "$mode" > "$IMP/closure-negative.$mode.log" 2>&1
        rc=$?
        set -e
        [[ $rc -ne 0 ]] || fail "closure negative accepted mode=$mode"
        grep -Fq "CJTHREAD_STATE_HOOK_CLOSURE FAIL mode=$mode" "$IMP/closure-negative.$mode.log" ||
            fail "closure negative did not execute analyzer mode=$mode"
        grep -Fq "$symbol" "$IMP/closure-negative.$mode.log" ||
            fail "closure negative missed symbol mode=$mode symbol=$symbol"
        echo "CJTHREAD_STATE_HOOK_NEGATIVE mode=$mode rc=$rc stage=$stage symbol=$symbol reason=$reason status=PASS"
    done
}

build_cpp_oracle
check_transcript "$CPP_TRANSCRIPT"
check_source_consumers_platforms
build_cangjie_probe
check_transcript "$CJ_TRANSCRIPT"
cmp "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT" || fail "complete normalized transcript mismatch"
echo "CJTHREAD_STATE_HOOK_TRANSCRIPT lines=$(wc -l < "$CJ_TRANSCRIPT") bytes=$(wc -c < "$CJ_TRANSCRIPT") sha256=$(sha256sum "$CJ_TRANSCRIPT" | awk '{print $1}') cmp=PASS"
cat "$CJ_TRANSCRIPT"
check_ir_and_closure
run_negative_injections

echo "CJTHREAD_STATE_HOOK_BINARIES oracle_sha256=$(sha256sum "$CPP_ORACLE" | awk '{print $1}') oracle_size=$(stat -c %s "$CPP_ORACLE") cj_sha256=$(sha256sum "$CJ_PROBE" | awk '{print $1}') cj_size=$(stat -c %s "$CJ_PROBE") status=PASS"
echo "CJTHREAD_STATE_HOOK_STAGES cpp_header=1 cj_values=5 unsigned_alias=1 owner_layout=1 owner_slots=4 source_inventory=1 consumers=15 pre_closure=1 final_closure=1 object_closure=1 allocation_negatives=3 barrier_negatives=3 definition_negatives=2 source_negatives=10 inventory_negatives=5 status=PASS"
disk_after=$(df -Pk / | awk 'NR==2 {print $4}')
disk_delta=$((disk_before - disk_after))
echo "CJTHREAD_STATE_HOOK_DISK_AFTER available_kb=$disk_after consumed_kb=$disk_delta"
(( disk_delta < 2097152 )) || fail "probe consumed more than 2GiB"
echo "run_cjthread_state_hook_probe: PASS"
