#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_barrier_protocol.XXXXXX")
trap 'find "$TMP" -depth -delete' EXIT
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
EXPECTED=(TryUpdateRefField TryUntagRefField IsOldPointer IsCurrentPointer FindToVersion GetAndTryTagRefField IsUnmovableFromObject TryForwardRefField ForwardObject RememberObjectInSatbBuffer IsHeapAddress)

inventory() {
    local input=$1
    grep -o 'CJ_RT_[A-Za-z0-9_]*(' "$input" | sed 's/^CJ_RT_//;s/($//' | sort -u
}
check_inventory() {
    local input=$1 label=$2 expected_file=$TMP/expected actual_file=$TMP/actual
    printf '%s\n' "${EXPECTED[@]}" | sort > "$expected_file"
    inventory "$input" > "$actual_file"
    if ! cmp -s "$expected_file" "$actual_file"; then
        echo "BARRIER_PROTOCOL_INVENTORY FAIL label=$label" >&2
        diff -u "$expected_file" "$actual_file" >&2 || true
        return 1
    fi
}

check_inventory "$ROOT/contract/cjcj_rt_barrier_protocol.h" header
check_inventory "$ROOT/rt0/BarrierProtocol.cpp" definition
check_inventory "$ROOT/src/rt.gc/BarrierProtocol.cj" cangjie
[[ $(grep -c '^extern "C"' "$ROOT/rt0/BarrierProtocol.cpp") -eq 11 ]]
[[ $(grep -c '^    func CJ_RT_' "$ROOT/src/rt.gc/BarrierProtocol.cj") -eq 33 ]]
for branch in '@When[os == "Linux" || env == "ohos"]' '@When[os == "macOS" || os == "iOS"]' '@When[os == "Windows"]'; do
    [[ $(grep -Fc "$branch" "$ROOT/src/rt.gc/BarrierProtocol.cj") -eq 11 ]]
done

sed '/CJ_RT_ForwardObject/d' "$ROOT/contract/cjcj_rt_barrier_protocol.h" > "$TMP/header.missing"
set +e
check_inventory "$TMP/header.missing" negative > "$TMP/negative.log" 2>&1
negative_rc=$?
set -e
[[ $negative_rc -ne 0 ]]
grep -Fq 'BARRIER_PROTOCOL_INVENTORY FAIL label=negative' "$TMP/negative.log"

CJTHREAD_INCLUDE_ARGS=()
while IFS= read -r include_dir; do CJTHREAD_INCLUDE_ARGS+=("-I$include_dir"); done < <(find "$RUNTIME_ROOT/src/CJThread/src" -type d)
g++ -std=c++17 -O2 -fPIC -DMRT_USE_CJTHREAD_RENAME -I"$ROOT/contract" -I"$RUNTIME_ROOT/include" -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/output/temp/include" -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "${CJTHREAD_INCLUDE_ARGS[@]}" -c "$ROOT/rt0/BarrierProtocol.cpp" -o "$TMP/BarrierProtocol.o"
nm --defined-only "$TMP/BarrierProtocol.o" | awk '$3 ~ /^CJ_RT_/ {print $3}' | sort > "$TMP/object.symbols"
sed 's/^/CJ_RT_/' "$TMP/expected" > "$TMP/expected.symbols"
cmp "$TMP/expected.symbols" "$TMP/object.symbols"
echo "BARRIER_PROTOCOL_CONTRACT wrappers=11 declarations=33 standalone=PASS negative_rc=$negative_rc status=PASS"
