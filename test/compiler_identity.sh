#!/usr/bin/env bash
# Sole immutable compiler/toolchain identity for runtime package, ABI, parity,
# contract, and gate runners. Sourcing validates and activates the published
# Linux-x86_64 tuple; every mismatch fails closed before compilation.

# Superseded 2026-07-24: the 2026-07-22 publication was
# path=/root/cj_build/runtime_compilers/3479da98334436e1949d2a3bbc3fd6d53ffb2fb4/bin/cjcj::cjc
# source=3479da98334436e1949d2a3bbc3fd6d53ffb2fb4
# sha256=fb54b5011a01c1e975910c861f19091c1a66a981ab0cfa13683d9dcac63f0d09
# size=49566664
# toolchain=nightly-1.2.0-alpha.20260712020030 + patched dynamic LLVM sha256 8f685b53f65df0284b75e8723246085aa20e3f6b8b06e4c02b44110755b8c444
# Re-baselined because ec4e20a8 carries the managed @FastNative/@NoHeapAlloc contract.
RUNTIME_COMPILER_ROOT=/root/cj_build/runtime_compilers/ec4e20a847ad463cba50baf80fe0e07ea4483176
SELFHOST_CJC="$RUNTIME_COMPILER_ROOT/bin/cjcj::cjc"
COMPILER_SOURCE=ec4e20a847ad463cba50baf80fe0e07ea4483176
COMPILER_SHA256=da0d394eed36e33eb15a6125b42b8273febd79a16f5cb669aa3b5cd34242d402
COMPILER_SHA="$COMPILER_SHA256"
COMPILER_SIZE=50033200

RUNTIME_TOOLCHAIN_ROOT="$RUNTIME_COMPILER_ROOT/compatible-toolchain-linux-x86_64"
COMPILER_BUILD_TOOLCHAIN='nightly-1.2.0-alpha.20260721165458 + fixed static LLVM llc sha256 d498353a70b3ef4e674dd68d1375a4f4ce39d3d2a1ce8e1ce71c10cafef9b9fd'
RUNTIME_LLVM_LIB="$RUNTIME_TOOLCHAIN_ROOT/third_party/llvm/lib/libLLVM-15.so"
RUNTIME_LLVM_SHA256=39819f28c84aa435c55ca22c9852ada0ef0124d141ab50ac8c4e87d4eabdb6cc
RUNTIME_LLVM_SIZE=72692416
RUNTIME_LLVM_OPT="$RUNTIME_TOOLCHAIN_ROOT/third_party/llvm/bin/opt"
RUNTIME_LLVM_LLC="$RUNTIME_TOOLCHAIN_ROOT/third_party/llvm/bin/llc"
RUNTIME_LLC_SHA256=d498353a70b3ef4e674dd68d1375a4f4ce39d3d2a1ce8e1ce71c10cafef9b9fd
RUNTIME_LLC_SIZE=39259304
RUNTIME_LLC_LIBLLVM_DT_NEEDED_COUNT=0
RUNTIME_LLC_RUNPATH='$ORIGIN/../lib'
RUNTIME_LLC_VERSION=15.0.4
RUNTIME_LLC_TARGET=x86_64-unknown-linux-gnu
COMPILER_ACCEPTANCE_SCOPE='Linux-x86_64 runtime package/ABI/parity runners; non-Linux remains execution debt'

runtime_identity_fail()
{
    printf 'RUNTIME_COMPILER_IDENTITY FAIL %s\n' "$*" >&2
    return 1
}

runtime_file_sha256()
{
    local digest
    digest=$(sha256sum "$1") || return 1
    printf '%s\n' "${digest%% *}"
}

runtime_resolved_llvm()
{
    ldd "$1" 2>/dev/null | awk '$1 == "libLLVM-15.so" { print $3; exit }'
}

runtime_check_file_identity()
{
    local label=$1 path=$2 expected_sha=$3 expected_size=$4 actual_sha actual_size
    [[ -f "$path" ]] || runtime_identity_fail "$label missing path=$path" || return 1
    actual_sha=$(runtime_file_sha256 "$path") ||
        runtime_identity_fail "$label sha256 unreadable path=$path" || return 1
    actual_size=$(stat -c %s "$path") ||
        runtime_identity_fail "$label size unreadable path=$path" || return 1
    [[ "$actual_sha" == "$expected_sha" ]] ||
        runtime_identity_fail "$label sha256 expected=$expected_sha actual=$actual_sha" || return 1
    [[ "$actual_size" == "$expected_size" ]] ||
        runtime_identity_fail "$label size expected=$expected_size actual=$actual_size" || return 1
}

runtime_check_llvm_resolution()
{
    local label=$1 tool=$2 resolved
    [[ -x "$tool" ]] || runtime_identity_fail "$label is not executable path=$tool" || return 1
    resolved=$(runtime_resolved_llvm "$tool")
    [[ -n "$resolved" ]] ||
        runtime_identity_fail "$label missing dynamic libLLVM-15.so resolution path=$tool" || return 1
    resolved=$(readlink -f "$resolved")
    [[ "$resolved" == "$RUNTIME_LLVM_LIB" ]] ||
        runtime_identity_fail "$label resolved LLVM outside tuple expected=$RUNTIME_LLVM_LIB actual=$resolved" || return 1
}

runtime_check_static_llc()
{
    local tool=$1 needed_count version_output
    [[ -x "$tool" ]] || runtime_identity_fail "llc is not executable path=$tool" || return 1
    needed_count=$(readelf -d "$tool" |
        grep -Ec 'Shared library: \[libLLVM[^]]*\]' || true)
    [[ "$needed_count" == "$RUNTIME_LLC_LIBLLVM_DT_NEEDED_COUNT" ]] ||
        runtime_identity_fail "llc libLLVM DT_NEEDED expected=$RUNTIME_LLC_LIBLLVM_DT_NEEDED_COUNT actual=$needed_count" || return 1
    version_output=$("$tool" --version 2>&1) ||
        runtime_identity_fail "llc --version failed path=$tool" || return 1
    grep -Fqx "  LLVM version $RUNTIME_LLC_VERSION" <<< "$version_output" ||
        runtime_identity_fail "llc version expected=$RUNTIME_LLC_VERSION" || return 1
    grep -Fqx "  Default target: $RUNTIME_LLC_TARGET" <<< "$version_output" ||
        runtime_identity_fail "llc target expected=$RUNTIME_LLC_TARGET" || return 1
}

activate_runtime_compiler()
{
    local actual_source writable_entry absolute_link actual_runpath

    [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] ||
        runtime_identity_fail "unsupported execution platform os=$(uname -s) arch=$(uname -m) debt=non-Linux" || return 1
    [[ "$(readlink -f "$SELFHOST_CJC")" == "$SELFHOST_CJC" ]] ||
        runtime_identity_fail "compiler path is not concrete path=$SELFHOST_CJC" || return 1
    actual_source=$(basename "$(dirname "$(dirname "$SELFHOST_CJC")")")
    [[ "$actual_source" == "$COMPILER_SOURCE" ]] ||
        runtime_identity_fail "compiler source expected=$COMPILER_SOURCE actual=$actual_source" || return 1
    [[ "$SELFHOST_CJC" == "$RUNTIME_COMPILER_ROOT/bin/cjcj::cjc" ]] ||
        runtime_identity_fail "compiler path is outside source root path=$SELFHOST_CJC" || return 1
    runtime_check_file_identity compiler "$SELFHOST_CJC" "$COMPILER_SHA256" "$COMPILER_SIZE" || return 1

    [[ "$RUNTIME_TOOLCHAIN_ROOT" == "$RUNTIME_COMPILER_ROOT/compatible-toolchain-linux-x86_64" ]] ||
        runtime_identity_fail "toolchain path is outside compiler tuple path=$RUNTIME_TOOLCHAIN_ROOT" || return 1
    [[ -d "$RUNTIME_TOOLCHAIN_ROOT" ]] ||
        runtime_identity_fail "toolchain root missing path=$RUNTIME_TOOLCHAIN_ROOT" || return 1
    writable_entry=$(find "$RUNTIME_TOOLCHAIN_ROOT" \( -type f -o -type d \) -perm /222 -print -quit)
    [[ -z "$writable_entry" ]] ||
        runtime_identity_fail "toolchain contains writable entry path=$writable_entry" || return 1
    absolute_link=$(find "$RUNTIME_TOOLCHAIN_ROOT" -type l -lname '/*' -print -quit)
    [[ -z "$absolute_link" ]] ||
        runtime_identity_fail "toolchain contains external absolute symlink path=$absolute_link" || return 1

    [[ "$RUNTIME_LLVM_LIB" == "$RUNTIME_TOOLCHAIN_ROOT/third_party/llvm/lib/libLLVM-15.so" ]] ||
        runtime_identity_fail "LLVM path is outside toolchain path=$RUNTIME_LLVM_LIB" || return 1
    runtime_check_file_identity LLVM "$RUNTIME_LLVM_LIB" "$RUNTIME_LLVM_SHA256" "$RUNTIME_LLVM_SIZE" || return 1
    [[ "$RUNTIME_LLVM_LLC" == "$RUNTIME_TOOLCHAIN_ROOT/third_party/llvm/bin/llc" ]] ||
        runtime_identity_fail "llc path is outside toolchain path=$RUNTIME_LLVM_LLC" || return 1
    runtime_check_file_identity llc "$RUNTIME_LLVM_LLC" "$RUNTIME_LLC_SHA256" "$RUNTIME_LLC_SIZE" || return 1

    runtime_check_static_llc "$RUNTIME_LLVM_LLC" || return 1
    actual_runpath=$(readelf -d "$RUNTIME_LLVM_LLC" |
        sed -n 's/.*Library runpath: \[\(.*\)\]/\1/p')
    [[ "$actual_runpath" == "$RUNTIME_LLC_RUNPATH" ]] ||
        runtime_identity_fail "llc RUNPATH expected=$RUNTIME_LLC_RUNPATH actual=$actual_runpath" || return 1

    CANGJIE_HOME="$RUNTIME_TOOLCHAIN_ROOT"
    REFERENCE_CJC="$CANGJIE_HOME/bin/cjc"
    CJC="$SELFHOST_CJC"
    TOOLCHAIN="$CANGJIE_HOME"
    LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
    RUNTIME_TOOLCHAIN_RT_LIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
    LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$RUNTIME_TOOLCHAIN_RT_LIB:$CANGJIE_HOME/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    PATH="$LLVM_BIN:$RUNTIME_COMPILER_ROOT/bin:$PATH"
    export RUNTIME_COMPILER_ROOT SELFHOST_CJC COMPILER_SOURCE COMPILER_SHA256 COMPILER_SHA COMPILER_SIZE
    export RUNTIME_TOOLCHAIN_ROOT COMPILER_BUILD_TOOLCHAIN RUNTIME_LLVM_LIB
    export RUNTIME_LLVM_SHA256 RUNTIME_LLVM_SIZE RUNTIME_LLVM_OPT RUNTIME_LLVM_LLC
    export RUNTIME_LLC_SHA256 RUNTIME_LLC_SIZE RUNTIME_LLC_LIBLLVM_DT_NEEDED_COUNT
    export RUNTIME_LLC_RUNPATH RUNTIME_LLC_VERSION RUNTIME_LLC_TARGET
    export COMPILER_ACCEPTANCE_SCOPE CANGJIE_HOME REFERENCE_CJC CJC TOOLCHAIN LLVM_BIN
    export RUNTIME_TOOLCHAIN_RT_LIB LD_LIBRARY_PATH PATH

    runtime_check_llvm_resolution compiler "$SELFHOST_CJC" || return 1
    runtime_check_llvm_resolution opt "$RUNTIME_LLVM_OPT" || return 1
}

activate_runtime_compiler || exit 1
