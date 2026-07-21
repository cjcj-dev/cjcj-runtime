#!/usr/bin/env bash
# Fail-closed Thread/LuaCJThread embedded Semaphore layout, address, and closure parity.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CJTHREAD_ROOT="$CPP_RUNTIME_ROOT/src/CJThread/src"
SCHEDULE_SRC="$CJTHREAD_ROOT/runtime/schedule/src"
THREAD_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/inner/thread.h"
CJTHREAD_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/inner/cjthread.h"
CONTEXT_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/inner/gas/x86/x86_64/cjthread_context.h"
ARM32_CONTEXT="$CJTHREAD_ROOT/runtime/schedule/include/inner/gas/arm/arm32/cjthread_context.h"
ARM64_CONTEXT="$CJTHREAD_ROOT/runtime/schedule/include/inner/gas/arm/arm64/cjthread_context.h"
LIST_HEADER="$CJTHREAD_ROOT/runtime/util/list/include/list.h"
SCHEDULE_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/schedule.h"
BASE_HEADER="$CJTHREAD_ROOT/runtime/schedule/include/inner/base.h"
export PATH=/root/.cjv/bin:$PATH
export cjHeapSize=24GB

fail()
{
    echo "run_thread_semaphore_layout_probe: FAIL $*" >&2
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
        fail "executable descriptor must be Linux x86_64"
    for tool in g++ objdump nm readelf python3 cmp sha256sum stat git awk sed grep rg df \
        readlink find wc cp mktemp uname chmod; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    [[ -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] ||
        fail "missing pinned nightly LLVM tools"
    for input in \
        "$THREAD_HEADER" "$CJTHREAD_HEADER" "$CONTEXT_HEADER" "$ARM32_CONTEXT" \
        "$ARM64_CONTEXT" "$LIST_HEADER" "$SCHEDULE_HEADER" "$BASE_HEADER" \
        "$CJTHREAD_ROOT/base/mid/include/macro_def.h" \
        "$ROOT/src/rt.sched/Thread.cj" "$ROOT/src/rt.sched/Semaphore.cj" \
        "$ROOT/src/rt.sched/CJthreadSpinLock.cj" \
        "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" \
        "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" \
        "$ROOT/test/parity/sched/thread_semaphore_layout_ref.cpp" \
        "$ROOT/test/parity/sched/thread_semaphore_layout_probe.cj" \
        "$ROOT/test/parity/sched/thread_semaphore_noheap_roots.cj" \
        "$ROOT/test/parity/sched/thread_semaphore_noheap_manifest.txt" \
        "$ROOT/test/parity/sched/thread_semaphore_consumers.txt" \
        "$ROOT/test/parity/sched/thread_semaphore_closure.py" \
        "$ROOT/test/parity/base/atomicspinlock_closure.py"; do
        [[ -f "$input" ]] || fail "missing input $input"
    done
    [[ $(find "$ROOT/rt0/os" -type f -name CJThreadSemaphore.cpp -print | wc -l) -eq 1 ]] ||
        fail "unexpected CJThread semaphore bridge source count"
}

require_inputs
check_compiler
echo "THREAD_SEMAPHORE_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"
disk_before=$(df -Pk / | awk 'NR==2 {print $4}')
echo "THREAD_SEMAPHORE_DISK_BEFORE available_kb=$disk_before"

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_thread_semaphore_layout.XXXXXX")
trap 'rm -rf "$IMP"' EXIT
ulimit -c 0
mkdir -p "$IMP/sched_temps" "$IMP/root_temps" "$IMP/threadsemaphore.noheap"
cp "$ROOT/test/parity/sched/thread_semaphore_noheap_roots.cj" \
    "$IMP/threadsemaphore.noheap/roots.cj"

CPP_ORACLE="$IMP/thread_semaphore_oracle"
CJ_PROBE="$IMP/thread_semaphore_probe"
CPP_TRANSCRIPT="$IMP/cpp.transcript"
CJ_TRANSCRIPT="$IMP/cj.transcript"
CPP_ADDRESS="$IMP/cpp.address"
CJ_ADDRESS="$IMP/cj.address"
CPP_SELECT=(-DMRT_HARDWARE_PLATFORM=MRT_X86 -DVOS_WORDSIZE=64)
CPP_INCLUDE=(
    -I "$CPP_RUNTIME_ROOT/include"
    -I "$CPP_RUNTIME_ROOT/src"
    -I "$CPP_RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    -I "$CJTHREAD_ROOT/base/mid/include"
    -I "$CJTHREAD_ROOT/base/log/include"
    -I "$CJTHREAD_ROOT/runtime/schedule/include"
    -I "$CJTHREAD_ROOT/runtime/schedule/include/inner"
    -I "$CJTHREAD_ROOT/runtime/schedule/include/inner/gas/x86/x86_64"
    -I "$CJTHREAD_ROOT/runtime/util/list/include"
)
CPP_WARN=(
    -Wall -Wextra -Werror -Wno-invalid-offset-of -Wno-strict-aliasing
    -Wno-overloaded-virtual -Wno-type-limits
)
SEM_WRAPS=(sem_init sem_wait sem_post sem_destroy)
BRIDGE_WRAPS=(
    cj_cjthread_semaphore_init cj_cjthread_semaphore_wait
    cj_cjthread_semaphore_wait_no_intr cj_cjthread_semaphore_post
    cj_cjthread_semaphore_destroy
)

build_cpp_oracle()
{
    local link_args=() symbol
    for symbol in "${SEM_WRAPS[@]}"; do
        link_args+=("-Wl,--wrap=$symbol")
    done
    g++ -std=c++14 -O2 "${CPP_WARN[@]}" "${CPP_SELECT[@]}" \
        -DTHREAD_SEMAPHORE_LAYOUT_ORACLE "${CPP_INCLUDE[@]}" \
        "$ROOT/test/parity/sched/thread_semaphore_layout_ref.cpp" -pthread \
        "${link_args[@]}" -o "$CPP_ORACLE"
    "$CPP_ORACLE" > "$CPP_TRANSCRIPT" 2> "$CPP_ADDRESS"
    [[ -s "$CPP_TRANSCRIPT" && -s "$CPP_ADDRESS" ]] || fail "empty C++ oracle evidence"
}

check_transcript_shape()
{
    local transcript=$1 address=$2
    [[ $(wc -l < "$transcript") -eq 23 ]] || fail "unexpected transcript line count"
    [[ $(grep -c '^THREAD_SEMAPHORE_OWNER_BYTES owner=' "$transcript") -eq 10 ]] ||
        fail "incomplete full-owner snapshots"
    grep -Fxq 'THREAD_LAYOUT sizeof=232 align=8 link2schd=0 cjthread=16 cjthread0=24 preemptFlag=32 preemptRequest=40 state=48 processor=56 oldProcessor=64 sem=72 tid=104 osThread=112 context=120 isSearching=192 boundCJThread=200 nextProcessor=208 allThreadDulink=216' "$transcript" || fail "Thread layout mismatch"
    grep -Fxq 'LUA_CJTHREAD_LAYOUT sizeof=200 align=8 cjthread=0 func=8 arg=16 result=24 sem=32 state=64 attrUser=68' "$transcript" || fail "LuaCJThread layout mismatch"
    grep -Fxq 'DULINK_LAYOUT sizeof=16 align=8 prev=0 next=8' "$transcript" ||
        fail "Dulink layout mismatch"
    grep -Fxq 'CJTHREAD_CONTEXT_LAYOUT sizeof=72 align=8 rsp=0 rbp=8 rbx=16 rip=24 r12=32 r13=40 r14=48 r15=56 mxcsr=64 fpuCw=68' "$transcript" || fail "context layout mismatch"
    grep -Fxq 'CJTHREAD_ATTR_LAYOUT sizeof=128 align=1 attr=0' "$transcript" ||
        fail "CJThreadAttr layout mismatch"
    grep -Fxq 'THREAD_SEMAPHORE_ENUM init=0 close=1 running=2 pre_sleep=3 sleep=4' "$transcript" ||
        fail "ThreadState values mismatch"
    grep -Fxq 'THREAD_SEMAPHORE_ATOMIC size=4 align=4 values=00000000,01000000,02000000,03000000,04000000' "$transcript" || fail "atomic representation mismatch"
    grep -Fxq 'THREAD_SEMAPHORE_REP pid=4/4/00000000/04030201 pthread=8/8/0000000000000000/0807060504030201 bool=1/1/00/01 data_pointer=8/8/0000000000000000/0807060504030201 function_pointer=8/8/0000000000000000/0807060504030201' "$transcript" || fail "native scalar/pointer representation mismatch"
    grep -Fxq 'THREAD_SEMAPHORE_FIELD_ADDRESS thread_offset=72 lua_offset=32 cangjie_equals_cpp=2 native_address_mismatches=0 libc_address_mismatches=0 status=PASS' "$transcript" || fail "embedded field-address mismatch"
    grep -Fxq 'THREAD_SEMAPHORE_LEAVES native_init=2 native_wait=1 native_wait_no_intr=1 native_post=2 native_destroy=2 libc_init=2 libc_wait=1 libc_wait_no_intr=1 libc_post=2 libc_destroy=2 original_addresses=2 status=PASS' "$transcript" || fail "Layer0 leaf address/count mismatch"
    grep -Fxq 'THREAD_SEMAPHORE_OUTSIDE snapshots=5 thread_unchanged=5 lua_unchanged=5 status=PASS' "$transcript" || fail "owner outside bytes changed"
    [[ $(wc -l < "$address") -eq 2 ]] || fail "raw address record count mismatch"
    awk '
        /^THREAD_SEMAPHORE_RAW_ADDRESS / {
            owner=""; cj=""; cpp="";
            for (i=1; i<=NF; ++i) {
                split($i, pair, "=");
                if (pair[1] == "owner_address") owner=pair[2];
                if (pair[1] == "cangjie_field") cj=pair[2];
                if (pair[1] == "cpp_field") cpp=pair[2];
            }
            if (owner == "" || cj == "" || cpp == "" || cj != cpp) exit 1;
            ++seen;
        }
        END { if (seen != 2) exit 1 }
    ' "$address" || fail "raw Cangjie/C++ member address mismatch"
}

build_production_and_probe()
{
    run_cjc --package "$ROOT/src/rt.sched" --output-type=staticlib -O2 \
        --int-overflow wrapping --save-temps "$IMP/sched_temps" \
        --output-dir "$IMP" -o librt.sched.a
    run_cjc --package "$IMP/threadsemaphore.noheap" --output-type=staticlib -O2 \
        --int-overflow wrapping --import-path "$IMP" --save-temps "$IMP/root_temps" \
        --output-dir "$IMP" -o libthreadsemaphore.noheap.a
    g++ -std=c++14 -O2 -fno-inline -fno-toplevel-reorder -fPIC "${CPP_WARN[@]}" \
        "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
        -c "$ROOT/test/parity/sched/thread_semaphore_layout_ref.cpp" -o "$IMP/layout_ref.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" -o "$IMP/CJThreadSemaphore.o"
    g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
        -c "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" -o "$IMP/CJThreadSpinLock.o"
    local link_args=() symbol
    for symbol in "${SEM_WRAPS[@]}" "${BRIDGE_WRAPS[@]}"; do
        link_args+=("--link-option=--wrap=$symbol")
    done
    run_cjc "$ROOT/test/parity/sched/thread_semaphore_layout_probe.cj" \
        --import-path "$IMP" --int-overflow wrapping \
        "$IMP/libthreadsemaphore.noheap.a" "$IMP/librt.sched.a" \
        "$IMP/layout_ref.o" "$IMP/CJThreadSemaphore.o" "$IMP/CJThreadSpinLock.o" \
        --link-option=-lstdc++ --link-option=-lpthread --link-option=-lgcc_s \
        "${link_args[@]}" -o "$CJ_PROBE"
    "$CJ_PROBE" > "$CJ_TRANSCRIPT" 2> "$CJ_ADDRESS"
}

check_layout_source_inventory_platforms()
{
    check_transcript_shape "$CPP_TRANSCRIPT" "$CPP_ADDRESS"
    check_transcript_shape "$CJ_TRANSCRIPT" "$CJ_ADDRESS"
    cmp "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT" || fail "complete C++/Cangjie transcript mismatch"
    local transcript_sha
    transcript_sha=$(sha256sum "$CJ_TRANSCRIPT" | awk '{print $1}')
    echo "THREAD_SEMAPHORE_TRANSCRIPT lines=$(wc -l < "$CJ_TRANSCRIPT") bytes=$(wc -c < "$CJ_TRANSCRIPT") sha256=$transcript_sha cmp=PASS"
    cat "$CJ_ADDRESS"

    "$LLVM_BIN/llvm-dis" "$IMP/sched_temps/rt.sched.opt.bc" -o "$IMP/sched.final.ll"
    "$LLVM_BIN/llvm-dis" "$IMP/root_temps/threadsemaphore.noheap.opt.bc" -o "$IMP/root.final.ll"
    grep -Fxq '%"record.rt.sched:Thread" = type { %"record.rt.sched:Dulink", i8*, i8*, i8*, i8*, i32, i8*, i8*, %"record.rt.sched:Semaphore", i32, i64, %"record.rt.sched:CJThreadContext", i1, i8*, i8*, %"record.rt.sched:Dulink" }' "$IMP/sched.final.ll" || fail "Thread final IR record mismatch"
    grep -Fxq '%"record.rt.sched:LuaCJThread" = type { i8*, i8*, i8*, i8*, %"record.rt.sched:Semaphore", i32, %"record.rt.sched:CJThreadAttr" }' "$IMP/sched.final.ll" || fail "LuaCJThread final IR record mismatch"
    grep -Fxq '%"record.rt.sched:CJThreadContext" = type { i64, i64, i64, i64, i64, i64, i64, i64, i32, i16 }' "$IMP/sched.final.ll" || fail "context final IR record mismatch"
    grep -Fxq '%"record.rt.sched:Dulink" = type { i8*, i8* }' "$IMP/sched.final.ll" || fail "Dulink final IR record mismatch"
    grep -Fxq '%"record.rt.sched:CJThreadAttr" = type { [128 x i8] }' "$IMP/sched.final.ll" || fail "CJThreadAttr final IR record mismatch"
    grep -Fq 'getelementptr inbounds %"record.rt.sched:Thread", %"record.rt.sched:Thread"* %thread, i64 0, i32 8' "$IMP/root.final.ll" || fail "Thread sem is not direct member GEP"
    grep -Fq 'getelementptr inbounds %"record.rt.sched:LuaCJThread", %"record.rt.sched:LuaCJThread"* %lua, i64 0, i32 4' "$IMP/root.final.ll" || fail "LuaCJThread sem is not direct member GEP"
    ! rg -q 'addrspacecast.*addrspace\(1\).* to [^,]*\*' "$IMP/root.final.ll" ||
        fail "illegal AS1-to-AS0 cast in embedded-field root"
    ! rg -q 'toUIntNative|CPointer<UInt8>\([^)]*\)\s*[+-]' \
        "$ROOT/src/rt.sched/Thread.cj" "$ROOT/test/parity/sched/thread_semaphore_noheap_roots.cj" ||
        fail "integer pointer arithmetic in owner/member path"
    ! rg -q '^public func |ThreadSleep\(|ThreadEntry\(|ThreadCreate\(|ThreadAlloc|CJThreadCreate\(|CJThreadResume\(|CJThreadYield\(|CJThreadDestroy\(|malloc|calloc|new ' \
        "$ROOT/src/rt.sched/Thread.cj" || fail "forbidden scheduler/lifecycle/wrapper surface"
    ! rg -q 'CJRT_ThreadOwnerRun|ThreadSemaphore|rt\.sched:Thread|(^|[^A-Za-z0-9_])(Thread|LuaCJThread|CJThreadContext|CJThreadAttr|Dulink)([^A-Za-z0-9_]|$)' "$ROOT/contract" ||
        fail "descriptor leaked into production export contract"

    local rows=0 owner operation file line expected actual
    declare -A owner_counts=([Thread]=0 [LuaCJThread]=0)
    declare -A operation_counts=([Init]=0 [WaitNoIntr]=0 [Wait]=0 [Post]=0 [Destroy]=0)
    while IFS='|' read -r owner operation file line expected; do
        [[ -n "$owner" && ${owner:0:1} != '#' ]] || continue
        actual=$(sed -n "${line}p" "$SCHEDULE_SRC/$file")
        [[ "$actual" == "$expected" ]] || fail "consumer drift $file:$line"
        ((++rows)); ((++owner_counts[$owner])); ((++operation_counts[$operation]))
    done < "$ROOT/test/parity/sched/thread_semaphore_consumers.txt"
    [[ $rows -eq 21 && ${owner_counts[Thread]} -eq 15 && ${owner_counts[LuaCJThread]} -eq 6 ]] ||
        fail "consumer owner count mismatch"
    [[ ${operation_counts[Init]} -eq 3 && ${operation_counts[WaitNoIntr]} -eq 1 &&
       ${operation_counts[Wait]} -eq 5 && ${operation_counts[Post]} -eq 7 &&
       ${operation_counts[Destroy]} -eq 5 ]] || fail "consumer operation count mismatch"
    [[ $(rg -n --pcre2 'Semaphore(?:Init|WaitNoIntr|Wait|Post|Destroy)\([^;\n]*->sem' \
        "$SCHEDULE_SRC" | wc -l) -eq 21 ]] || fail "C++ direct consumer source count changed"
    echo "THREAD_SEMAPHORE_CONSUMERS total=21 Thread=15 LuaCJThread=6 Init=3 WaitNoIntr=1 Wait=5 Post=7 Destroy=5 status=PASS"

    grep -Fq '#ifdef MRT_MACOS' "$THREAD_HEADER" || fail "Mac tid selector disappeared"
    grep -Fq '#ifdef MRT_WINDOWS' "$CONTEXT_HEADER" || fail "Win64 context selector disappeared"
    grep -Fq '#ifdef __OHOS__' "$CJTHREAD_HEADER" || fail "OHOS CJThread dependency disappeared"
    grep -Fq '#ifdef __OHOS__' "$ARM32_CONTEXT" || fail "ARM32 context selection disappeared"
    grep -Fq '#ifdef __OHOS__' "$ARM64_CONTEXT" || fail "ARM64 context selection disappeared"
    grep -Fq '#ifdef MRT_MACOS' "$BASE_HEADER" || fail "Darwin Semaphore branch disappeared"
    for debt in CJTHREAD-CONTEXT-PLATFORM-LAYOUT THREAD-DESCRIPTOR-LAYOUT \
        CJTHREAD-SEMAPHORE-DARWIN-LAYOUT CJTHREAD-SEMAPHORE-INLINE-LAYOUT LUA-CJTHREAD-ABI; do
        grep -Fq "$debt" "$ROOT/src/rt.sched/Thread.cj" || fail "missing platform debt $debt"
    done
    [[ $(grep -Fxc '@When[os == "Linux" && arch == "x86_64"]' \
        "$ROOT/src/rt.sched/Thread.cj") -eq 3 ]] || fail "Linux descriptor selection count mismatch"
    echo "THREAD_SEMAPHORE_PLATFORMS linux_x86_64=PROVED macos=DEBT ios=DEBT aarch64_linux=DEBT android_arm32=DEBT android_arm64=DEBT win64=DEBT ohos=DEBT other=DEBT status=PASS"
}

build_closure_inputs()
{
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.bc" \
        "$IMP/root_temps/threadsemaphore.noheap.bc" -o "$IMP/pre.bc"
    "$LLVM_BIN/llvm-link" "$IMP/sched_temps/rt.sched.opt.bc" \
        "$IMP/root_temps/threadsemaphore.noheap.opt.bc" -o "$IMP/final.bc"
    "$LLVM_BIN/llvm-dis" "$IMP/pre.bc" -o "$IMP/pre.ll"
    "$LLVM_BIN/llvm-dis" "$IMP/final.bc" -o "$IMP/final.ll"
}

run_closure()
{
    local closure_output matcher_contract
    closure_args=(
        --pre-ll "$IMP/pre.ll"
        --final-ll "$IMP/final.ll"
        --manifest "$ROOT/test/parity/sched/thread_semaphore_noheap_manifest.txt"
        --object "$IMP/root_temps/threadsemaphore.noheap.o"
        --object "$IMP/sched_temps/rt.sched.o"
        --object "$IMP/layout_ref.o"
        --object "$IMP/CJThreadSemaphore.o"
        --object "$IMP/CJThreadSpinLock.o"
    )
    closure_output=$(python3 "$ROOT/test/parity/sched/thread_semaphore_closure.py" \
        "${closure_args[@]}")
    echo "$closure_output"
    grep -Eq 'THREAD_SEMAPHORE_PRE_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "pre reached/scanned equality absent"
    grep -Eq 'THREAD_SEMAPHORE_FINAL_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "final reached/scanned equality absent"
    grep -Eq 'THREAD_SEMAPHORE_OBJECT_CLOSURE reached_defs=([0-9]+) scanned_defs=\1 ' <<< "$closure_output" || fail "object reached/scanned equality absent"
    matcher_contract='THREAD_SEMAPHORE_BARRIER_MATCHER required_rejected=22 permitted_accepted=31 intrinsic_family_rejected=1 status=PASS'
    grep -Fxq "$matcher_contract" <<< "$closure_output" || fail "barrier matcher contract missing"
}

run_negative_self_tests()
{
    local mode negative_rc expected_stage expected_symbol expected_error reason
    for mode in missing extra forbidden barrier_pre barrier_final barrier_object; do
        case "$mode" in
            missing|extra)
                expected_stage=pre; expected_symbol=reached_scanned
                expected_error='pre reached/scanned mismatch'; reason="${mode}_definition"
                ;;
            forbidden)
                expected_stage=pre; expected_symbol=MCC_NewObject
                expected_error='pre forbidden external: MCC_NewObject'; reason=forbidden_allocation
                ;;
            barrier_pre)
                expected_stage=pre; expected_symbol=MCC_WriteRefField
                expected_error='pre forbidden barrier external: MCC_WriteRefField'; reason=forbidden_barrier
                ;;
            barrier_final)
                expected_stage=final; expected_symbol=CJ_MCC_AtomicSwapReference
                expected_error='final forbidden barrier external: CJ_MCC_AtomicSwapReference'; reason=forbidden_barrier
                ;;
            barrier_object)
                expected_stage=object; expected_symbol=CJ_MCC_WriteGenericPayload
                expected_error='object forbidden barrier external: CJ_MCC_WriteGenericPayload'; reason=forbidden_barrier
                ;;
        esac
        set +e
        python3 "$ROOT/test/parity/sched/thread_semaphore_closure.py" "${closure_args[@]}" \
            --mode "$mode" > "$IMP/negative.$mode.log" 2>&1
        negative_rc=$?
        set -e
        [[ $negative_rc -ne 0 ]] || fail "negative mode $mode returned zero"
        grep -Fq "THREAD_SEMAPHORE_CLOSURE FAIL mode=$mode" "$IMP/negative.$mode.log" ||
            fail "negative mode $mode did not execute real analyzer"
        grep -Fq "$expected_error" "$IMP/negative.$mode.log" ||
            fail "negative mode $mode missed $expected_error"
        echo "THREAD_SEMAPHORE_NEGATIVE mode=$mode rc=$negative_rc stage=$expected_stage symbol=$expected_symbol reason=$reason status=PASS"
    done
}

build_cpp_oracle
check_transcript_shape "$CPP_TRANSCRIPT" "$CPP_ADDRESS"
build_production_and_probe
check_layout_source_inventory_platforms
build_closure_inputs
run_closure
run_negative_self_tests

echo "THREAD_SEMAPHORE_BINARIES oracle_sha256=$(sha256sum "$CPP_ORACLE" | awk '{print $1}') oracle_size=$(stat -c %s "$CPP_ORACLE") cj_sha256=$(sha256sum "$CJ_PROBE" | awk '{print $1}') cj_size=$(stat -c %s "$CJ_PROBE") status=PASS"

disk_after=$(df -Pk / | awk 'NR==2 {print $4}')
disk_delta=$((disk_before - disk_after))
echo "THREAD_SEMAPHORE_DISK_AFTER available_kb=$disk_after consumed_kb=$disk_delta"
(( disk_delta < 2097152 )) || fail "probe consumed more than 2GiB"
echo "THREAD_SEMAPHORE_LAYOUT_PROBE PASS layout=byte-exact addresses=original transcript=byte-identical consumers=21 closure=pre+final+object negatives=6"
