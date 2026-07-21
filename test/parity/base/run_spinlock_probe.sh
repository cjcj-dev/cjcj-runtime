#!/usr/bin/env bash
# Fail-closed partial SpinLock parity and deterministic-destruction boundary proof.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
TOOLCHAIN=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
export CANGJIE_HOME="$TOOLCHAIN"
LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
export PATH=/root/.cjv/bin:$PATH
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

fail()
{
    echo "run_spinlock_probe: FAIL $*" >&2
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
    for tool in g++ objdump nm readelf python3 cmp sha256sum stat git awk sed grep rg df ldd; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    [[ -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] ||
        fail "missing pinned nightly LLVM tools"
    for input in \
        "$CPP_RUNTIME_ROOT/src/Base/SpinLock.h" \
        "$CPP_RUNTIME_ROOT/src/Base/Macros.h" \
        "$ROOT/src/rt.base/SpinLock.cj" \
        "$ROOT/rt0/os/Linux/SpinLock.cpp" \
        "$ROOT/rt0/os/Linux/Atomic.cpp" \
        "$ROOT/rt0/os/Linux/Panic.cpp" \
        "$ROOT/test/parity/base/spinlock_ref.cpp" \
        "$ROOT/test/parity/base/spinlock_probe.cj" \
        "$ROOT/test/parity/base/spinlock_lifetime_probe.cj" \
        "$ROOT/test/parity/base/spinlock_noheap_roots.cj" \
        "$ROOT/test/parity/base/spinlock_noheap_manifest.txt" \
        "$ROOT/test/parity/base/spinlock_closure.py" \
        "$ROOT/test/parity/base/atomicspinlock_closure.py"; do
        [[ -f "$input" ]] || fail "missing input $input"
    done
    [[ $(find "$ROOT/rt0/os" -type f -name SpinLock.cpp -print | wc -l) -eq 1 ]] ||
        fail "unexpected SpinLock bridge source selection count"
}

require_inputs
check_compiler
echo "SPINLOCK_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"
echo "SPINLOCK_DISK_BEFORE available_kb=$(df -Pk / | awk 'NR==2 {print $4}')"

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_spinlock_probe.XXXXXX")
trap 'rm -rf "$IMP"' EXIT
ulimit -c 0
mkdir -p "$IMP/base_temps" "$IMP/root_temps" "$IMP/spinlock.noheap"

CPP_ORACLE="$IMP/spinlock_oracle"
CJ_PROBE="$IMP/spinlock_probe"
CPP_FULL="$IMP/cpp.full"
CPP_TRANSCRIPT="$IMP/cpp.partial"
CJ_TRANSCRIPT="$IMP/cj.partial"
WRAP_OPTIONS=(
    --wrap=pthread_spin_init
    --wrap=pthread_spin_destroy
    --wrap=pthread_spin_lock
    --wrap=pthread_spin_unlock
    --wrap=pthread_spin_trylock
)

build_cpp_oracle()
{
    g++ -std=c++14 -O2 -Wall -Wextra -Werror -Wno-invalid-offsetof -DSPINLOCK_ORACLE \
        -I "$CPP_RUNTIME_ROOT/src" "$ROOT/test/parity/base/spinlock_ref.cpp" -pthread \
        -Wl,"${WRAP_OPTIONS[0]}" -Wl,"${WRAP_OPTIONS[1]}" -Wl,"${WRAP_OPTIONS[2]}" \
        -Wl,"${WRAP_OPTIONS[3]}" -Wl,"${WRAP_OPTIONS[4]}" -o "$CPP_ORACLE"
    "$CPP_ORACLE" > "$CPP_FULL"
    "$CPP_ORACLE" --partial > "$CPP_TRANSCRIPT"
    [[ -s "$CPP_FULL" && -s "$CPP_TRANSCRIPT" ]] || fail "empty C++ oracle transcript"
}

check_full_cpp_oracle()
{
    grep -Fxq 'SPINLOCK_PTHREAD sizeof=4 align=4 is_int=false remove_cv_is_int=true volatile=true' \
        "$CPP_FULL" || fail "pthread_spinlock_t identity mismatch"
    grep -Fxq 'SPINLOCK_LAYOUT sizeof=4 align=4 spinlock=0' "$CPP_FULL" ||
        fail "SpinLock C++ layout mismatch"
    grep -Fxq 'SCOPED_SPINLOCK_LAYOUT sizeof=8 align=8 spinLock=0' "$CPP_FULL" ||
        fail "ScopedEnterSpinLock C++ layout mismatch"
    grep -Fxq 'SPINLOCK_BYTES init=01000000 held_lock=00000000 failed_try=00000000 unlock=01000000 successful_try=00000000 final_unlock=01000000 destroy=01000000' \
        "$CPP_FULL" || fail "complete C++ object bytes mismatch"
    grep -Fxq 'SPINLOCK_CALLS init=1 destroy=1 lock=1 unlock=2 try=2' "$CPP_FULL" ||
        fail "C++ pthread call counts mismatch"
    grep -Fxq 'SCOPED_SPINLOCK_RAII lexical=true early_return=true unwind=true lock_delta=3 unlock_delta=6 status=PASS' \
        "$CPP_FULL" || fail "C++ guard lifetime behavior mismatch"
    sed -n '1,20p' "$CPP_FULL"
    echo "SPINLOCK_CPP_ORACLE pthread_size=4 pthread_align=4 spin_size=4 spin_align=4 spin_offset=0 guard_size=8 guard_align=8 guard_offset=0 states=7 status=PASS"
}

check_lifetime_boundary()
{
    local lifetime_rc
    check_compiler
    set +e
    "$SELFHOST_CJC" "$ROOT/test/parity/base/spinlock_lifetime_probe.cj" \
        -o "$IMP/spinlock_lifetime_probe" > "$IMP/lifetime.out" 2> "$IMP/lifetime.err"
    lifetime_rc=$?
    set -e
    [[ $lifetime_rc -eq 1 ]] || fail "inline finalizer probe rc=$lifetime_rc expected=1"
    [[ $(grep -Fc 'unexpected finalizer in struct body' "$IMP/lifetime.err") -eq 2 ]] ||
        fail "inline lock/guard finalizer diagnostics mismatch"
    [[ ! -e "$IMP/spinlock_lifetime_probe" ]] || fail "invalid lifetime probe produced executable"
    echo "SPINLOCK_LIFETIME_PROBE rc=$lifetime_rc inline_lock_finalizer=REJECTED inline_guard_finalizer=REJECTED gc_finalizer_substitution=FORBIDDEN status=BLOCKED"
}

build_base_and_native()
{
    run_cjc --package "$ROOT/src/rt.base" --output-type=staticlib \
        -O2 -Woff unused --int-overflow wrapping --save-temps "$IMP/base_temps" \
        --output-dir "$IMP" -o librt.base.a
    [[ -s "$IMP/librt.base.a" && -s "$IMP/base_temps/rt.base.o" ]] ||
        fail "rt.base build artifacts absent"
    local source
    for source in SpinLock Atomic Panic; do
        g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
            -c "$ROOT/rt0/os/Linux/$source.cpp" -o "$IMP/$source.o"
    done
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -I "$CPP_RUNTIME_ROOT/src" -c "$ROOT/test/parity/base/spinlock_ref.cpp" \
        -o "$IMP/spinlock_ref.o"
}

build_cangjie_probe()
{
    local link_args=()
    local option
    for option in "${WRAP_OPTIONS[@]}"; do
        link_args+=("--link-option=$option")
    done
    run_cjc "$ROOT/test/parity/base/spinlock_probe.cj" \
        --import-path "$IMP" --int-overflow wrapping \
        "$IMP/librt.base.a" "$IMP/SpinLock.o" "$IMP/Atomic.o" "$IMP/Panic.o" \
        "$IMP/spinlock_ref.o" --link-option=-lstdc++ --link-option=-lpthread \
        --link-option=-lgcc_s "${link_args[@]}" -o "$CJ_PROBE"
    [[ -x "$CJ_PROBE" ]] || fail "Cangjie probe executable absent"
    local resolved_runtime
    resolved_runtime=$(ldd "$CJ_PROBE" | awk '/libcangjie-runtime\.so/{print $3; exit}')
    [[ "$(readlink -f "$resolved_runtime")" == "$(readlink -f "$SELFHOST_RT/libcangjie-runtime.so")" ]] ||
        fail "Cangjie probe runtime identity mismatch"
    "$CJ_PROBE" > "$CJ_TRANSCRIPT"
    [[ -s "$CJ_TRANSCRIPT" ]] || fail "empty Cangjie transcript"
}

check_partial_parity()
{
    cmp -s "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT" || {
        echo "C++ partial transcript:" >&2
        sed -n '1,20p' "$CPP_TRANSCRIPT" >&2
        echo "Cangjie partial transcript:" >&2
        sed -n '1,20p' "$CJ_TRANSCRIPT" >&2
        fail "partial transcript byte mismatch"
    }
    [[ $(wc -l < "$CJ_TRANSCRIPT") -eq 8 ]] || fail "unexpected partial record count"
    grep -Fxq 'SPINLOCK_CALLS init=1 destroy=0 lock=1 unlock=2 try=2' "$CJ_TRANSCRIPT" ||
        fail "partial pthread call counts mismatch"
    grep -Fxq 'SPINLOCK_BLOCK pre_release=1 acquired_before_release=0 post_release=1 acquired_after_release=1 status=PASS' \
        "$CJ_TRANSCRIPT" || fail "blocking acquisition mismatch"
    grep -Fxq 'SPINLOCK_COUNTER threads=4 iterations=4096 expected=16384 actual=16384 final=1 status=PASS' \
        "$CJ_TRANSCRIPT" || fail "critical-section counter mismatch"
    grep -Fxq 'SPINLOCK_HANDOFF payload=1511506142 observed=1511506142 final=1 status=PASS' \
        "$CJ_TRANSCRIPT" || fail "release/acquire handoff mismatch"
    sed -n '1,20p' "$CJ_TRANSCRIPT"
    echo "SPINLOCK_PARTIAL_PARITY records=8 bytes=$(stat -c %s "$CJ_TRANSCRIPT") cmp=identical completed=constructor,Lock,Unlock,TryLock status=PASS"
}

check_bridge_and_layout()
{
    local operation pthread_target native_defs native_relocs base_relocs executable_defs
    "$LLVM_BIN/llvm-dis" "$IMP/base_temps/rt.base.opt.bc" -o "$IMP/base.final.ll"
    grep -Fxq '%"record.rt.base:SpinLock" = type { i32 }' "$IMP/base.final.ll" ||
        fail "Cangjie inline SpinLock is not one Int32"
    ! rg -q 'cj_pthread_spin_destroy' "$ROOT/src/rt.base/SpinLock.cj" "$ROOT/rt0/os/Linux/SpinLock.cpp" ||
        fail "invented explicit destroy surface present"
    for operation in init lock unlock trylock; do
        pthread_target="pthread_spin_$operation"
        native_defs=$(nm -g --defined-only "$IMP/SpinLock.o" |
            awk -v symbol="cj_pthread_spin_$operation" '$3 == symbol {++n} END {print n+0}')
        native_relocs=$(objdump -r "$IMP/SpinLock.o" |
            awk -v symbol="$pthread_target" '$3 ~ ("^" symbol "(-0x[0-9A-Fa-f]+)?$") {++n} END {print n+0}')
        base_relocs=$(objdump -r "$IMP/base_temps/rt.base.o" |
            awk -v symbol="cj_pthread_spin_$operation" '$3 ~ ("^" symbol "(-0x[0-9A-Fa-f]+)?$") {++n} END {print n+0}')
        executable_defs=$(nm -g --defined-only "$CJ_PROBE" |
            awk -v symbol="cj_pthread_spin_$operation" '$3 == symbol {++n} END {print n+0}')
        [[ $native_defs -eq 1 && $native_relocs -eq 1 && $base_relocs -eq 1 && $executable_defs -eq 1 ]] ||
            fail "bridge multiplicity mismatch operation=$operation native_defs=$native_defs native_relocs=$native_relocs base_relocs=$base_relocs executable_defs=$executable_defs"
    done
    for operation in Init Lock Unlock TryLock; do
        [[ $(nm -g --defined-only "$CJ_PROBE" |
            awk -v symbol="CJRT_SpinLock$operation" '$3 == symbol {++n} END {print n+0}') -eq 1 ]] ||
            fail "missing Cangjie test entry CJRT_SpinLock$operation"
    done
    echo "SPINLOCK_LAYOUT_GATE cpp_pthread=4/4 cpp_spin=4/4/0 cj_spin=4/4/0 complete_states=6 status=PASS"
    echo "SPINLOCK_BRIDGE cj_signatures=4 native_definitions=4 base_relocations=4 pthread_relocations=4 executable_definitions=4 original_address=1 status=PASS"
}

build_closure_inputs()
{
    cp "$ROOT/test/parity/base/spinlock_noheap_roots.cj" "$IMP/spinlock.noheap/Roots.cj"
    run_cjc --package "$IMP/spinlock.noheap" --output-type=staticlib \
        -O2 --int-overflow wrapping --import-path "$IMP" --save-temps "$IMP/root_temps" \
        --output-dir "$IMP" -o libspinlock.noheap.a
    [[ -s "$IMP/root_temps/spinlock.noheap.o" ]] || fail "root object absent"
    "$LLVM_BIN/llvm-link" "$IMP/base_temps/rt.base.bc" \
        "$IMP/root_temps/spinlock.noheap.bc" -o "$IMP/linked.pre.bc"
    "$LLVM_BIN/llvm-link" "$IMP/base_temps/rt.base.opt.bc" \
        "$IMP/root_temps/spinlock.noheap.opt.bc" -o "$IMP/linked.final.bc"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.pre.bc" -o "$IMP/linked.pre.ll"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.final.bc" -o "$IMP/linked.final.ll"
}

closure_args=(
    --pre-ll "$IMP/linked.pre.ll"
    --final-ll "$IMP/linked.final.ll"
    --manifest "$ROOT/test/parity/base/spinlock_noheap_manifest.txt"
    --object "$IMP/root_temps/spinlock.noheap.o"
    --object "$IMP/base_temps/rt.base.o"
    --object "$IMP/SpinLock.o"
)

run_closure_proof()
{
    python3 "$ROOT/test/parity/base/spinlock_closure.py" "${closure_args[@]}"
}

run_negative_self_tests()
{
    local mode negative_rc
    for mode in missing extra forbidden; do
        set +e
        python3 "$ROOT/test/parity/base/spinlock_closure.py" "${closure_args[@]}" \
            --mode "$mode" > "$IMP/negative.$mode.log" 2>&1
        negative_rc=$?
        set -e
        [[ $negative_rc -ne 0 ]] || fail "negative mode $mode returned zero"
        grep -Fq "SPINLOCK_CLOSURE FAIL mode=$mode" "$IMP/negative.$mode.log" ||
            fail "negative mode $mode did not execute real analyzer"
        echo "SPINLOCK_NEGATIVE mode=$mode rc=$negative_rc status=PASS"
    done
}

build_cpp_oracle
check_full_cpp_oracle
check_lifetime_boundary
build_base_and_native
build_cangjie_probe
check_partial_parity
check_bridge_and_layout
build_closure_inputs
run_closure_proof
run_negative_self_tests

header_sha=$(sha256sum "$CPP_RUNTIME_ROOT/src/Base/SpinLock.h" | awk '{print $1}')
tree_sha=$(git -C "$ROOT" rev-parse 'HEAD^{tree}')
cpp_sha=$(sha256sum "$CPP_ORACLE" | awk '{print $1}')
cj_sha=$(sha256sum "$CJ_PROBE" | awk '{print $1}')
transcript_sha=$(sha256sum "$CJ_TRANSCRIPT" | awk '{print $1}')
platform_branches=$(rg -n '_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif' \
    "$CPP_RUNTIME_ROOT/src/Base/SpinLock.h" || true)
[[ -z "$platform_branches" ]] || fail "unexpected C++ header platform branch"
echo "SPINLOCK_CPP_HEADER sha256=$header_sha platform_conditionals=0 exact_header=1 status=PASS"
echo "SPINLOCK_COPY_SURFACE cpp_copy_constructor=deleted cpp_assignment=deleted cangjie_compile_time_deletion=unavailable clone_api=0 production_test_lock_copies=0 status=DEBT_RECORDED"
echo "SPINLOCK_PLATFORM linux_x86_64=EXECUTED aarch64_linux=UNEXECUTED arm32_linux=UNEXECUTED macOS_iOS=UNEXECUTED Win64=UNEXECUTED Hongmeng_OHOS=UNEXECUTED other_targets=UNEXECUTED status=DEBT_RECORDED"
echo "SPINLOCK_EVIDENCE tree=$tree_sha cpp_oracle_sha256=$cpp_sha cj_probe_sha256=$cj_sha transcript_sha256=$transcript_sha status=PASS"
echo "SPINLOCK_STAGES full_cpp_header=1 lifetime_compile_fail=1 cj_consumer=1 byte_layout=1 state_machine=1 blocking=1 counter=1 handoff=1 bridge=1 pre_closure=1 final_closure=1 object_closure=1 negatives=3 status=PASS"
echo "SPINLOCK_UNPORTED lines=20,33-39 symbols=SpinLock::~SpinLock,ScopedEnterSpinLock blocker=SCOPED-SPINLOCK-DETERMINISTIC-DESTRUCTION status=BLOCKED"
echo "SPINLOCK_DISK_AFTER available_kb=$(df -Pk / | awk 'NR==2 {print $4}')"
echo "run_spinlock_probe: BLOCKED SCOPED-SPINLOCK-DETERMINISTIC-DESTRUCTION unported=SpinLock.h:20,33-39"
echo "run_spinlock_probe: PASS scope=SpinLock.h:18,22,24,26,28-30 completed=constructor,Lock,Unlock,TryLock"
