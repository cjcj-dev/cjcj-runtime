#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)
MANIFEST="$ROOT/test/compiler_identity.sh"
source "$MANIFEST"

fail()
{
    printf 'COMPILER_IDENTITY_GATE FAIL %s\n' "$*" >&2
    exit 1
}

mutate_assignment()
{
    local input=$1 output=$2 key=$3 value=$4
    awk -v key="$key" -v value="$value" '
        index($0, key "=") == 1 { print key "=" value; next }
        { print }
    ' "$input" > "$output"
}

run_negative()
{
    local axis=$1 key=$2 value=$3 case_manifest trace stdout stderr rc
    case_manifest="$TMP/$axis.manifest.sh"
    trace="$TMP/$axis.execve"
    stdout="$TMP/$axis.stdout"
    stderr="$TMP/$axis.stderr"
    mutate_assignment "$MANIFEST" "$case_manifest" "$key" "$value"
    set +e
    strace -f -qq -e trace=execve -o "$trace" \
        bash -c 'set -euo pipefail; source "$1"; "$CJC" --version >/dev/null' \
        identity-negative "$case_manifest" >"$stdout" 2>"$stderr"
    rc=$?
    set -e
    [[ "$rc" -ne 0 ]] || fail "negative axis=$axis unexpectedly succeeded"
    if grep -Eq 'execve\("[^"]*cjcj::cjc"' "$trace"; then
        fail "negative axis=$axis reached first cjc invocation"
    fi
    grep -Fq 'RUNTIME_TOOLCHAIN_INTAKE FAIL' "$stderr" ||
        fail "negative axis=$axis did not fail in identity manifest"
    printf 'IDENTITY_NEGATIVE axis=%s rc=%s first_cjc_invocations=0 status=PASS\n' "$axis" "$rc"
}

TMP=$(mktemp -d /tmp/rttoolchain-identity.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

printf 'IDENTITY compiler_path=%s source=%s tree=%s sha256=%s size=%s status=PASS\n' \
    "$SELFHOST_CJC" "$COMPILER_SOURCE" "$COMPILER_TREE" "$COMPILER_SHA256" "$COMPILER_SIZE"
printf 'IDENTITY fork_runtime=%s source=%s tree=%s sha256=%s size=%s status=PASS\n' \
    "$RUNTIME_FORK_LIB" "$RUNTIME_FORK_SOURCE" "$RUNTIME_FORK_TREE" "$RUNTIME_FORK_SHA256" "$RUNTIME_FORK_SIZE"
printf 'IDENTITY llc=%s source=%s sha256=%s size=%s status=PASS\n' \
    "$RUNTIME_LLC" "$RUNTIME_LLVM_SOURCE" "$RUNTIME_LLC_SHA256" "$RUNTIME_LLC_SIZE"
printf 'IDENTITY shim=%s source_blob=%s sha256=%s size=%s status=PASS\n' \
    "$RUNTIME_SHIM" "$RUNTIME_SHIM_SOURCE_BLOB" "$RUNTIME_SHIM_SHA256" "$RUNTIME_SHIM_SIZE"
printf 'IDENTITY ci_run=%s artifact=%s scope=%s status=PASS\n' \
    "$RUNTIME_CI_RUN" "$RUNTIME_FIXED_TOOLS_ARTIFACT" "$COMPILER_ACCEPTANCE_SCOPE"

run_negative toolchain_root RUNTIME_COMPILER_ROOT "'$RUNTIME_COMPILER_ROOT.tampered'"
run_negative compiler_path SELFHOST_CJC "'$SELFHOST_CJC.tampered'"
run_negative compiler_source COMPILER_SOURCE "${COMPILER_SOURCE}x"
run_negative compiler_tree COMPILER_TREE "${COMPILER_TREE}x"
run_negative compiler_sha COMPILER_SHA256 "${COMPILER_SHA256}x"
run_negative compiler_size COMPILER_SIZE "$((COMPILER_SIZE + 1))"
run_negative runtime_path RUNTIME_FORK_LIB "'$RUNTIME_FORK_LIB.tampered'"
run_negative runtime_source RUNTIME_FORK_SOURCE "${RUNTIME_FORK_SOURCE}x"
run_negative runtime_tree RUNTIME_FORK_TREE "${RUNTIME_FORK_TREE}x"
run_negative runtime_sha RUNTIME_FORK_SHA256 "${RUNTIME_FORK_SHA256}x"
run_negative runtime_size RUNTIME_FORK_SIZE "$((RUNTIME_FORK_SIZE + 1))"
run_negative llc_path RUNTIME_LLC "'$RUNTIME_LLC.tampered'"
run_negative llc_source RUNTIME_LLVM_SOURCE "${RUNTIME_LLVM_SOURCE}x"
run_negative llc_sha RUNTIME_LLC_SHA256 "${RUNTIME_LLC_SHA256}x"
run_negative llc_size RUNTIME_LLC_SIZE "$((RUNTIME_LLC_SIZE + 1))"
run_negative llc_runpath RUNTIME_LLC_RUNPATH "'${RUNTIME_LLC_RUNPATH}.tampered'"
run_negative shim_path RUNTIME_SHIM "'$RUNTIME_SHIM.tampered'"
run_negative shim_source RUNTIME_SHIM_SOURCE_BLOB "${RUNTIME_SHIM_SOURCE_BLOB}x"
run_negative shim_sha RUNTIME_SHIM_SHA256 "${RUNTIME_SHIM_SHA256}x"
run_negative shim_size RUNTIME_SHIM_SIZE "$((RUNTIME_SHIM_SIZE + 1))"
run_negative artifact_manifest RUNTIME_TOOLCHAIN_MANIFEST "'$RUNTIME_TOOLCHAIN_MANIFEST.tampered'"
printf 'IDENTITY_NEGATIVE_MATRIX axes=21 first_cjc_invocations=0 status=PASS\n'
