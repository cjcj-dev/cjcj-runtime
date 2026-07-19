#!/usr/bin/env bash
# Fail-closed RwLock C++ parity, invalid-unlock, and final/object noheap proof.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
COMPILER_SOURCE=27b9b88c2a7bc68acfcc870e7b394404a8f6c356
COMPILER_SHA=d99659d1cc797eb179e349bdcff1c635086680fba6b9be5dac61e39eb570b44c
COMPILER_SIZE=98479472
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$CPP_RUNTIME_ROOT/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative"
CPP_BOUNDS_LIB="$CPP_RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export PATH=/root/.cjv/bin:$PATH
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
export cjHeapSize=24GB

fail()
{
    echo "run_rwlock_probe: FAIL $*" >&2
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

require_tools()
{
    local tool
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
        fail "executable target must be Linux x86_64"
    for tool in g++ objdump python3 cmp sha256sum stat git; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    [[ -x "$LLVM_BIN/llvm-link" && -x "$LLVM_BIN/llvm-dis" ]] ||
        fail "missing pinned nightly LLVM tools"
    [[ -f "$CPP_RUNTIME_LIB/libcangjie-runtime.so" ]] || fail "missing read-only C++ runtime"
    [[ -f "$CPP_BOUNDS_LIB/libboundscheck.so" ]] || fail "missing C++ runtime bounds library"
}

IMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_rwlock_probe.XXXXXX")
trap 'rm -rf "$IMP"' EXIT
ulimit -c 0
mkdir -p "$IMP/base_temps" "$IMP/root_temps" "$IMP/rwlock.noheap"

CPP_ORACLE="$IMP/rwlock_oracle"
CJ_VALID="$IMP/rwlock_valid"
CJ_INVALID_READ="$IMP/rwlock_invalid_read"
CJ_INVALID_WRITE="$IMP/rwlock_invalid_write"
CPP_TRANSCRIPT="$IMP/cpp.transcript"
CJ_TRANSCRIPT="$IMP/cj.transcript"

build_cpp_oracle()
{
    g++ -std=c++14 -O2 \
        -I "$CPP_RUNTIME_ROOT/src" \
        -I "$CPP_RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
        "$ROOT/test/parity/base/rwlock_oracle.cpp" \
        -L "$CPP_RUNTIME_LIB" -L "$CPP_BOUNDS_LIB" \
        -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -lboundscheck -pthread \
        -o "$CPP_ORACLE"
    local resolved_runtime
    resolved_runtime=$(LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$CPP_BOUNDS_LIB" ldd "$CPP_ORACLE" |
        awk '/libcangjie-runtime\.so/{print $3; exit}')
    [[ "$(readlink -f "$resolved_runtime")" == "$(readlink -f "$CPP_RUNTIME_LIB/libcangjie-runtime.so")" ]] ||
        fail "C++ oracle runtime identity mismatch"
    LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$CPP_BOUNDS_LIB:$CANGJIE_HOME/third_party/llvm/lib" \
        "$CPP_ORACLE" > "$CPP_TRANSCRIPT"
    [[ -s "$CPP_TRANSCRIPT" ]] || fail "empty C++ oracle transcript"
}

build_base()
{
    check_compiler
    (
        cd "$IMP"
        "$SELFHOST_CJC" --package "$ROOT/src/rt.base" --output-type=staticlib \
            -O2 --int-overflow wrapping --save-temps "$IMP/base_temps" \
            --output-dir "$IMP" -o librt.base.a
    )
    [[ -s "$IMP/librt.base.a" && -s "$IMP/base_temps/rt.base.o" ]] ||
        fail "rt.base build artifacts absent"
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$IMP/Panic.o"
    g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$IMP/Atomic.o"
}

build_cj_executable()
{
    local source=$1 output=$2
    check_compiler
    "$SELFHOST_CJC" "$source" --import-path "$IMP" --int-overflow wrapping \
        "$IMP/librt.base.a" "$IMP/Panic.o" "$IMP/Atomic.o" \
        --link-option=-lstdc++ --link-option=-lgcc_s -o "$output"
    [[ -x "$output" ]] || fail "Cangjie executable absent: $output"
}

run_valid_parity()
{
    build_cj_executable "$ROOT/test/parity/base/rwlock_probe.cj" "$CJ_VALID"
    "$CJ_VALID" > "$CJ_TRANSCRIPT"
    [[ -s "$CJ_TRANSCRIPT" ]] || fail "empty Cangjie transcript"
    cmp -s "$CPP_TRANSCRIPT" "$CJ_TRANSCRIPT" || {
        echo "C++ transcript:" >&2
        sed -n '1,20p' "$CPP_TRANSCRIPT" >&2
        echo "Cangjie transcript:" >&2
        sed -n '1,20p' "$CJ_TRANSCRIPT" >&2
        fail "valid transcript byte mismatch"
    }
    grep -Fxq 'RWLOCK_LAYOUT sizeof=4 align=4 lockCount=0' "$CJ_TRANSCRIPT" ||
        fail "layout transcript mismatch"
    sed -n '1,20p' "$CJ_TRANSCRIPT"
    echo "RWLOCK_PARITY bytes=$(stat -c %s "$CJ_TRANSCRIPT") cmp=identical status=PASS"
}

run_invalid_read()
{
    build_cj_executable "$ROOT/test/parity/base/rwlock_invalid_read.cj" "$CJ_INVALID_READ"
    set +e
    "$CJ_INVALID_READ" > "$IMP/invalid_read.out" 2> "$IMP/invalid_read.err"
    local child_rc=$?
    set -e
    [[ $child_rc -eq 134 ]] || fail "invalid read rc=$child_rc expected=134"
    ! grep -Fq 'RwLock read count underflow' "$IMP/invalid_read.err" ||
        fail "invalid read emitted invented managed diagnostic"
    ! grep -Fq 'Check failed:' "$IMP/invalid_read.err" ||
        fail "invalid read emitted invented CHECK diagnostic"
    ! grep -Fq 'POST_UNLOCK_READ_REACHED' "$IMP/invalid_read.out" "$IMP/invalid_read.err" ||
        fail "invalid read post-call marker reached"
    grep -Fq 'CJNative Handle signal: 6.' "$IMP/invalid_read.err" ||
        fail "invalid read native SIGABRT observation absent"
    echo "RWLOCK_INVALID_READ rc=$child_rc native_signal=6 invented_message=0 post_marker=0 status=PASS"
}

run_invalid_write()
{
    build_cj_executable "$ROOT/test/parity/base/rwlock_invalid_write.cj" "$CJ_INVALID_WRITE"
    set +e
    "$CJ_INVALID_WRITE" > "$IMP/invalid_write.out" 2> "$IMP/invalid_write.err"
    local child_rc=$?
    set -e
    [[ $child_rc -eq 134 ]] || fail "invalid write rc=$child_rc expected=134"
    local message='Check failed: lockCount.load() == WRITE_LOCKED'
    [[ $(grep -Fxc "$message" "$IMP/invalid_write.err") -eq 1 ]] ||
        fail "invalid write exact diagnostic count mismatch"
    ! grep -Fq 'POST_UNLOCK_WRITE_REACHED' "$IMP/invalid_write.out" "$IMP/invalid_write.err" ||
        fail "invalid write post-call marker reached"
    echo "RWLOCK_INVALID_WRITE rc=$child_rc message_count=1 post_marker=0 status=PASS"
}

build_roots_and_graphs()
{
    [[ $(grep -Ec '^public func (UnlockRead|UnlockWrite)\(' \
        "$ROOT/test/parity/base/rwlock_noheap_roots.cj") -eq 2 ]] ||
        fail "root source must contain exactly two enumerated exports"
    cp "$ROOT/test/parity/base/rwlock_noheap_roots.cj" "$IMP/rwlock.noheap/Roots.cj"
    check_compiler
    (
        cd "$IMP"
        "$SELFHOST_CJC" --package "$IMP/rwlock.noheap" --output-type=staticlib \
            -O2 --int-overflow wrapping --import-path "$IMP" \
            --save-temps "$IMP/root_temps" --output-dir "$IMP" -o librwlock.noheap.a
    )
    [[ -s "$IMP/root_temps/rwlock.noheap.o" ]] || fail "root target object absent"
    "$LLVM_BIN/llvm-link" "$IMP"/base_temps/*.opt.bc "$IMP"/root_temps/*.opt.bc \
        -o "$IMP/linked.final.bc"
    "$LLVM_BIN/llvm-dis" "$IMP/linked.final.bc" -o "$IMP/linked.final.ll"
    mapfile -t root_pre < <(find "$IMP/root_temps" -maxdepth 1 -name '*.bc' ! -name '*.opt.bc' -print)
    mapfile -t root_final < <(find "$IMP/root_temps" -maxdepth 1 -name '*.opt.bc' -print)
    [[ ${#root_pre[@]} -eq 1 && ${#root_final[@]} -eq 1 ]] ||
        fail "ambiguous root pre/final artifacts"
    "$LLVM_BIN/llvm-dis" "${root_pre[0]}" -o "$IMP/root.pre.ll"
    "$LLVM_BIN/llvm-dis" "${root_final[0]}" -o "$IMP/root.final.ll"
    [[ -s "$IMP/linked.final.ll" && -s "$IMP/root.pre.ll" && -s "$IMP/root.final.ll" ]] ||
        fail "empty closure IR artifact"
}

closure_args=(
    --pre-ll "$IMP/root.pre.ll"
    --root-final-ll "$IMP/root.final.ll"
    --linked-final-ll "$IMP/linked.final.ll"
    --manifest "$ROOT/test/parity/base/rwlock_noheap_manifest.txt"
    --object "$IMP/root_temps/rwlock.noheap.o"
    --object "$IMP/base_temps/rt.base.o"
    --object "$IMP/Atomic.o"
    --object "$IMP/Panic.o"
)

run_closure_proof()
{
    python3 "$ROOT/test/parity/base/rwlock_closure.py" "${closure_args[@]}"
}

run_negative_self_tests()
{
    local mode negative_rc
    for mode in missing extra forbidden; do
        set +e
        python3 "$ROOT/test/parity/base/rwlock_closure.py" "${closure_args[@]}" \
            --mode "$mode" > "$IMP/negative.$mode.log" 2>&1
        negative_rc=$?
        set -e
        [[ $negative_rc -ne 0 ]] || fail "negative mode $mode returned zero"
        grep -Fq "RWLOCK_CLOSURE FAIL mode=$mode" "$IMP/negative.$mode.log" ||
            fail "negative mode $mode did not execute real analyzer"
        echo "RWLOCK_NEGATIVE mode=$mode rc=$negative_rc status=PASS"
    done
}

require_tools
check_compiler
echo "RWLOCK_COMPILER source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"
echo "RWLOCK_DISK_BEFORE available_kb=$(df -Pk / | awk 'NR==2 {print $4}')"
build_cpp_oracle
build_base
run_valid_parity
run_invalid_read
run_invalid_write
build_roots_and_graphs
run_closure_proof
run_negative_self_tests
echo "RWLOCK_STAGES cpp_oracle=1 cj_valid=1 invalid_read=1 invalid_write=1 final_bc=1 object=1 negatives=3 status=PASS"
echo "run_rwlock_probe: PASS"
