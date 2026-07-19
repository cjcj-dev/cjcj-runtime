#!/usr/bin/env bash
# Fail-closed CJThread base.h Semaphore layout, behavior, ABI, and whole-closure parity.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
COMPILER_SOURCE=27b9b88c2a7bc68acfcc870e7b394404a8f6c356
COMPILER_SHA=d99659d1cc797eb179e349bdcff1c635086680fba6b9be5dac61e39eb570b44c
COMPILER_SIZE=98479472
TOOLCHAIN=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CJTHREAD_ROOT="$CPP_RUNTIME_ROOT/src/CJThread/src"
BASE_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/inner/base.h"
export CANGJIE_HOME="$TOOLCHAIN"
LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export PATH=/root/.cjv/bin:$PATH
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

fail()
{
    echo "run_cjthread_semaphore_probe: FAIL $*" >&2
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
    for tool in g++ objdump nm readelf ldd python3 cmp sha256sum stat git awk sed grep rg df \
        readlink find wc cp mktemp uname; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    [[ -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] ||
        fail "missing pinned nightly LLVM tools"
    for input in \
        "$BASE_HEADER" \
        "$CJTHREAD_ROOT/base/mid/include/macro_def.h" \
        "$ROOT/src/rt.sched/Semaphore.cj" \
        "$ROOT/src/rt.sched/CJthreadSpinLock.cj" \
        "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" \
        "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" \
        "$ROOT/test/parity/sched/cjthread_semaphore_ref.cpp" \
        "$ROOT/test/parity/sched/cjthread_semaphore_probe.cj" \
        "$ROOT/test/parity/sched/cjthread_semaphore_noheap_roots.cj" \
        "$ROOT/test/parity/sched/cjthread_semaphore_noheap_manifest.txt" \
        "$ROOT/test/parity/sched/cjthread_semaphore_closure.py" \
        "$ROOT/test/parity/base/atomicspinlock_closure.py"; do
        [[ -f "$input" ]] || fail "missing input $input"
    done
    [[ $(find "$ROOT/rt0/os" -type f -name CJThreadSemaphore.cpp -print | wc -l) -eq 1 ]] ||
        fail "unexpected CJThread semaphore bridge source count"
}

require_inputs
check_compiler
echo "CJTHREAD_SEMAPHORE_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"
disk_before=$(df -Pk / | awk 'NR==2 {print $4}')
echo "CJTHREAD_SEMAPHORE_DISK_BEFORE available_kb=$disk_before"

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_cjthread_semaphore_probe.XXXXXX")
trap 'rm -rf "$IMP"' EXIT
ulimit -c 0
mkdir -p "$IMP/sched_temps" "$IMP/root_temps" "$IMP/cjthreadsemaphore.noheap"

CPP_ORACLE="$IMP/cjthread_semaphore_oracle"
CJ_PROBE="$IMP/cjthread_semaphore_probe"
CPP_TRANSCRIPT="$IMP/cpp.transcript"
CJ_TRANSCRIPT="$IMP/cj.transcript"
CPP_INCLUDE=(
    -I "$CJTHREAD_ROOT/base/mid/include"
    -I "$CJTHREAD_ROOT/runtime/schedule/include/inner"
)
CPP_SELECT=(-DMRT_HARDWARE_PLATFORM=MRT_X86 -DVOS_WORDSIZE=64)
WRAP_OPTIONS=(
    --wrap=sem_init
    --wrap=sem_wait
    --wrap=sem_post
    --wrap=sem_destroy
)

build_cpp_oracle()
{
    g++ -std=c++14 -O2 -Wall -Wextra -Werror -DCJTHREAD_SEMAPHORE_ORACLE \
        "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
        "$ROOT/test/parity/sched/cjthread_semaphore_ref.cpp" -pthread \
        -Wl,"${WRAP_OPTIONS[0]}" -Wl,"${WRAP_OPTIONS[1]}" \
        -Wl,"${WRAP_OPTIONS[2]}" -Wl,"${WRAP_OPTIONS[3]}" -o "$CPP_ORACLE"
    "$CPP_ORACLE" > "$CPP_TRANSCRIPT"
    [[ -s "$CPP_TRANSCRIPT" ]] || fail "empty C++ oracle transcript"
}

check_cpp_oracle()
{
    [[ $(wc -l < "$CPP_TRANSCRIPT") -eq 10 ]] || fail "unexpected C++ transcript record count"
    grep -Fxq 'CJTHREAD_SEMAPHORE_SEM_T sizeof=32 align=8' "$CPP_TRANSCRIPT" ||
        fail "sem_t layout mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_LAYOUT sizeof=32 align=8 sem=0' "$CPP_TRANSCRIPT" ||
        fail "Semaphore layout mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_BYTES init=0000000000000000000000000000000000000000000000000000000000000000 blocked=0000000001000000000000000000000000000000000000000000000000000000 consumed=0000000000000000000000000000000000000000000000000000000000000000 destroy=0000000000000000000000000000000000000000000000000000000000000000' "$CPP_TRANSCRIPT" ||
        fail "complete semaphore object bytes mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_RETURNS init=0 wait=0 wait_eintr=-1 wait_no_intr=0 post=0 destroy=0' \
        "$CPP_TRANSCRIPT" || fail "native return values mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_ERRNO init=0 wait=0 wait_eintr=4 wait_no_intr=4 post=0 destroy=0' \
        "$CPP_TRANSCRIPT" || fail "native errno observations mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_BLOCK blocked_before_post=1 completed_after_post=1 status=PASS' \
        "$CPP_TRANSCRIPT" || fail "blocking/wakeup mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_NOINTR real_eintr=1 retries=1 blocked_before_post=1 completed_after_post=1 non_eintr_defined_trigger=none status=PASS' \
        "$CPP_TRANSCRIPT" || fail "WaitNoIntr EINTR retry mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_COUNTER threads=8 iterations=4096 expected=32768 actual=32768 status=PASS' \
        "$CPP_TRANSCRIPT" || fail "deterministic counter mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_HANDOFF payload=1511506142 observed=1511506142 status=PASS' \
        "$CPP_TRANSCRIPT" || fail "release/acquire handoff mismatch"
    grep -Fxq 'CJTHREAD_SEMAPHORE_CALLS init=1 wait=32774 wait_returns=32774 wait_eintr=2 post=32772 destroy=1 pshared=0 value=0 address_mismatches=0 destroy_after_users=true' \
        "$CPP_TRANSCRIPT" || fail "native call/address/argument counts mismatch"
}

build_production_and_probe()
{
    run_cjc --package "$ROOT/src/rt.sched" --output-type=staticlib -O2 \
        --int-overflow wrapping --save-temps "$IMP/sched_temps" \
        --output-dir "$IMP" -o librt.sched.a
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" -o "$IMP/CJThreadSemaphore.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" -o "$IMP/CJThreadSpinLock.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
        -c "$ROOT/test/parity/sched/cjthread_semaphore_ref.cpp" -o "$IMP/cjthread_semaphore_ref.o"
    local link_args=()
    local option
    for option in "${WRAP_OPTIONS[@]}"; do
        link_args+=("--link-option=$option")
    done
    run_cjc "$ROOT/test/parity/sched/cjthread_semaphore_probe.cj" \
        --import-path "$IMP" --int-overflow wrapping "$IMP/librt.sched.a" \
        "$IMP/CJThreadSemaphore.o" "$IMP/CJThreadSpinLock.o" "$IMP/cjthread_semaphore_ref.o" \
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
        sed -n '1,14p' "$CPP_TRANSCRIPT" >&2
        echo "Cangjie transcript:" >&2
        sed -n '1,14p' "$CJ_TRANSCRIPT" >&2
        fail "C++/Cangjie transcript byte mismatch"
    }
}

check_layout_calls_and_abi()
{
    "$LLVM_BIN/llvm-dis" "$IMP/sched_temps/rt.sched.opt.bc" -o "$IMP/sched.final.ll"
    grep -Fxq '%"record.rt.sched:Semaphore" = type { [4 x i64] }' "$IMP/sched.final.ll" ||
        fail "Cangjie inline record is not exactly four UInt64 values"
    [[ $(grep -Fc '@When[os == "Linux" && arch == "x86_64"]' \
        "$ROOT/src/rt.sched/Semaphore.cj") -eq 11 ]] || fail "local compiled branch count mismatch"
    [[ $(grep -Fc 'CJTHREAD-SEMAPHORE-DARWIN-LAYOUT:' \
        "$ROOT/src/rt.sched/Semaphore.cj") -eq 1 ]] || fail "Darwin debt count mismatch"
    [[ $(grep -Fc 'CJTHREAD-SEMAPHORE-INLINE-LAYOUT:' \
        "$ROOT/src/rt.sched/Semaphore.cj") -eq 1 ]] || fail "non-Mac platform debt count mismatch"
    [[ $(grep -Fxc 'struct Semaphore {' "$BASE_HEADER") -eq 2 ]] ||
        fail "C++ representation branch count mismatch"
    local source_definitions=0 operation
    for operation in SemaphoreInit SemaphoreWait SemaphoreWaitNoIntr SemaphorePost SemaphoreDestroy; do
        [[ $(grep -Ec "^static inline int ${operation}\\(" "$BASE_HEADER") -eq 2 ]] ||
            fail "C++ operation branch count mismatch operation=$operation"
        source_definitions=$((source_definitions + 2))
        [[ $(grep -Ec "^public func ${operation}\\(" "$ROOT/src/rt.sched/Semaphore.cj") -eq 1 ]] ||
            fail "Cangjie production operation count mismatch operation=$operation"
    done
    [[ $source_definitions -eq 10 ]] || fail "source function definition total mismatch"
    ! rg -q 'TryWait|Timed|Reset|RAII|Scoped|Guard|malloc|calloc|realloc|new |throw|catch|ArrayList|HashMap|HashSet' \
        "$ROOT/src/rt.sched/Semaphore.cj" "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" ||
        fail "invented operation, ownership, allocation, or failure policy present"

    local operation_name native_defs sched_relocs executable_defs hidden_defs
    for operation_name in init wait wait_no_intr post destroy; do
        [[ $(grep -Fc "func cj_cjthread_semaphore_${operation_name}(" \
            "$ROOT/src/rt.sched/Semaphore.cj") -eq 1 ]] ||
            fail "Cangjie foreign signature count mismatch operation=$operation_name"
        [[ $(grep -Fc "int32_t cj_cjthread_semaphore_${operation_name}(" \
            "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp") -eq 1 ]] ||
            fail "native bridge signature count mismatch operation=$operation_name"
        native_defs=$(nm -g --defined-only "$IMP/CJThreadSemaphore.o" |
            awk -v symbol="cj_cjthread_semaphore_${operation_name}" '$3 == symbol {++n} END {print n+0}')
        sched_relocs=$(objdump -r "$IMP/sched_temps/rt.sched.o" |
            awk -v symbol="cj_cjthread_semaphore_${operation_name}" \
                '$3 ~ ("^" symbol "(-0x[0-9A-Fa-f]+)?$") {++n} END {print n+0}')
        executable_defs=$(nm -g --defined-only "$CJ_PROBE" |
            awk -v symbol="cj_cjthread_semaphore_${operation_name}" '$3 == symbol {++n} END {print n+0}')
        hidden_defs=$(readelf -Ws "$IMP/CJThreadSemaphore.o" |
            awk -v symbol="cj_cjthread_semaphore_${operation_name}" \
                '$5 == "GLOBAL" && $6 == "HIDDEN" && $8 == symbol {++n} END {print n+0}')
        [[ $native_defs -eq 1 && $sched_relocs -eq 1 && $executable_defs -eq 1 && $hidden_defs -eq 1 ]] ||
            fail "bridge edge mismatch operation=$operation_name defs=$native_defs sched_relocs=$sched_relocs executable_defs=$executable_defs hidden=$hidden_defs"
    done
    [[ $(objdump -r "$IMP/CJThreadSemaphore.o" | grep -Ec 'R_X86_64_(PLT32|PC32)[[:space:]]+sem_init') -eq 1 &&
       $(objdump -r "$IMP/CJThreadSemaphore.o" | grep -Ec 'R_X86_64_(PLT32|PC32)[[:space:]]+sem_wait') -eq 2 &&
       $(objdump -r "$IMP/CJThreadSemaphore.o" | grep -Ec 'R_X86_64_(PLT32|PC32)[[:space:]]+__errno_location') -eq 1 &&
       $(objdump -r "$IMP/CJThreadSemaphore.o" | grep -Ec 'R_X86_64_(PLT32|PC32)[[:space:]]+sem_post') -eq 1 &&
       $(objdump -r "$IMP/CJThreadSemaphore.o" | grep -Ec 'R_X86_64_(PLT32|PC32)[[:space:]]+sem_destroy') -eq 1 ]] ||
        fail "native source relocation multiplicity mismatch"
    for operation in Init Wait WaitNoIntr Post Destroy; do
        [[ $(nm -g --defined-only "$CJ_PROBE" |
            awk -v symbol="CJRT_CJthreadSemaphore${operation}" '$3 == symbol {++n} END {print n+0}') -eq 1 ]] ||
            fail "test C entry count mismatch operation=$operation"
    done
    for symbol in sem_init sem_wait sem_post sem_destroy __errno_location; do
        objdump -T "$CJ_PROBE" | grep -Eq "\\*UND\\*.*GLIBC_.*${symbol}$" ||
            fail "real glibc edge absent symbol=$symbol"
    done
    ldd "$CJ_PROBE" | grep -Fq 'libc.so.6' || fail "real libc linkage absent"
    ! rg -q 'CJRT_CJthreadSemaphore|cj_cjthread_semaphore_' "$ROOT/contract" ||
        fail "test/internal semaphore symbol leaked into production contract manifest"
    echo "CJTHREAD_SEMAPHORE_LAYOUT_GATE cpp_sem_t=32/8 cpp_value=32/8/0 cj_value=32/8/0 complete_states=4 status=PASS"
    echo "CJTHREAD_SEMAPHORE_BRIDGE cj_signatures=5 native_definitions=5 native_relocations=6 sched_relocations=5 executable_definitions=5 hidden=5 original_address=1 status=PASS"
    echo "CJTHREAD_SEMAPHORE_ABI public_inventory_delta=0 test_symbols_manifested=0 glibc_edges=5 pthread_link_option=1 status=PASS"
}

build_closure_inputs()
{
    cp "$ROOT/test/parity/sched/cjthread_semaphore_noheap_roots.cj" \
        "$IMP/cjthreadsemaphore.noheap/Roots.cj"
    run_cjc --package "$IMP/cjthreadsemaphore.noheap" --output-type=staticlib -O2 \
        --int-overflow wrapping --import-path "$IMP" --save-temps "$IMP/root_temps" \
        --output-dir "$IMP" -o libsemaphore.noheap.a
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.bc" \
        "$IMP/root_temps/cjthreadsemaphore.noheap.bc" -o "$IMP/linked.pre.bc"
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.opt.bc" \
        "$IMP/root_temps/cjthreadsemaphore.noheap.opt.bc" -o "$IMP/linked.final.bc"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.pre.bc" -o "$IMP/linked.pre.ll"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.final.bc" -o "$IMP/linked.final.ll"
}

closure_args=(
    --pre-ll "$IMP/linked.pre.ll"
    --final-ll "$IMP/linked.final.ll"
    --manifest "$ROOT/test/parity/sched/cjthread_semaphore_noheap_manifest.txt"
    --object "$IMP/root_temps/cjthreadsemaphore.noheap.o"
    --object "$IMP/sched_temps/rt.sched.o"
    --object "$IMP/CJThreadSemaphore.o"
)

run_closure_proof()
{
    python3 "$ROOT/test/parity/sched/cjthread_semaphore_closure.py" "${closure_args[@]}"
}

run_negative_self_tests()
{
    local mode negative_rc
    for mode in missing extra forbidden; do
        set +e
        python3 "$ROOT/test/parity/sched/cjthread_semaphore_closure.py" "${closure_args[@]}" \
            --mode "$mode" > "$IMP/negative.$mode.log" 2>&1
        negative_rc=$?
        set -e
        [[ $negative_rc -ne 0 ]] || fail "negative mode $mode returned zero"
        grep -Fq "CJTHREAD_SEMAPHORE_CLOSURE FAIL mode=$mode" "$IMP/negative.$mode.log" ||
            fail "negative mode $mode did not execute the real analyzer"
        echo "CJTHREAD_SEMAPHORE_NEGATIVE mode=$mode rc=$negative_rc status=PASS"
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
platform_predicates=$(rg -c '^#ifdef MRT_MACOS$' "$BASE_HEADER")
[[ "$platform_predicates" == 1 ]] || fail "source selection predicate count mismatch"
echo "CJTHREAD_SEMAPHORE_CPP_HEADER sha256=$header_sha source_predicates=1 source_representations=2 source_operation_definitions=10 exact_header=1 status=PASS"
echo "CJTHREAD_SEMAPHORE_BRANCHES source=2 local_compiled=1 local_debts=2 machine_checked=true status=PASS"
echo "CJTHREAD_SEMAPHORE_PLATFORM linux_x86_64=COMPILED_EXECUTED aarch64_linux=UNCOMPILED_BLOCKED Android_ARM32_ARM64=UNCOMPILED_BLOCKED macOS_iOS=UNCOMPILED_BLOCKED Win64=UNCOMPILED_BLOCKED Hongmeng_OHOS=UNCOMPILED_BLOCKED other_targets=UNCOMPILED_BLOCKED blockers=CJTHREAD-SEMAPHORE-INLINE-LAYOUT,CJTHREAD-SEMAPHORE-DARWIN-LAYOUT status=DEBT_RECORDED"
echo "CJTHREAD_SEMAPHORE_EVIDENCE tree=$tree_sha cpp_oracle_sha256=$cpp_sha cj_probe_sha256=$cj_sha transcript_sha256=$transcript_sha status=PASS"
echo "CJTHREAD_SEMAPHORE_STAGES cpp_header=1 cj_consumer=1 byte_layout=1 returns=6 blocking=1 eintr_return=1 eintr_retry=1 counter_threads=8 handoff=1 destroy_once=1 bridge=1 pre_closure=1 final_closure=1 object_closure=1 negatives=3 status=PASS"
sed -n '1,10p' "$CJ_TRANSCRIPT"
disk_after=$(df -Pk / | awk 'NR==2 {print $4}')
used_kb=$((disk_before - disk_after))
[[ $used_kb -le 2097152 ]] || fail "temporary artifacts exceeded 2 GiB used_kb=$used_kb"
echo "CJTHREAD_SEMAPHORE_DISK_AFTER available_kb=$disk_after used_kb=$used_kb"
echo "run_cjthread_semaphore_probe: PASS"
