#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/test/compiler_identity.sh"
source "$MANIFEST"

fail()
{
    printf 'COMPILER_IDENTITY_GATE FAIL %s\n' "$*" >&2
    exit 1
}

audit_test_tree()
{
    local findings caller caller_count=0 script_count
    script_count=$(find "$ROOT/test" -type f \( -name '*.sh' -o -name '*.py' \) | wc -l)
    findings=$(rg -n --hidden \
        --glob '!compiler_identity.sh' --glob '!compiler_identity_gate.sh' \
        "$RUNTIME_COMPILER_ROOT|$COMPILER_SOURCE|$COMPILER_SHA256|$COMPILER_SIZE|d996|20260619020029|/root/\\.cjv/toolchains" \
        "$ROOT/test" || true)
    [[ -z "$findings" ]] || fail "duplicate or stale identity constants:\n$findings"

    findings=$(rg -n --hidden \
        --glob '!compiler_identity.sh' --glob '!compiler_identity_gate.sh' \
        '/root/cj_build/cjcj/(target/)?release/bin/cjcj::cjc|/root/cj_build/cjcj/target/release/bin|cangjie_compiler_selfhost.*/bin/.*cjc' \
        "$ROOT/test" || true)
    [[ -z "$findings" ]] || fail "mutable checkout compiler default:\n$findings"

    findings=$(rg -n --hidden \
        --glob '!compiler_identity.sh' --glob '!compiler_identity_gate.sh' \
        'SELFHOST_CJC=\$\{|CJC=\$\{|CANGJIE_HOME=\$\{|TOOLCHAIN=\$\{|LLVM_BIN=\$\{' \
        "$ROOT/test" || true)
    [[ -z "$findings" ]] || fail "identity environment override remains:\n$findings"

    while IFS= read -r caller; do
        [[ "$caller" == "$MANIFEST" || "$caller" == "$ROOT/test/compiler_identity_gate.sh" ]] && continue
        caller_count=$((caller_count + 1))
        rg -q 'source .*compiler_identity\.sh' "$caller" ||
            fail "compiler caller does not source manifest path=$caller"
    done < <(rg -l --glob '*.sh' --glob '*.py' \
        'cjcj::cjc|SELFHOST_CJC|(^|[^A-Z_])CJC([ =]|$)|REFERENCE_CJC|run_(staged_managed_host|managed_contract|official_control)|published_cjc\.sh|difftest\.sh' \
        "$ROOT/test" | sort)

    rg -q 'exec env -u LD_PRELOAD "\$SELFHOST_CJC"' "$ROOT/test/published_cjc.sh" ||
        fail 'published launcher does not strip tested-runtime LD_PRELOAD'
    rg -q 'runtime_check_file_identity staged-compiler "\$STAGED_CJC"' \
        "$ROOT/test/contract/instance/run_staged_managed_host.sh" ||
        fail 'staged compiler is not rechecked after copy'

    printf 'COMPILER_IDENTITY_AUDIT scripts=%s callers=%s duplicate_constants=0 stale_tuple=0 mutable_defaults=0 env_overrides=0 tested_runtime_preload=0 staging_recheck=1 callers_manifest_only=1 status=PASS\n' \
        "$script_count" "$caller_count"
}

TMP=$(mktemp -d /tmp/rtidentity-r4-identity.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

printf 'COMPILER_IDENTITY path=%s source=%s sha256=%s size=%s toolchain=%s LLVM=%s LLVM_sha256=%s status=PASS\n' \
    "$SELFHOST_CJC" "$COMPILER_SOURCE" "$COMPILER_SHA256" "$COMPILER_SIZE" \
    "$COMPILER_BUILD_TOOLCHAIN" "$RUNTIME_LLVM_LIB" "$RUNTIME_LLVM_SHA256"

TAMPER_ROOT="$TMP/$COMPILER_SOURCE"
mkdir -p "$TAMPER_ROOT/bin"
cp --reflink=auto "$SELFHOST_CJC" "$TAMPER_ROOT/bin/cjcj::cjc"
truncate -s "$((COMPILER_SIZE - 1))" "$TAMPER_ROOT/bin/cjcj::cjc"
sed "s|^RUNTIME_COMPILER_ROOT=.*|RUNTIME_COMPILER_ROOT=$TAMPER_ROOT|" \
    "$MANIFEST" > "$TMP/tampered_identity.sh"

set +e
bash -c 'set -euo pipefail; source "$1"' identity-negative \
    "$TMP/tampered_identity.sh" >"$TMP/negative.stdout" 2>"$TMP/negative.stderr"
negative_rc=$?
set -e
[[ "$negative_rc" -ne 0 ]] || fail 'tampered compiler copy unexpectedly accepted'
grep -Fq 'RUNTIME_COMPILER_IDENTITY FAIL compiler' "$TMP/negative.stderr" ||
    fail 'tampered compiler copy did not fail in compiler identity check'
printf 'COMPILER_IDENTITY_NEGATIVE mutation=compiler_size_minus_1 expected_size=%s actual_size=%s rc=%s status=PASS\n' \
    "$COMPILER_SIZE" "$((COMPILER_SIZE - 1))" "$negative_rc"

audit_test_tree
