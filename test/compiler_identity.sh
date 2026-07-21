#!/usr/bin/env bash
# Sole published compiler/toolchain identity for runtime validation.
# Sourcing this file validates and activates one immutable Linux-x86_64 suite.

RUNTIME_COMPILER_ROOT=/root/cj_build/runtime_compilers/4a1773a05245cfef0259bebb998ac78038a04301
RUNTIME_TOOLCHAIN_MANIFEST="$RUNTIME_COMPILER_ROOT/TOOLCHAIN-MANIFEST"
SELFHOST_CJC="$RUNTIME_COMPILER_ROOT/bin/cjcj::cjc"
COMPILER_SOURCE=4a1773a05245cfef0259bebb998ac78038a04301
COMPILER_TREE=591ba6c9c244dcce737f859ac47be72209313fa3
COMPILER_SHA256=6812f6ff525792c7edf13e36c8b1faf18de70121c078916339afbb1fbed85b95
COMPILER_SHA="$COMPILER_SHA256"
COMPILER_SIZE=51278384

COMPILER_BUILD_TOOLCHAIN=nightly-1.2.0-alpha.20260721165458
REFERENCE_CJC="$RUNTIME_COMPILER_ROOT/bin/cjc"
REFERENCE_CJC_SHA256=ed806687b1fa0228b84d18b72e01cdc174d75d140cf5f7dd6267598fb80cb509
REFERENCE_CJC_SIZE=72930672
RUNTIME_LLVM_LIB="$RUNTIME_COMPILER_ROOT/third_party/llvm/lib/libLLVM-15.so"
RUNTIME_LLVM_SHA256=39819f28c84aa435c55ca22c9852ada0ef0124d141ab50ac8c4e87d4eabdb6cc
RUNTIME_LLVM_SIZE=72692416

RUNTIME_LLVM_SOURCE=4f61703c3225d60a7dc839718d822911628e6740
RUNTIME_LLC="$RUNTIME_COMPILER_ROOT/third_party/llvm/bin/llc"
RUNTIME_LLC_SHA256=d498353a70b3ef4e674dd68d1375a4f4ce39d3d2a1ce8e1ce71c10cafef9b9fd
RUNTIME_LLC_SIZE=39259304
RUNTIME_LLC_RUNPATH='$ORIGIN/../lib'
RUNTIME_SHIM="$RUNTIME_COMPILER_ROOT/toolchain-artifacts/cjselfhost_llvmshim.o"
RUNTIME_SHIM_SOURCE_BLOB=b3be32b5721f97a70925de19898e3be4769b16e6
RUNTIME_SHIM_SHA256=bb05dfd1fa584aa8456356064c3dd392c3588a13708327a6f899d9a09ec4fd47
RUNTIME_SHIM_SIZE=207776

RUNTIME_FORK_SOURCE=f56e60bfb05121f138f39dec46d7e0b38eb3165a
RUNTIME_FORK_TREE=f84b31a7c2fb09073de36f5ef36d128e21781ff9
RUNTIME_FORK_ANCHOR_BLOB=5d6345836b9028812929372876bf95a612f1cbf7
RUNTIME_FORK_LIB="$RUNTIME_COMPILER_ROOT/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
RUNTIME_FORK_SHA256=04add953be3919baf39ba714dbd2c5187189f43d80c42cc3a02605a704ab1079
RUNTIME_FORK_SIZE=12397072

RUNTIME_CI_RUN=29870114434
RUNTIME_FIXED_TOOLS_ARTIFACT=8510776386
RUNTIME_FIXED_TOOLS_WORKFLOW_BLOB=3059798a91d98c1791fe5d4a46dc42dc446a7379
RUNTIME_BUILD_SCRIPT_BLOB=c84cc2641bbfdd752fb3e31fc0c4773928ecb6bc
COMPILER_ACCEPTANCE_SCOPE=linux_x86_64-runtime-package-abi-parity

runtime_identity_fail()
{
    printf 'RUNTIME_TOOLCHAIN_INTAKE FAIL %s\n' "$*" >&2
    return 1
}

runtime_file_sha256()
{
    local digest
    digest=$(sha256sum "$1") || return 1
    printf '%s\n' "${digest%% *}"
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

runtime_tree_for_commit()
{
    git -C "$1" rev-parse "$2^{tree}" 2>/dev/null
}

runtime_blob_at_path()
{
    git -C "$1" ls-tree "$2" -- "$3" 2>/dev/null | awk 'NR == 1 { print $3 }'
}

runtime_manifest_has()
{
    grep -Fqx "$1" "$RUNTIME_TOOLCHAIN_MANIFEST" ||
        runtime_identity_fail "artifact manifest mismatch field=$1"
}

runtime_resolved_dependency()
{
    local binary=$1 library=$2
    ldd "$binary" 2>/dev/null | awk -v library="$library" '$1 == library { print $3; exit }'
}

runtime_check_source_identity()
{
    local actual
    actual=$(runtime_tree_for_commit /root/cj_build/cjcj "$COMPILER_SOURCE") ||
        runtime_identity_fail "compiler source commit absent source=$COMPILER_SOURCE" || return 1
    [[ "$actual" == "$COMPILER_TREE" ]] ||
        runtime_identity_fail "compiler tree expected=$COMPILER_TREE actual=$actual" || return 1
    actual=$(runtime_blob_at_path /root/cj_build/cjcj "$COMPILER_SOURCE" runtime_shim/cjselfhost_llvmshim.cpp)
    [[ "$actual" == "$RUNTIME_SHIM_SOURCE_BLOB" ]] ||
        runtime_identity_fail "shim source blob expected=$RUNTIME_SHIM_SOURCE_BLOB actual=$actual" || return 1
    actual=$(runtime_blob_at_path /root/cj_build/cjcj "$COMPILER_SOURCE" .github/workflows/build-fixed-llc.yml)
    [[ "$actual" == "$RUNTIME_FIXED_TOOLS_WORKFLOW_BLOB" ]] ||
        runtime_identity_fail "fixed-tools workflow blob expected=$RUNTIME_FIXED_TOOLS_WORKFLOW_BLOB actual=$actual" || return 1
    actual=$(runtime_blob_at_path /root/cj_build/cjcj "$COMPILER_SOURCE" ci/build_patched_runtime.sh)
    [[ "$actual" == "$RUNTIME_BUILD_SCRIPT_BLOB" ]] ||
        runtime_identity_fail "runtime build script blob expected=$RUNTIME_BUILD_SCRIPT_BLOB actual=$actual" || return 1

    actual=$(runtime_tree_for_commit /root/cj_build/cangjie_runtime "$RUNTIME_FORK_SOURCE") ||
        runtime_identity_fail "runtime fork source commit absent source=$RUNTIME_FORK_SOURCE" || return 1
    [[ "$actual" == "$RUNTIME_FORK_TREE" ]] ||
        runtime_identity_fail "runtime fork tree expected=$RUNTIME_FORK_TREE actual=$actual" || return 1
    actual=$(runtime_blob_at_path /root/cj_build/cangjie_runtime "$RUNTIME_FORK_SOURCE" runtime/src/StackManager.cpp)
    [[ "$actual" == "$RUNTIME_FORK_ANCHOR_BLOB" ]] ||
        runtime_identity_fail "runtime fork anchor expected=$RUNTIME_FORK_ANCHOR_BLOB actual=$actual" || return 1
}

runtime_check_artifact_manifest()
{
    [[ -f "$RUNTIME_TOOLCHAIN_MANIFEST" ]] ||
        runtime_identity_fail "artifact manifest missing path=$RUNTIME_TOOLCHAIN_MANIFEST" || return 1
    runtime_manifest_has "compiler_source=$COMPILER_SOURCE" || return 1
    runtime_manifest_has "compiler_tree=$COMPILER_TREE" || return 1
    runtime_manifest_has "compiler_sha256=$COMPILER_SHA256" || return 1
    runtime_manifest_has "runtime_source=$RUNTIME_FORK_SOURCE" || return 1
    runtime_manifest_has "runtime_sha256=$RUNTIME_FORK_SHA256" || return 1
    runtime_manifest_has "llvm_fork_source=$RUNTIME_LLVM_SOURCE" || return 1
    runtime_manifest_has "llvm_llc_sha256=$RUNTIME_LLC_SHA256" || return 1
    runtime_manifest_has "shim_source_blob=$RUNTIME_SHIM_SOURCE_BLOB" || return 1
    runtime_manifest_has "shim_sha256=$RUNTIME_SHIM_SHA256" || return 1
    runtime_manifest_has "ci_run=$RUNTIME_CI_RUN" || return 1
    runtime_manifest_has "fixed_tools_artifact=$RUNTIME_FIXED_TOOLS_ARTIFACT" || return 1
}

activate_runtime_compiler()
{
    local writable_entry absolute_link actual_runpath elf_type shim_exports resolved

    [[ "$(readlink -f "$RUNTIME_COMPILER_ROOT")" == "$RUNTIME_COMPILER_ROOT" ]] ||
        runtime_identity_fail "toolchain root is not concrete path=$RUNTIME_COMPILER_ROOT" || return 1
    [[ -d "$RUNTIME_COMPILER_ROOT" ]] ||
        runtime_identity_fail "toolchain root missing path=$RUNTIME_COMPILER_ROOT" || return 1
    writable_entry=$(find "$RUNTIME_COMPILER_ROOT" \( -type f -o -type d \) -perm /222 -print -quit)
    [[ -z "$writable_entry" ]] ||
        runtime_identity_fail "toolchain contains writable entry path=$writable_entry" || return 1
    absolute_link=$(find "$RUNTIME_COMPILER_ROOT" -type l -lname '/*' -print -quit)
    [[ -z "$absolute_link" ]] ||
        runtime_identity_fail "toolchain contains external absolute symlink path=$absolute_link" || return 1

    runtime_check_source_identity || return 1
    runtime_check_artifact_manifest || return 1
    runtime_check_file_identity compiler "$SELFHOST_CJC" "$COMPILER_SHA256" "$COMPILER_SIZE" || return 1
    runtime_check_file_identity reference_cjc "$REFERENCE_CJC" "$REFERENCE_CJC_SHA256" "$REFERENCE_CJC_SIZE" || return 1
    runtime_check_file_identity LLVM "$RUNTIME_LLVM_LIB" "$RUNTIME_LLVM_SHA256" "$RUNTIME_LLVM_SIZE" || return 1
    runtime_check_file_identity llc "$RUNTIME_LLC" "$RUNTIME_LLC_SHA256" "$RUNTIME_LLC_SIZE" || return 1
    runtime_check_file_identity shim "$RUNTIME_SHIM" "$RUNTIME_SHIM_SHA256" "$RUNTIME_SHIM_SIZE" || return 1
    runtime_check_file_identity fork_runtime "$RUNTIME_FORK_LIB" "$RUNTIME_FORK_SHA256" "$RUNTIME_FORK_SIZE" || return 1

    [[ -x "$SELFHOST_CJC" && -x "$RUNTIME_LLC" ]] ||
        runtime_identity_fail "compiler or llc is not executable" || return 1
    actual_runpath=$(readelf -d "$RUNTIME_LLC" | sed -n 's/.*Library runpath: \[\(.*\)\]/\1/p')
    [[ "$actual_runpath" == "$RUNTIME_LLC_RUNPATH" ]] ||
        runtime_identity_fail "llc RUNPATH expected=$RUNTIME_LLC_RUNPATH actual=$actual_runpath" || return 1
    [[ $(readelf -d "$RUNTIME_LLC" | grep -Fc 'Shared library: [libLLVM-15.so]' || true) == 0 ]] ||
        runtime_identity_fail "llc unexpectedly depends on SDK libLLVM" || return 1

    elf_type=$(readelf -h "$RUNTIME_SHIM" | awk -F: '/^[[:space:]]*Type:/{gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
    [[ "$elf_type" == REL* ]] || runtime_identity_fail "shim is not relocatable type=$elf_type" || return 1
    shim_exports=$(nm -C "$RUNTIME_SHIM" | grep -cE ' T (LLVMGlobalObjectAddStringAttribute|LLVMSelfhost|CJOF)' || true)
    [[ "$shim_exports" -ge 90 ]] || runtime_identity_fail "shim export surface too small count=$shim_exports" || return 1
    grep -qa '\.cjmetadata' "$RUNTIME_FORK_LIB" ||
        runtime_identity_fail "fork runtime lacks .cjmetadata discriminator" || return 1
    [[ $(readelf -d "$RUNTIME_FORK_LIB" | grep -Fc 'Library soname: [libcangjie-runtime.so]' || true) == 1 ]] ||
        runtime_identity_fail "fork runtime SONAME mismatch" || return 1

    resolved=$(runtime_resolved_dependency "$SELFHOST_CJC" libLLVM-15.so)
    [[ "$(readlink -f "$resolved")" == "$RUNTIME_LLVM_LIB" ]] ||
        runtime_identity_fail "compiler resolved LLVM outside tuple actual=$resolved" || return 1
    resolved=$(runtime_resolved_dependency "$SELFHOST_CJC" libcangjie-runtime.so)
    [[ "$(readlink -f "$resolved")" == "$RUNTIME_FORK_LIB" ]] ||
        runtime_identity_fail "compiler resolved runtime outside tuple actual=$resolved" || return 1

    CANGJIE_HOME="$RUNTIME_COMPILER_ROOT"
    CJC="$SELFHOST_CJC"
    TOOLCHAIN="$CANGJIE_HOME"
    LLVM_BIN="$CANGJIE_HOME/third_party/llvm/bin"
    RUNTIME_TOOLCHAIN_RT_LIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
    LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$RUNTIME_TOOLCHAIN_RT_LIB:$CANGJIE_HOME/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    PATH="$LLVM_BIN:$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$PATH"
    export RUNTIME_COMPILER_ROOT RUNTIME_TOOLCHAIN_MANIFEST SELFHOST_CJC
    export COMPILER_SOURCE COMPILER_TREE COMPILER_SHA256 COMPILER_SHA COMPILER_SIZE
    export COMPILER_BUILD_TOOLCHAIN REFERENCE_CJC RUNTIME_LLVM_LIB RUNTIME_LLC RUNTIME_SHIM
    export RUNTIME_FORK_SOURCE RUNTIME_FORK_LIB COMPILER_ACCEPTANCE_SCOPE
    export CANGJIE_HOME CJC TOOLCHAIN LLVM_BIN RUNTIME_TOOLCHAIN_RT_LIB LD_LIBRARY_PATH PATH

    printf 'RUNTIME_TOOLCHAIN_INTAKE compiler=%s runtime=%s llc=%s shim=%s status=PASS\n' \
        "$COMPILER_SOURCE" "$RUNTIME_FORK_SOURCE" "$RUNTIME_LLVM_SOURCE" "$RUNTIME_SHIM_SOURCE_BLOB"
}

activate_runtime_compiler || exit 1
