#!/usr/bin/env bash
# Fail-closed check that CMake and parity runners consume one Linux bridge manifest.
set -euo pipefail

ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)
MANIFEST="$ROOT/rt0/linux_bridge_sources.txt"
OUT=${OUT:-"$ROOT/out/rt0-manifest-gate"}
RUNTIME_ROOT=${RUNTIME_ROOT:-/root/cj_build/cangjie_runtime/runtime}

fail()
{
    echo "rt0_manifest_gate: FAIL $*" >&2
    exit 1
}

mapfile -t sources < "$MANIFEST"
[[ ${#sources[@]} -gt 0 ]] || fail "empty manifest"
[[ $(printf '%s\n' "${sources[@]}" | LC_ALL=C sort -u | wc -l) -eq ${#sources[@]} ]] ||
    fail "duplicate manifest source"
for source in "${sources[@]}"; do
    [[ "$source" == os/Linux/*.cpp && -f "$ROOT/rt0/$source" ]] ||
        fail "invalid source $source"
done

cmake -S "$ROOT" -B "$OUT/cmake" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_ASM_COMPILER=clang \
    -DCANGJIE_RUNTIME_SOURCE="$RUNTIME_ROOT"
cmake --build "$OUT/cmake" --target cjcj_rt0 --parallel
archive="$OUT/cmake/lib/libcjcj_rt0.a"
[[ -s "$archive" ]] || fail "missing CMake archive"

members=$(ar t "$archive")
for source in "${sources[@]}"; do
    member="${source##*/}.o"
    count=$(grep -Fxc "$member" <<< "$members" || true)
    [[ $count -eq 1 ]] || fail "archive member $member count=$count"
done

expected_symbols=(
    cj_atomic_flag_clear
    cj_atomic_flag_test_and_set
    cj_atomic_i32_cas
    cj_atomic_i32_fetch_sub
    cj_atomic_i32_load
    cj_atomic_i32_store
    cj_atomic_u16_cas
    cj_atomic_u16_load
    cj_atomic_u16_store
    cj_atomic_u8_cas
    cj_atomic_u8_load
    cj_atomic_u8_store
    cj_pthread_spin_init
    cj_pthread_spin_lock
    cj_pthread_spin_trylock
    cj_pthread_spin_unlock
    cj_stateword_u16_cas
)
actual_symbols=$(nm -g --defined-only "$archive" |
    awk '$3 ~ /^(cj_atomic_|cj_pthread_spin_|cj_stateword_)/ {print $3}' |
    LC_ALL=C sort)
expected_sorted=$(printf '%s\n' "${expected_symbols[@]}" | LC_ALL=C sort)
[[ "$actual_symbols" == "$expected_sorted" ]] || {
    diff -u <(printf '%s\n' "$expected_sorted") <(printf '%s\n' "$actual_symbols") >&2 || true
    fail "atomic/spin symbol set mismatch"
}
for symbol in "${expected_symbols[@]}"; do
    count=$(nm -g --defined-only "$archive" | awk -v symbol="$symbol" '$3 == symbol {++n} END {print n+0}')
    [[ $count -eq 1 ]] || fail "symbol $symbol definition count=$count"
done

grep -Fq 'linux_bridge_sources.txt' "$ROOT/rt0/CMakeLists.txt" ||
    fail "CMake does not consume manifest"
grep -Fq 'linux_bridge_sources.txt' "$ROOT/test/parity/heap/run_regioninfo_probe.sh" ||
    fail "RegionInfo runner does not consume manifest"

echo "RT0_MANIFEST sources=${#sources[@]} archive_members=$(wc -l <<< "$members") consumers=2 status=PASS"
echo "RT0_SYMBOLS atomic=12 spin=4 stateword=1 unique=17 unexpected=0 status=PASS"
echo "RT0_PLATFORMS linux_x86_64=EXECUTED linux_aarch64=DEBT ohos=DEBT macos=DEBT ios=DEBT win64=DEBT status=PASS"
echo "rt0_manifest_gate: PASS"
