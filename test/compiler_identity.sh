#!/usr/bin/env bash
# Sole published compiler identity for fail-closed runtime parity runners.
# Re-baseline only after source/binary/toolchain/acceptance evidence is published.
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/runtime_compilers/3479da98334436e1949d2a3bbc3fd6d53ffb2fb4/bin/cjcj::cjc}
COMPILER_SOURCE=3479da98334436e1949d2a3bbc3fd6d53ffb2fb4
COMPILER_SHA=fb54b5011a01c1e975910c861f19091c1a66a981ab0cfa13683d9dcac63f0d09
COMPILER_SIZE=49566664
COMPILER_BUILD_TOOLCHAIN=nightly-1.2.0-alpha.20260712020030
COMPILER_BUILD_LLVM_SHA256=8f685b53f65df0284b75e8723246085aa20e3f6b8b06e4c02b44110755b8c444
COMPILER_ACCEPTANCE_SCOPE=linux_x86_64-runtime-packages-and-parity

check_runtime_compiler_identity()
{
    local actual_sha actual_size
    [[ -x "$SELFHOST_CJC" ]] || return 1
    actual_sha=$(sha256sum "$SELFHOST_CJC")
    actual_sha=${actual_sha%% *}
    actual_size=$(stat -c %s "$SELFHOST_CJC")
    [[ "$actual_sha" == "$COMPILER_SHA" && "$actual_size" == "$COMPILER_SIZE" ]] || return 1
    git -C /root/cj_build/cjcj cat-file -e "$COMPILER_SOURCE^{commit}" 2>/dev/null
}
