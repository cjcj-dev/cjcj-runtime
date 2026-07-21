#!/usr/bin/env bash
# Fail-closed Base/Types.h:21-55 host ABI parity and source branch audit.
set -euo pipefail

ROOT=$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd -P)
SELFHOST_CJC=/root/cj_build/cjcj/target/release/bin/cjcj::cjc
COMPILER_SOURCE=27b9b88c2a7bc68acfcc870e7b394404a8f6c356
COMPILER_SHA=d99659d1cc797eb179e349bdcff1c635086680fba6b9be5dac61e39eb570b44c
COMPILER_SIZE=98479472
CPP_RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
export PATH=/root/.cjv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
CJC_BIN_DIR=$(cd "${SELFHOST_CJC%/*}" && pwd -P)
SELFHOST_RT="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
export LD_LIBRARY_PATH="$SELFHOST_RT:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
export cjHeapSize=24GB

fail()
{
    echo "run_types_probe: FAIL $*" >&2
    exit 1
}

check_compiler()
{
    local actual_sha actual_size
    [[ -x "$SELFHOST_CJC" ]] || fail "pinned compiler is not executable"
    actual_sha=$(sha256sum "$SELFHOST_CJC")
    actual_sha=${actual_sha%% *}
    actual_size=$(stat -c %s "$SELFHOST_CJC")
    [[ "$actual_sha" == "$COMPILER_SHA" ]] || fail "compiler sha drift actual=$actual_sha"
    [[ "$actual_size" == "$COMPILER_SIZE" ]] || fail "compiler size drift actual=$actual_size"
    git -C /root/cj_build/cjcj cat-file -e "$COMPILER_SOURCE^{commit}" 2>/dev/null ||
        fail "compiler source commit absent"
}

require_host_tools_and_inputs()
{
    local input tool
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
        fail "executable target must be Linux x86_64"
    for tool in cat cmp g++ git grep mktemp rm sha256sum stat uname; do
        command -v "$tool" >/dev/null || fail "missing tool $tool"
    done
    for input in \
        "$ROOT/src/rt.base/Types.cj" \
        "$ROOT/test/parity/base/types_probe.cj" \
        "$ROOT/test/parity/base/types_ref.cpp" \
        "$CPP_RUNTIME_ROOT/src/Base/Types.h" \
        "$ROOT/rt0/os/Linux/Panic.cpp" \
        "$ROOT/rt0/os/Linux/Atomic.cpp" \
        "$ROOT/rt0/os/Linux/SpinLock.cpp"; do
        [[ -r "$input" ]] || fail "missing oracle input $input"
    done
    [[ -d "$SELFHOST_RT" ]] || fail "missing pinned selfhost runtime libraries"
    [[ -d "$CANGJIE_HOME/third_party/llvm/lib" ]] || fail "missing pinned nightly LLVM libraries"
    [[ -d "$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" ]] ||
        fail "missing pinned nightly runtime libraries"
}

assert_source_branches()
{
    local source
    source=$(<"$ROOT/src/rt.base/Types.cj")
    [[ "$source" == *$'@When[os == "macOS" || os == "iOS"]\npublic type Uptr = UInt64'* ]] ||
        fail "missing Apple Uptr branch"
    [[ "$source" == *$'@When[os != "macOS" && os != "iOS"]\npublic type Uptr = UIntNative'* ]] ||
        fail "missing non-Apple Uptr branch"
    [[ "$source" == *$'@When[arch == "arm"]\npublic type ArchUInt = UInt32'* ]] ||
        fail "missing 32-bit ARM ArchUInt branch"
    [[ "$source" == *$'@When[arch != "arm"]\npublic type ArchUInt = UInt64'* ]] ||
        fail "missing non-ARM ArchUInt branch"
}

require_host_tools_and_inputs
check_compiler
assert_source_branches
echo "TYPES_COMPILER path=$SELFHOST_CJC source=$COMPILER_SOURCE sha256=$COMPILER_SHA size=$COMPILER_SIZE status=PASS"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_types_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

check_compiler
"$SELFHOST_CJC" --package "$ROOT/src/rt.base" --output-type=staticlib \
    --int-overflow wrapping --output-dir "$TMP" -o librt.base.a

g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/SpinLock.cpp" -o "$TMP/SpinLock.o"

check_compiler
"$SELFHOST_CJC" "$ROOT/test/parity/base/types_probe.cj" --import-path "$TMP" \
    --int-overflow wrapping "$TMP/librt.base.a" "$TMP/Panic.o" "$TMP/Atomic.o" "$TMP/SpinLock.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/types_probe"

g++ -std=c++14 -O2 -I "$CPP_RUNTIME_ROOT/src" \
    "$ROOT/test/parity/base/types_ref.cpp" -o "$TMP/types_ref"

"$TMP/types_probe" > "$TMP/cangjie.records"
"$TMP/types_ref" > "$TMP/cpp.records"
cmp "$TMP/cpp.records" "$TMP/cangjie.records"
cat "$TMP/cangjie.records"

tree_sha=$(git -C "$ROOT" rev-parse 'HEAD^{tree}')
cpp_sha=$(sha256sum "$TMP/types_ref")
cpp_sha=${cpp_sha%% *}
cj_sha=$(sha256sum "$TMP/types_probe")
cj_sha=${cj_sha%% *}
echo "TYPES_EVIDENCE tree_sha=$tree_sha compiler_path=$SELFHOST_CJC compiler_source=$COMPILER_SOURCE compiler_sha256=$COMPILER_SHA compiler_size=$COMPILER_SIZE cpp_sha256=$cpp_sha cj_sha256=$cj_sha"
echo "TYPES_PLATFORM apple_branches=2 arm_branches=2 linux_x86_64=EXECUTED status=PASS"
echo "run_types_probe: PASS"
