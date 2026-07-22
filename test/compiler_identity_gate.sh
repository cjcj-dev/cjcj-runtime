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
    local findings caller
    findings=$(rg -n --hidden \
        --glob '!compiler_identity.sh' --glob '!compiler_identity_gate.sh' \
        "$RUNTIME_COMPILER_ROOT|$COMPILER_SOURCE|$COMPILER_SHA256|$COMPILER_SIZE|d996" \
        "$ROOT/test" || true)
    [[ -z "$findings" ]] || fail "duplicate or stale identity constants:\n$findings"

    findings=$(rg -n --hidden \
        --glob '!compiler_identity.sh' --glob '!compiler_identity_gate.sh' \
        '/root/cj_build/cjcj/(target/)?release/bin/cjcj::cjc|/root/cj_build/cjcj/target/release/bin|cangjie_compiler_selfhost.*/bin/.*cjc' \
        "$ROOT/test" || true)
    [[ -z "$findings" ]] || fail "mutable checkout compiler default:\n$findings"

    findings=$(rg -n --hidden \
        --glob '!compiler_identity.sh' --glob '!compiler_identity_gate.sh' \
        'SELFHOST_CJC=\$\{|CJC=\$\{|CANGJIE_HOME=\$\{' "$ROOT/test" || true)
    [[ -z "$findings" ]] || fail "identity environment override remains:\n$findings"

    while IFS= read -r caller; do
        [[ "$caller" == "$MANIFEST" || "$caller" == "$ROOT/test/compiler_identity_gate.sh" ]] && continue
        rg -q 'source .*compiler_identity\.sh' "$caller" ||
            fail "compiler caller does not source manifest path=$caller"
    done < <(rg -l --glob '*.sh' --glob '*.py' \
        'cjcj::cjc|SELFHOST_CJC|(^|[^A-Z_])CJC([ =]|$)|run_staged_managed_host|difftest\.sh' \
        "$ROOT/test" | sort)

    printf 'COMPILER_IDENTITY_AUDIT duplicate_constants=0 stale_tuple=0 mutable_defaults=0 env_overrides=0 callers_manifest_only=1 status=PASS\n'
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
