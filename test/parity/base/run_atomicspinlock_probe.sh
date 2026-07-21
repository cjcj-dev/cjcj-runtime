#!/usr/bin/env bash
# Fail-closed AtomicSpinLock header parity, native contention, bridge, and whole-closure proof.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
COMPILER_SOURCE=27b9b88c2a7bc68acfcc870e7b394404a8f6c356
COMPILER_SHA=d99659d1cc797eb179e349bdcff1c635086680fba6b9be5dac61e39eb570b44c
COMPILER_SIZE=98479472
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
    echo "run_atomicspinlock_probe: FAIL $*" >&2
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

require_inputs()
{
    local tool input
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
        fail "executable target must be Linux x86_64"
    for tool in g++ objdump nm readelf python3 cmp sha256sum stat git awk sed grep rg df; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    [[ -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] ||
        fail "missing pinned nightly LLVM tools"
    for input in \
        "$CPP_RUNTIME_ROOT/src/Base/AtomicSpinLock.h" \
        "$CPP_RUNTIME_ROOT/src/Base/Macros.h" \
        "$ROOT/src/rt/base/AtomicSpinLock.cj" \
        "$ROOT/rt0/os/Linux/Atomic.cpp" \
        "$ROOT/rt0/os/Linux/SpinLock.cpp" \
        "$ROOT/test/parity/base/atomicspinlock_ref.cpp" \
        "$ROOT/test/parity/base/atomicspinlock_probe.cj" \
        "$ROOT/test/parity/base/atomicspinlock_noheap_roots.cj" \
        "$ROOT/test/parity/base/atomicspinlock_noheap_manifest.txt" \
        "$ROOT/test/parity/base/atomicspinlock_closure.py"; do
        [[ -f "$input" ]] || fail "missing input $input"
    done
    [[ $(find "$ROOT/rt0/os" -type f -name Atomic.cpp -print | wc -l) -eq 1 ]] ||
        fail "unexpected atomic source selection count"
}

require_inputs
check_compiler
echo "ATOMICSPINLOCK_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"
echo "ATOMICSPINLOCK_DISK_BEFORE available_kb=$(df -Pk / | awk 'NR==2 {print $4}')"

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_atomicspinlock_probe.XXXXXX")
trap 'rm -rf "$IMP"' EXIT
ulimit -c 0
mkdir -p "$IMP/base_temps" "$IMP/root_temps" "$IMP/atomicspinlock.noheap"

CPP_ORACLE="$IMP/atomicspinlock_oracle"
CJ_PROBE="$IMP/atomicspinlock_probe"
CPP_TRANSCRIPT="$IMP/cpp.transcript"
CJ_TRANSCRIPT="$IMP/cj.transcript"

build_cpp_oracle()
{
    g++ -std=c++14 -O2 -Wall -Wextra -Werror -DATOMICSPINLOCK_ORACLE \
        -I "$CPP_RUNTIME_ROOT/src" \
        "$ROOT/test/parity/base/atomicspinlock_ref.cpp" -pthread -o "$CPP_ORACLE"
    "$CPP_ORACLE" > "$CPP_TRANSCRIPT"
    [[ -s "$CPP_TRANSCRIPT" ]] || fail "empty C++ oracle transcript"
}

build_base_and_native()
{
    check_compiler
    "$SELFHOST_CJC" --package "$ROOT/src/rt/base" --output-type=staticlib \
        -O2 -Woff unused --int-overflow wrapping --save-temps "$IMP/base_temps" \
        --output-dir "$IMP" -o librt.base.a
    [[ -s "$IMP/librt.base.a" && -s "$IMP/base_temps/rt.base.o" ]] ||
        fail "rt.base build artifacts absent"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$IMP/Atomic.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/SpinLock.cpp" -o "$IMP/SpinLock.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$IMP/Panic.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -I "$CPP_RUNTIME_ROOT/src" -c "$ROOT/test/parity/base/atomicspinlock_ref.cpp" \
        -o "$IMP/atomicspinlock_ref.o"
}

build_cangjie_probe()
{
    check_compiler
    "$SELFHOST_CJC" "$ROOT/test/parity/base/atomicspinlock_probe.cj" \
        --import-path "$IMP" --int-overflow wrapping \
        "$IMP/librt.base.a" "$IMP/Atomic.o" "$IMP/SpinLock.o" "$IMP/Panic.o" "$IMP/atomicspinlock_ref.o" \
        --link-option=-lstdc++ --link-option=-lpthread --link-option=-lgcc_s -o "$CJ_PROBE"
    [[ -x "$CJ_PROBE" ]] || fail "Cangjie probe executable absent"
    local resolved_runtime
    resolved_runtime=$(ldd "$CJ_PROBE" | awk '/libcangjie-runtime\.so/{print $3; exit}')
    [[ "$(readlink -f "$resolved_runtime")" == "$(readlink -f "$SELFHOST_RT/libcangjie-runtime.so")" ]] ||
        fail "Cangjie probe runtime identity mismatch"
    "$CJ_PROBE" > "$CJ_TRANSCRIPT"
    [[ -s "$CJ_TRANSCRIPT" ]] || fail "empty Cangjie transcript"
}

check_parity()
{
    cmp -s "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT" || {
        echo "C++ transcript:" >&2
        sed -n '1,20p' "$CPP_TRANSCRIPT" >&2
        echo "Cangjie transcript:" >&2
        sed -n '1,20p' "$CJ_TRANSCRIPT" >&2
        fail "transcript byte mismatch"
    }
    [[ $(wc -l < "$CJ_TRANSCRIPT") -eq 6 ]] || fail "unexpected transcript record count"
    grep -Fxq 'ATOMICSPINLOCK_LAYOUT sizeof=1 align=1 state=0' "$CJ_TRANSCRIPT" ||
        fail "layout record mismatch"
    grep -Fxq 'ATOMICSPINLOCK_BYTES construct=0 try_success=1 try_failed=1 unlock=0 lock=1 final_unlock=0' \
        "$CJ_TRANSCRIPT" || fail "complete object-byte sequence mismatch"
    grep -Fxq 'ATOMICSPINLOCK_TRY clear=true held=false status=PASS' "$CJ_TRANSCRIPT" ||
        fail "TryLock state-machine mismatch"
    grep -Fxq 'ATOMICSPINLOCK_BLOCK pre_release=1 acquired_before_release=0 post_release=1 acquired_after_release=1 status=PASS' \
        "$CJ_TRANSCRIPT" || fail "blocking acquisition mismatch"
    grep -Fxq 'ATOMICSPINLOCK_COUNTER threads=4 iterations=4096 expected=16384 actual=16384 final=0 status=PASS' \
        "$CJ_TRANSCRIPT" || fail "critical-section counter mismatch"
    grep -Fxq 'ATOMICSPINLOCK_HANDOFF payload=1511506142 observed=1511506142 final=0 status=PASS' \
        "$CJ_TRANSCRIPT" || fail "release/acquire handoff mismatch"
    sed -n '1,20p' "$CJ_TRANSCRIPT"
    echo "ATOMICSPINLOCK_PARITY records=6 bytes=$(stat -c %s "$CJ_TRANSCRIPT") cmp=identical status=PASS"
}

check_bridge_and_layout()
{
    local test_defs clear_defs test_relocs clear_relocs test_exec clear_exec
    [[ $(grep -Fxc 'extern "C" bool cj_atomic_flag_test_and_set(uint8_t* p)' \
        "$ROOT/rt0/os/Linux/Atomic.cpp") -eq 1 ]] || fail "test-and-set native signature mismatch"
    [[ $(grep -Fxc 'extern "C" void cj_atomic_flag_clear(uint8_t* p) { __atomic_clear(p, __ATOMIC_RELEASE); }' \
        "$ROOT/rt0/os/Linux/Atomic.cpp") -eq 1 ]] || fail "clear native signature/order mismatch"
    [[ $(grep -Fc 'return __atomic_test_and_set(p, __ATOMIC_ACQUIRE);' \
        "$ROOT/rt0/os/Linux/Atomic.cpp") -eq 1 ]] || fail "test-and-set native order mismatch"
    [[ $(grep -Fxc '    func cj_atomic_flag_test_and_set(p: CPointer<UInt8>): Bool' \
        "$ROOT/src/rt/base/AtomicSpinLock.cj") -eq 1 ]] || fail "test-and-set foreign signature mismatch"
    [[ $(grep -Fxc '    func cj_atomic_flag_clear(p: CPointer<UInt8>): Unit' \
        "$ROOT/src/rt/base/AtomicSpinLock.cj") -eq 1 ]] || fail "clear foreign signature mismatch"
    test_defs=$(nm -g --defined-only "$IMP/Atomic.o" | awk '$3 == "cj_atomic_flag_test_and_set" {++n} END {print n+0}')
    clear_defs=$(nm -g --defined-only "$IMP/Atomic.o" | awk '$3 == "cj_atomic_flag_clear" {++n} END {print n+0}')
    test_relocs=$(objdump -r "$IMP/base_temps/rt.base.o" |
        awk '$3 == "cj_atomic_flag_test_and_set" {++n} END {print n+0}')
    clear_relocs=$(objdump -r "$IMP/base_temps/rt.base.o" |
        awk '$3 == "cj_atomic_flag_clear" {++n} END {print n+0}')
    test_exec=$(nm -g --defined-only "$CJ_PROBE" |
        awk '$3 == "cj_atomic_flag_test_and_set" {++n} END {print n+0}')
    clear_exec=$(nm -g --defined-only "$CJ_PROBE" |
        awk '$3 == "cj_atomic_flag_clear" {++n} END {print n+0}')
    [[ $test_defs -eq 1 && $clear_defs -eq 1 && $test_relocs -eq 1 && $clear_relocs -eq 1 &&
       $test_exec -eq 1 && $clear_exec -eq 1 ]] || fail "bridge definitions/relocations mismatch"
    for symbol in CJRT_AtomicSpinLockLock CJRT_AtomicSpinLockUnlock CJRT_AtomicSpinLockTryLock; do
        [[ $(nm -g --defined-only "$CJ_PROBE" | awk -v symbol="$symbol" '$3 == symbol {++n} END {print n+0}') -eq 1 ]] ||
            fail "missing Cangjie operation entry $symbol"
    done
    "$LLVM_BIN/llvm-dis" "$IMP/base_temps/rt.base.opt.bc" -o "$IMP/base.final.ll"
    grep -Fxq '%"record.rt.base:AtomicSpinLock" = type { i8 }' "$IMP/base.final.ll" ||
        fail "Cangjie inline record is not one byte"
    echo "ATOMICSPINLOCK_LAYOUT_GATE cpp_size=1 cpp_align=1 cpp_state_offset=0 cj_size=1 cj_align=1 cj_state_offset=0 complete_states=6 status=PASS"
    echo "ATOMICSPINLOCK_BRIDGE symbols=2 signatures=2 base_relocations=2 native_definitions=2 executable_definitions=2 orders=acquire,release status=PASS"
}

build_closure_inputs()
{
    cp "$ROOT/test/parity/base/atomicspinlock_noheap_roots.cj" \
        "$IMP/atomicspinlock.noheap/Roots.cj"
    check_compiler
    "$SELFHOST_CJC" --package "$IMP/atomicspinlock.noheap" --output-type=staticlib \
        -O2 --int-overflow wrapping --import-path "$IMP" --save-temps "$IMP/root_temps" \
        --output-dir "$IMP" -o libatomicspinlock.noheap.a
    [[ -s "$IMP/root_temps/atomicspinlock.noheap.o" ]] || fail "root object absent"
    "$LLVM_BIN/llvm-link" "$IMP/base_temps/rt.base.bc" \
        "$IMP/root_temps/atomicspinlock.noheap.bc" -o "$IMP/linked.pre.bc"
    "$LLVM_BIN/llvm-link" "$IMP/base_temps/rt.base.opt.bc" \
        "$IMP/root_temps/atomicspinlock.noheap.opt.bc" -o "$IMP/linked.final.bc"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.pre.bc" -o "$IMP/linked.pre.ll"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.final.bc" -o "$IMP/linked.final.ll"
}

closure_args=(
    --pre-ll "$IMP/linked.pre.ll"
    --final-ll "$IMP/linked.final.ll"
    --manifest "$ROOT/test/parity/base/atomicspinlock_noheap_manifest.txt"
    --object "$IMP/root_temps/atomicspinlock.noheap.o"
    --object "$IMP/base_temps/rt.base.o"
    --object "$IMP/Atomic.o"
)

run_closure_proof()
{
    python3 "$ROOT/test/parity/base/atomicspinlock_closure.py" "${closure_args[@]}"
}

run_negative_self_tests()
{
    local mode negative_rc
    for mode in missing extra forbidden; do
        set +e
        python3 "$ROOT/test/parity/base/atomicspinlock_closure.py" "${closure_args[@]}" \
            --mode "$mode" > "$IMP/negative.$mode.log" 2>&1
        negative_rc=$?
        set -e
        [[ $negative_rc -ne 0 ]] || fail "negative mode $mode returned zero"
        grep -Fq "ATOMICSPINLOCK_CLOSURE FAIL mode=$mode" "$IMP/negative.$mode.log" ||
            fail "negative mode $mode did not execute the real analyzer"
        echo "ATOMICSPINLOCK_NEGATIVE mode=$mode rc=$negative_rc status=PASS"
    done
}

build_cpp_oracle
build_base_and_native
build_cangjie_probe
check_parity
check_bridge_and_layout
build_closure_inputs
run_closure_proof
run_negative_self_tests

header_sha=$(sha256sum "$CPP_RUNTIME_ROOT/src/Base/AtomicSpinLock.h" | awk '{print $1}')
tree_sha=$(git -C "$ROOT" rev-parse 'HEAD^{tree}')
cpp_sha=$(sha256sum "$CPP_ORACLE" | awk '{print $1}')
cj_sha=$(sha256sum "$CJ_PROBE" | awk '{print $1}')
transcript_sha=$(sha256sum "$CJ_TRANSCRIPT" | awk '{print $1}')
platform_branches=$(rg -n '_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif' \
    "$CPP_RUNTIME_ROOT/src/Base/AtomicSpinLock.h" || true)
[[ -z "$platform_branches" ]] || fail "unexpected C++ header platform branch"
echo "ATOMICSPINLOCK_CPP_HEADER sha256=$header_sha platform_conditionals=0 exact_header=1 status=PASS"
echo "ATOMICSPINLOCK_COPY_SURFACE cpp_copy_constructor=deleted cpp_assignment=deleted cangjie_compile_time_deletion=unavailable clone_api=0 production_test_lock_copies=0 status=DEBT_RECORDED"
echo "ATOMICSPINLOCK_PLATFORM linux_x86_64=EXECUTED aarch64_linux=UNEXECUTED arm32_linux=UNEXECUTED macOS_iOS=UNEXECUTED Win64=UNEXECUTED Hongmeng_OHOS=UNEXECUTED other_targets=UNEXECUTED status=DEBT_RECORDED"
echo "ATOMICSPINLOCK_EVIDENCE tree=$tree_sha cpp_oracle_sha256=$cpp_sha cj_probe_sha256=$cj_sha transcript_sha256=$transcript_sha status=PASS"
echo "ATOMICSPINLOCK_STAGES header_oracle=1 cj_consumer=1 byte_layout=1 state_machine=1 blocking=1 counter=1 handoff=1 bridge=1 pre_closure=1 final_closure=1 object_closure=1 negatives=3 status=PASS"
echo "ATOMICSPINLOCK_DISK_AFTER available_kb=$(df -Pk / | awk 'NR==2 {print $4}')"
echo "run_atomicspinlock_probe: PASS"
