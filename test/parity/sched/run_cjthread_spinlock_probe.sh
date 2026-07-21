#!/usr/bin/env bash
# Fail-closed CJThread base.h spinlock layout, behavior, ABI, and whole-closure parity.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
SELFHOST_RT="$RUNTIME_TOOLCHAIN_RT_LIB"
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CJTHREAD_ROOT="$CPP_RUNTIME_ROOT/src/CJThread/src"
BASE_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/inner/base.h"
export PATH=/root/.cjv/bin:$PATH
export cjHeapSize=24GB

fail()
{
    echo "run_cjthread_spinlock_probe: FAIL $*" >&2
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
        fail "executable target must be Linux x86_64"
    for tool in g++ objdump nm readelf ldd python3 cmp sha256sum stat git awk sed grep rg df; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    [[ -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] ||
        fail "missing pinned nightly LLVM tools"
    for input in \
        "$BASE_HEADER" \
        "$CJTHREAD_ROOT/base/mid/include/macro_def.h" \
        "$ROOT/src/rt.sched/CJthreadSpinLock.cj" \
        "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" \
        "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" \
        "$ROOT/test/parity/sched/cjthread_spinlock_ref.cpp" \
        "$ROOT/test/parity/sched/cjthread_spinlock_probe.cj" \
        "$ROOT/test/parity/sched/cjthread_spinlock_noheap_roots.cj" \
        "$ROOT/test/parity/sched/cjthread_spinlock_noheap_manifest.txt" \
        "$ROOT/test/parity/sched/cjthread_spinlock_closure.py" \
        "$ROOT/test/parity/base/atomicspinlock_closure.py"; do
        [[ -f "$input" ]] || fail "missing input $input"
    done
    [[ $(find "$ROOT/rt0/os" -type f -name CJThreadSpinLock.cpp -print | wc -l) -eq 1 ]] ||
        fail "unexpected CJThread spinlock bridge source count"
}

require_inputs
check_compiler
echo "CJTHREAD_SPINLOCK_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"
disk_before=$(df -Pk / | awk 'NR==2 {print $4}')
echo "CJTHREAD_SPINLOCK_DISK_BEFORE available_kb=$disk_before"

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_cjthread_spinlock_probe.XXXXXX")
trap 'rm -rf "$IMP"' EXIT
ulimit -c 0
mkdir -p "$IMP/sched_temps" "$IMP/root_temps" "$IMP/cjthreadspinlock.noheap"

CPP_ORACLE="$IMP/cjthread_spinlock_oracle"
CJ_PROBE="$IMP/cjthread_spinlock_probe"
CPP_TRANSCRIPT="$IMP/cpp.transcript"
CJ_TRANSCRIPT="$IMP/cj.transcript"
CPP_INCLUDE=(
    -I "$CJTHREAD_ROOT/base/mid/include"
    -I "$CJTHREAD_ROOT/runtime/schedule/include/inner"
)
CPP_SELECT=(-DMRT_HARDWARE_PLATFORM=MRT_X86 -DVOS_WORDSIZE=64)
WRAP_OPTIONS=(
    --wrap=pthread_spin_init
    --wrap=pthread_spin_lock
    --wrap=pthread_spin_unlock
    --wrap=pthread_spin_destroy
)

build_cpp_oracle()
{
    g++ -std=c++14 -O2 -Wall -Wextra -Werror -DCJTHREAD_SPINLOCK_ORACLE \
        "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
        "$ROOT/test/parity/sched/cjthread_spinlock_ref.cpp" -pthread \
        -Wl,"${WRAP_OPTIONS[0]}" -Wl,"${WRAP_OPTIONS[1]}" \
        -Wl,"${WRAP_OPTIONS[2]}" -Wl,"${WRAP_OPTIONS[3]}" -o "$CPP_ORACLE"
    "$CPP_ORACLE" > "$CPP_TRANSCRIPT"
    [[ -s "$CPP_TRANSCRIPT" ]] || fail "empty C++ oracle transcript"
}

check_cpp_oracle()
{
    [[ $(wc -l < "$CPP_TRANSCRIPT") -eq 9 ]] || fail "unexpected C++ transcript record count"
    grep -Fxq 'CJTHREAD_SPINLOCK_PTHREAD sizeof=4 align=4 is_int=false remove_cv_is_int=true volatile=true' \
        "$CPP_TRANSCRIPT" || fail "pthread_spinlock_t layout mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_LAYOUT sizeof=4 align=4 lock=0' "$CPP_TRANSCRIPT" ||
        fail "CJthreadSpinLock layout mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_BYTES init=01000000 held_lock=00000000 unlock=01000000 destroy=01000000' \
        "$CPP_TRANSCRIPT" || fail "complete C++ object bytes mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_RETURNS init=0 lock=0 unlock=0 destroy=0' "$CPP_TRANSCRIPT" ||
        fail "source operation return codes mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_BLOCK pre_release=1 acquired_before_release=0 post_release=1 acquired_after_release=1 status=PASS' \
        "$CPP_TRANSCRIPT" || fail "blocking acquisition mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_COUNTER threads=8 iterations=4096 expected=32768 actual=32768 status=PASS' \
        "$CPP_TRANSCRIPT" || fail "deterministic counter mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_HANDOFF payload=1511506142 observed=1511506142 status=PASS' \
        "$CPP_TRANSCRIPT" || fail "release/acquire handoff mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_CALLS init=1 lock=32773 unlock=32773 destroy=1 address_mismatches=0 destroy_after_users=true' \
        "$CPP_TRANSCRIPT" || fail "native call/address count mismatch"
    grep -Fxq 'CJTHREAD_SPINLOCK_NONZERO safe_defined_trigger=none caller_owned_error_policy=true' \
        "$CPP_TRANSCRIPT" || fail "nonzero-return policy record mismatch"
}

build_production_and_probe()
{
    run_cjc --package "$ROOT/src/rt.sched" --output-type=staticlib -O2 \
        --int-overflow wrapping --save-temps "$IMP/sched_temps" \
        --output-dir "$IMP" -o librt.sched.a
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" -o "$IMP/CJThreadSpinLock.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" -o "$IMP/CJThreadSemaphore.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
        -c "$ROOT/test/parity/sched/cjthread_spinlock_ref.cpp" -o "$IMP/cjthread_spinlock_ref.o"
    local link_args=()
    local option
    for option in "${WRAP_OPTIONS[@]}"; do
        link_args+=("--link-option=$option")
    done
    run_cjc "$ROOT/test/parity/sched/cjthread_spinlock_probe.cj" \
        --import-path "$IMP" --int-overflow wrapping "$IMP/librt.sched.a" \
        "$IMP/CJThreadSpinLock.o" "$IMP/CJThreadSemaphore.o" "$IMP/cjthread_spinlock_ref.o" \
        --link-option=-lstdc++ --link-option=-lpthread --link-option=-lgcc_s \
        "${link_args[@]}" -o "$CJ_PROBE"
    [[ -x "$CJ_PROBE" ]] || fail "Cangjie consumer executable absent"
    local resolved_runtime
    resolved_runtime=$(ldd "$CJ_PROBE" | awk '/libcangjie-runtime\.so/{print $3; exit}')
    [[ "$(readlink -f "$resolved_runtime")" == "$(readlink -f "$SELFHOST_RT/libcangjie-runtime.so")" ]] ||
        fail "Cangjie consumer runtime identity mismatch"
    "$CJ_PROBE" > "$CJ_TRANSCRIPT"
    cmp -s "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT" || {
        echo "C++ transcript:" >&2
        sed -n '1,20p' "$CPP_TRANSCRIPT" >&2
        echo "Cangjie transcript:" >&2
        sed -n '1,20p' "$CJ_TRANSCRIPT" >&2
        fail "C++/Cangjie transcript byte mismatch"
    }
}

check_layout_calls_and_abi()
{
    "$LLVM_BIN/llvm-dis" "$IMP/sched_temps/rt.sched.opt.bc" -o "$IMP/sched.final.ll"
    grep -Fxq '%"record.rt.sched:CJthreadSpinLock" = type { i32 }' "$IMP/sched.final.ll" ||
        fail "Cangjie inline record is not exactly one Int32"
    [[ $(grep -Fc '@When[os == "Linux" && arch == "x86_64"]' \
        "$ROOT/src/rt.sched/CJthreadSpinLock.cj") -eq 9 ]] || fail "local compiled branch count mismatch"
    [[ $(grep -Fc 'CJTHREAD-SPINLOCK-PLATFORM-LAYOUT:' \
        "$ROOT/src/rt.sched/CJthreadSpinLock.cj") -eq 3 ]] || fail "local platform debt count mismatch"
    [[ $(grep -Fxc 'struct CJthreadSpinLock {' "$BASE_HEADER") -eq 3 ]] ||
        fail "C++ representation branch count mismatch"
    for operation in Init Lock Unlock Destroy; do
        [[ $(grep -Fc "static inline int PthreadSpin$operation" "$BASE_HEADER") -eq 3 ]] ||
            fail "C++ operation branch count mismatch operation=$operation"
    done
    ! rg -q 'TryLock|~CJthreadSpinLock|Scoped|RAII|malloc|calloc|realloc|new ' \
        "$ROOT/src/rt.sched/CJthreadSpinLock.cj" "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" ||
        fail "invented operation, ownership, or allocation surface present"

    local lower target native_defs native_relocs sched_relocs executable_defs hidden_defs
    for operation in init lock unlock destroy; do
        lower="cj_cjthread_pthread_spin_$operation"
        target="pthread_spin_$operation"
        [[ $(grep -Fc "func $lower(lock: CPointer<Int32>): Int32" \
            "$ROOT/src/rt.sched/CJthreadSpinLock.cj") -eq 1 ]] ||
            fail "Cangjie foreign signature mismatch operation=$operation"
        [[ $(grep -Fc "int32_t $lower(int32_t* lock)" \
            "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp") -eq 1 ]] ||
            fail "native bridge signature mismatch operation=$operation"
        [[ $(grep -Fc "return $target(" "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp") -eq 1 ]] ||
            fail "native source call multiplicity mismatch operation=$operation"
        native_defs=$(nm -g --defined-only "$IMP/CJThreadSpinLock.o" |
            awk -v symbol="$lower" '$3 == symbol {++n} END {print n+0}')
        native_relocs=$(objdump -r "$IMP/CJThreadSpinLock.o" |
            awk -v symbol="$target" '$3 ~ ("^" symbol "(-0x[0-9A-Fa-f]+)?$") {++n} END {print n+0}')
        sched_relocs=$(objdump -r "$IMP/sched_temps/rt.sched.o" |
            awk -v symbol="$lower" '$3 ~ ("^" symbol "(-0x[0-9A-Fa-f]+)?$") {++n} END {print n+0}')
        executable_defs=$(nm -g --defined-only "$CJ_PROBE" |
            awk -v symbol="$lower" '$3 == symbol {++n} END {print n+0}')
        hidden_defs=$(readelf -Ws "$IMP/CJThreadSpinLock.o" |
            awk -v symbol="$lower" '$5 == "GLOBAL" && $6 == "HIDDEN" && $8 == symbol {++n} END {print n+0}')
        [[ $native_defs -eq 1 && $native_relocs -eq 1 && $sched_relocs -eq 1 &&
           $executable_defs -eq 1 && $hidden_defs -eq 1 ]] ||
            fail "bridge edge mismatch operation=$operation defs=$native_defs native_relocs=$native_relocs sched_relocs=$sched_relocs executable_defs=$executable_defs hidden=$hidden_defs"
    done
    [[ $(grep -Fc 'PTHREAD_PROCESS_PRIVATE' "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp") -eq 1 ]] ||
        fail "init sharing argument is not exactly PTHREAD_PROCESS_PRIVATE"
    for operation in Init Lock Unlock Destroy; do
        [[ $(nm -g --defined-only "$CJ_PROBE" |
            awk -v symbol="CJRT_CJthreadSpinLock$operation" '$3 == symbol {++n} END {print n+0}') -eq 1 ]] ||
            fail "test C entry count mismatch operation=$operation"
    done
    for symbol in pthread_spin_init pthread_spin_lock pthread_spin_unlock pthread_spin_destroy; do
        objdump -T "$CJ_PROBE" | grep -Eq "\\*UND\\*.*GLIBC_.*${symbol}$" ||
            fail "real glibc pthread edge absent symbol=$symbol"
    done
    ! rg -q 'CJRT_CJthreadSpinLock|cj_cjthread_pthread_spin_' "$ROOT/contract" ||
        fail "test/internal spinlock symbol leaked into production contract manifest"
    echo "CJTHREAD_SPINLOCK_LAYOUT_GATE cpp_pthread=4/4 cpp_value=4/4/0 cj_value=4/4/0 complete_states=4 status=PASS"
    echo "CJTHREAD_SPINLOCK_BRIDGE cj_signatures=4 native_definitions=4 native_relocations=4 sched_relocations=4 executable_definitions=4 hidden=4 process_private=1 original_address=1 status=PASS"
    echo "CJTHREAD_SPINLOCK_ABI public_inventory_delta=0 test_symbols_manifested=0 pthread_glibc_edges=4 status=PASS"
}

build_closure_inputs()
{
    cp "$ROOT/test/parity/sched/cjthread_spinlock_noheap_roots.cj" \
        "$IMP/cjthreadspinlock.noheap/Roots.cj"
    run_cjc --package "$IMP/cjthreadspinlock.noheap" --output-type=staticlib -O2 \
        --int-overflow wrapping --import-path "$IMP" --save-temps "$IMP/root_temps" \
        --output-dir "$IMP" -o libspinlock.noheap.a
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.bc" \
        "$IMP/root_temps/cjthreadspinlock.noheap.bc" -o "$IMP/linked.pre.bc"
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.opt.bc" \
        "$IMP/root_temps/cjthreadspinlock.noheap.opt.bc" -o "$IMP/linked.final.bc"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.pre.bc" -o "$IMP/linked.pre.ll"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.final.bc" -o "$IMP/linked.final.ll"
}

closure_args=(
    --pre-ll "$IMP/linked.pre.ll"
    --final-ll "$IMP/linked.final.ll"
    --manifest "$ROOT/test/parity/sched/cjthread_spinlock_noheap_manifest.txt"
    --object "$IMP/root_temps/cjthreadspinlock.noheap.o"
    --object "$IMP/sched_temps/rt.sched.o"
    --object "$IMP/CJThreadSpinLock.o"
)

run_closure_proof()
{
    python3 "$ROOT/test/parity/sched/cjthread_spinlock_closure.py" "${closure_args[@]}"
}

run_negative_self_tests()
{
    local mode negative_rc
    for mode in missing extra forbidden; do
        set +e
        python3 "$ROOT/test/parity/sched/cjthread_spinlock_closure.py" "${closure_args[@]}" \
            --mode "$mode" > "$IMP/negative.$mode.log" 2>&1
        negative_rc=$?
        set -e
        [[ $negative_rc -ne 0 ]] || fail "negative mode $mode returned zero"
        grep -Fq "CJTHREAD_SPINLOCK_CLOSURE FAIL mode=$mode" "$IMP/negative.$mode.log" ||
            fail "negative mode $mode did not execute the real analyzer"
        echo "CJTHREAD_SPINLOCK_NEGATIVE mode=$mode rc=$negative_rc status=PASS"
    done
}

build_cpp_oracle
check_cpp_oracle
build_production_and_probe
check_layout_calls_and_abi
build_closure_inputs
run_closure_proof
run_negative_self_tests

header_sha=$(sha256sum "$BASE_HEADER" | awk '{print $1}')
tree_sha=$(git -C "$ROOT" rev-parse 'HEAD^{tree}')
cpp_sha=$(sha256sum "$CPP_ORACLE" | awk '{print $1}')
cj_sha=$(sha256sum "$CJ_PROBE" | awk '{print $1}')
transcript_sha=$(sha256sum "$CJ_TRANSCRIPT" | awk '{print $1}')
platform_branches=$(rg -c '#ifdef MRT_MACOS|#if defined \(__ANDROID__\).*VOS_WORDSIZE.*MRT_HARDWARE_PLATFORM' \
    "$BASE_HEADER")
[[ "$platform_branches" == 2 ]] || fail "source selection predicate count mismatch"
echo "CJTHREAD_SPINLOCK_CPP_HEADER sha256=$header_sha source_predicates=2 source_representations=3 source_operation_definitions=12 exact_header=1 status=PASS"
echo "CJTHREAD_SPINLOCK_BRANCHES source=3 local_compiled=1 local_debts=3 machine_checked=true status=PASS"
echo "CJTHREAD_SPINLOCK_PLATFORM linux_x86_64=COMPILED_EXECUTED aarch64_linux=UNCOMPILED_BLOCKED Android_ARM32=UNCOMPILED_BLOCKED macOS_iOS=UNCOMPILED_BLOCKED Win64=UNCOMPILED_BLOCKED Hongmeng_OHOS=UNCOMPILED_BLOCKED other_targets=UNCOMPILED_BLOCKED blocker=CJTHREAD-SPINLOCK-PLATFORM-LAYOUT status=DEBT_RECORDED"
echo "CJTHREAD_SPINLOCK_EVIDENCE tree=$tree_sha cpp_oracle_sha256=$cpp_sha cj_probe_sha256=$cj_sha transcript_sha256=$transcript_sha status=PASS"
echo "CJTHREAD_SPINLOCK_STAGES cpp_header=1 cj_consumer=1 byte_layout=1 returns=4 blocking=1 counter_threads=8 handoff=1 destroy_once=1 bridge=1 pre_closure=1 final_closure=1 object_closure=1 negatives=3 status=PASS"
sed -n '1,9p' "$CJ_TRANSCRIPT"
disk_after=$(df -Pk / | awk 'NR==2 {print $4}')
used_kb=$((disk_before - disk_after))
[[ $used_kb -le 2097152 ]] || fail "temporary artifacts exceeded 2 GiB used_kb=$used_kb"
echo "CJTHREAD_SPINLOCK_DISK_AFTER available_kb=$disk_after used_kb=$used_kb"
echo "run_cjthread_spinlock_probe: PASS"
