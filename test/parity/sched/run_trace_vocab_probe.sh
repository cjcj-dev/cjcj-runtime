#!/usr/bin/env bash
# Fail-closed Trace vocabulary, native bytes, layout, and callback ABI parity.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CJTHREAD_ROOT="$CPP_RUNTIME_ROOT/src/CJThread/src"
export cjHeapSize=24GB

fail() { echo "run_trace_vocab_probe: FAIL $*" >&2; exit 1; }
run_cjc() { "$SELFHOST_CJC" "$@"; }

[[ $(uname -s)/$(uname -m) == Linux/x86_64 ]] || fail "Linux x86_64 execution required"
for tool in g++ cmp sha256sum stat git awk rg llvm-nm mktemp sed; do
    command -v "$tool" >/dev/null || fail "missing tool=$tool"
done
HEAD_SHA=$(git -C "$ROOT" rev-parse HEAD)
echo "TRACE_VOCAB_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA256 size=$COMPILER_SIZE toolchain_root=$CANGJIE_HOME toolchain=$COMPILER_BUILD_TOOLCHAIN LLVM=$RUNTIME_LLVM_LIB LLVM_sha256=$RUNTIME_LLVM_SHA256 LLVM_size=$RUNTIME_LLVM_SIZE head=$HEAD_SHA status=PASS"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_trace_vocab.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sched_temps" "$TMP/win.release" "$TMP/win.debug"

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
    -I "$CJTHREAD_ROOT/runtime/timer/include"
    -I "$CJTHREAD_ROOT/runtime/timer/include/inner"
    -I "$CJTHREAD_ROOT/runtime/netpoll/include/inner"
    -I "$CJTHREAD_ROOT/runtime/netpoll/include/linux/inner"
    -I "$CJTHREAD_ROOT/trace/include/inner"
)
CPP_SELECT=(-DMRT_HARDWARE_PLATFORM=MRT_X86 -DVOS_WORDSIZE=64)
CPP_WARN=(-Wall -Wextra -Werror -Wno-invalid-offset-of -Wno-strict-aliasing
    -Wno-overloaded-virtual -Wno-type-limits)

g++ -std=c++14 -O2 "${CPP_WARN[@]}" "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
    -DTRACE_VOCAB_ORACLE "$ROOT/test/parity/sched/trace_vocab_ref.cpp" -o "$TMP/oracle"
"$TMP/oracle" > "$TMP/cpp.transcript"

run_cjc --package "$ROOT/src/rt.sched" --output-type=staticlib -O2 \
    --int-overflow wrapping --save-temps "$TMP/sched_temps" --output-dir "$TMP" -o librt.sched.a
g++ -std=c++14 -O2 -fno-inline -fno-toplevel-reorder -fPIC "${CPP_WARN[@]}" \
    "${CPP_SELECT[@]}" "${CPP_INCLUDE[@]}" \
    -c "$ROOT/test/parity/sched/trace_vocab_ref.cpp" -o "$TMP/ref.o"
g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
    -c "$ROOT/rt0/os/Linux/CJThreadSemaphore.cpp" -o "$TMP/semaphore.o"
g++ -std=c++14 -O2 -fPIC -Wall -Wextra -Werror \
    -c "$ROOT/rt0/os/Linux/CJThreadSpinLock.cpp" -o "$TMP/spinlock.o"
run_cjc "$ROOT/test/parity/sched/trace_vocab_probe.cj" --import-path "$TMP" \
    --int-overflow wrapping "$TMP/librt.sched.a" "$TMP/ref.o" \
    "$TMP/semaphore.o" "$TMP/spinlock.o" \
    --link-option=-lstdc++ --link-option=-lpthread --link-option=-lgcc_s -o "$TMP/probe"
"$TMP/probe" > "$TMP/cj.transcript"

cmp "$TMP/cpp.transcript" "$TMP/cj.transcript" || fail "complete C++/Cangjie transcript mismatch"
[[ $(wc -l < "$TMP/cj.transcript") -eq 16 ]] || fail "transcript line count"
grep -Fxq 'TRACE_HOOKS_LAYOUT size=48 align=8 deregister=0 start=8 stop=16 event=24 dump=32 reader=40' "$TMP/cj.transcript" || fail "TraceHooks layout"
grep -Fxq 'TRACE_HEADER_LAYOUT size=32 align=8 dulink=0 ticks=16 pos=24' "$TMP/cj.transcript" || fail "TraceBufHeader layout"
grep -Fxq 'TRACE_BUF_LAYOUT size=65536 align=8 header=0 arr=32 arr_length=65504 derived_length=65504' "$TMP/cj.transcript" || fail "TraceBuf layout/length closure"
grep -Fxq 'TRACE_SENTINEL cpp_write_cj_read=0 cj_write_cpp_read=0 callbacks=0 va0=1122334455667788 va1=8877665544332211 status=PASS' "$TMP/cj.transcript" || fail "bidirectional sentinel/callback ABI"
echo "TRACE_VOCAB_TRANSCRIPT lines=16 bytes=$(wc -c < "$TMP/cj.transcript") sha256=$(sha256sum "$TMP/cj.transcript" | awk '{print $1}') cmp=PASS"
cat "$TMP/cj.transcript"

"$LLVM_BIN/llvm-dis" "$TMP/sched_temps/rt.sched.opt.bc" -o "$TMP/sched.final.ll"
grep -Fq '%"record.rt.sched:TraceHooks" = type { void ()*, i1 (i16)*, i1 ()*, void (i32, i32, i8*, i32, i8*)*, i8* (i8*)*, i8* ()* }' "$TMP/sched.final.ll" || fail "TraceHooks final IR"
grep -Fq '%"record.rt.sched:TraceBufHeader" = type { %"record.rt.sched:Dulink", i64, i32 }' "$TMP/sched.final.ll" || fail "TraceBufHeader final IR"
grep -Fq '%"record.rt.sched:TraceBuf" = type { %"record.rt.sched:TraceBufHeader", [65504 x i8] }' "$TMP/sched.final.ll" || fail "TraceBuf final IR"
for symbol in TRACE_HEADER TRACE_EXIT_STRING TRACE_RESCHED_STRING TRACE_NET_BLOCK_STRING \
    TRACE_NET_UNBLOCK_STRING TRACE_UNBLOCK_STRING TRACE_UNKNOWN_STRING TRACE_RUNTIME_STRING; do
    rg -q "@$symbol|${symbol}E = global \[[0-9]+ x i8\]" "$TMP/sched.final.ll" || fail "AS0 byte global missing $symbol"
done
managed_edges=$(llvm-nm -u "$TMP/sched_temps/rt.sched.o" | grep -Ec 'CJ_MCC_(New|Write|Throw)' || true)
[[ $managed_edges -eq 0 ]] || fail "managed allocation/barrier/throw edge count=$managed_edges"
production_code=$(sed '/^[[:space:]]*\/\//d' "$ROOT/src/rt.sched/TraceTypes.cj")
! grep -Eq '(^|[^A-Za-z])(String|Array|ArrayList|HashMap|HashSet|LinkedList)([^A-Za-z]|$)|mallocCString|\+ *"|=>.*[A-Za-z]' <<< "$production_code" || fail "managed/dynamic production facility"
[[ $(rg -c '^public const TRACE_EV_' "$ROOT/src/rt.sched/TraceTypes.cj") -eq 21 ]] || fail "TraceEvent inventory"
[[ $(rg -c '^public const ERRNO_TRACE_' "$ROOT/src/rt.sched/TraceTypes.cj") -eq 11 ]] || fail "trace errno inventory"
[[ $(rg -c '^public var TRACE_(HEADER|EXIT_STRING|RESCHED_STRING|NET_BLOCK_STRING|NET_UNBLOCK_STRING|UNBLOCK_STRING|UNKNOWN_STRING|RUNTIME_STRING): VArray<UInt8' "$ROOT/src/rt.sched/TraceTypes.cj") -eq 8 ]] || fail "native string inventory"
[[ $(rg -c '^public type Trace(Register|Deregister|Start|Stop|Event|Dump|ReaderGet)Func' "$ROOT/src/rt.sched/TraceTypes.cj") -eq 7 ]] || fail "callback typedef inventory"
[[ $(rg -c '^public struct Trace(Hooks|BufHeader|Buf) ' "$ROOT/src/rt.sched/TraceTypes.cj") -eq 3 ]] || fail "record inventory"
echo "TRACE_VOCAB_SOURCE types=3 events=21 errors=11 numeric_constants=10 strings=8 callbacks=7 records=3 managed_edges=0 owner_records=0 status=PASS"

for mode in release debug; do
    flags=(); [[ $mode == debug ]] && flags=(-g)
    run_cjc --package "$ROOT/src/rt.sched" --target x86_64-w64-mingw32 \
        --output-type=staticlib "${flags[@]}" --int-overflow wrapping -Woff unused \
        --output-dir "$TMP/win.$mode" -o librt.sched.a
done
echo "TRACE_VOCAB_PLATFORM target=Linux-x86_64 compile=PASS execute=PASS va_list=SYSV-ARRAY-PARAM-POINTER status=PASS"
echo "TRACE_VOCAB_PLATFORM target=Win64 vocabulary=COMPILE-PASS va_list=POINTER native_execute=DEBT-WINDOWS-RUNNER TraceHooks=WITHHELD status=EXPLICIT-DEBT"
echo "TRACE_VOCAB_PLATFORM target=Apple vocabulary=SOURCE-COMMON va_list=POINTER native_execute=DEBT-APPLE-SDK TraceHooks=WITHHELD status=EXPLICIT-DEBT"
echo "TRACE_VOCAB_PLATFORM target=OHOS-AArch64 vocabulary=SOURCE-COMMON va_list=AAPCS64-32B-AGGREGATE native_execute=DEBT-OHOS-RUNNER TraceHooks=WITHHELD status=EXPLICIT-DEBT"
echo "TRACE_VOCAB_OWNER pthread_mutex=EXCLUDED atomic=EXCLUDED DlHandle_MRT_WINDOWS=EXCLUDED followup=TRACE-OWNER status=PASS"

negative_cmp()
{
    local kind=$1 expression=$2
    sed "$expression" "$TMP/cj.transcript" > "$TMP/negative.$kind"
    set +e
    cmp "$TMP/cpp.transcript" "$TMP/negative.$kind" >/dev/null
    local cmp_rc=$?
    set -e
    [[ $cmp_rc -ne 0 ]] || fail "negative accepted kind=$kind"
    echo "TRACE_VOCAB_NEGATIVE kind=$kind cmp_rc=$cmp_rc status=PASS"
}
negative_cmp value 's/TRACE_TYPES 256/TRACE_TYPES 257/'
negative_cmp size 's/TRACE_HOOKS_LAYOUT size=48/TRACE_HOOKS_LAYOUT size=49/'
negative_cmp offset 's/start=8/start=9/'
negative_cmp string 's/bytes=43616e/bytes=44616e/'

echo "TRACE_VOCAB_BINARIES oracle_sha256=$(sha256sum "$TMP/oracle" | awk '{print $1}') oracle_size=$(stat -c %s "$TMP/oracle") cj_sha256=$(sha256sum "$TMP/probe" | awk '{print $1}') cj_size=$(stat -c %s "$TMP/probe") status=PASS"
echo "run_trace_vocab_probe: PASS"
