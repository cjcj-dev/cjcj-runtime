#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME=/root/cj_build/cangjie_runtime/runtime
SELFHOST=/root/cj_build/cangjie_compiler_selfhost
BUILD="$ROOT/target/stackmap-parity"

objects=(
    "$SELFHOST/01_return.o"
    "$SELFHOST/09_nested_func.o"
    "$SELFHOST/38_geniface_struct_ret.o"
    "$SELFHOST/44_list_methods.o"
    "$SELFHOST/52_lambda.o"
    "$SELFHOST/58_array_struct.o"
    "$SELFHOST/75_varray_compound.o"
    "$SELFHOST/90_range_subscript.o"
    "$SELFHOST/108_nested_struct_field.o"
    "$SELFHOST/113_virtual_dispatch.o"
)

for object in "${objects[@]}"; do
    if [[ ! -f "$object" ]]; then
        echo "missing difftest object: $object" >&2
        exit 2
    fi
done

rm -rf "$BUILD"
mkdir -p "$BUILD/library"

common_includes=(
    -I"$ROOT/test/parity/stackmap"
)
oracle_includes=(
    -I"$ROOT/test/parity/stackmap/stubs"
    "${common_includes[@]}"
    -I"$RUNTIME/src"
    -I"$RUNTIME/third_party/third_party_bounds_checking_function/include"
)

g++ -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter -Wno-strict-aliasing -fno-strict-aliasing \
    "${oracle_includes[@]}" "$ROOT/test/parity/stackmap/cpp_stackmap_dump.cpp" \
    -o "$BUILD/cpp_stackmap_dump"
g++ -std=c++17 -O2 -Wall -Wextra "${common_includes[@]}" \
    -c "$ROOT/test/parity/stackmap/cangjie_driver.cpp" -o "$BUILD/cangjie_driver.o"

(
    cd "$BUILD"
    "$CJC" -p "$ROOT/src/rt.stackmap" --output-type=staticlib --int-overflow wrapping \
        -o "$BUILD/library" -Woff unused
    "$CJC" "$ROOT/src/rt.stackmap/stackmap.cj" "$ROOT/test/parity/stackmap/cangjie_dump.cj" \
        -o "$BUILD/cangjie_stackmap_dump" --set-runtime-rpath --int-overflow wrapping -Woff unused \
        --link-option "$BUILD/cangjie_driver.o" --link-option=-lstdc++ --link-option=-lgcc_s
)

forbidden_symbols=$(nm -u "$BUILD/library/librt.stackmap.a" | \
    grep -E 'CJ_MCC_(New|Write|Throw)|MCC_(New|Write)|malloc|calloc|realloc|RawArray' || true)
if [[ -n "$forbidden_symbols" ]]; then
    echo "$forbidden_symbols" >&2
    echo "forbidden allocation, barrier, or exception symbol in rt.stackmap" >&2
    exit 1
fi

cpp_dump="$BUILD/cpp.dump"
cangjie_dump="$BUILD/cangjie.dump"
"$BUILD/cpp_stackmap_dump" "${objects[@]}" > "$cpp_dump"
object_list=$(IFS=:; echo "${objects[*]}")
CJRT_STACKMAP_OBJECTS="$object_list" "$BUILD/cangjie_stackmap_dump" > "$cangjie_dump"

cmp "$cpp_dump" "$cangjie_dump"

gcc -c "$ROOT/test/parity/stackmap/synthetic_reg.s" -o "$BUILD/synthetic_reg.o"
"$BUILD/cpp_stackmap_dump" "$BUILD/synthetic_reg.o" > "$BUILD/synthetic.cpp.dump"
CJRT_STACKMAP_OBJECTS="$BUILD/synthetic_reg.o" "$BUILD/cangjie_stackmap_dump" > "$BUILD/synthetic.cangjie.dump"
cmp "$BUILD/synthetic.cpp.dump" "$BUILD/synthetic.cangjie.dump"
synthetic_reg_roots=$(awk '$1 == "E" && $2 == 4 { count++ } END { print count + 0 }' "$BUILD/synthetic.cpp.dump")
synthetic_derived_reg_roots=$(awk '$1 == "E" && $2 == 6 { count++ } END { print count + 0 }' "$BUILD/synthetic.cpp.dump")
if [[ "$synthetic_reg_roots" != 1 || "$synthetic_derived_reg_roots" != 1 ]]; then
    echo "synthetic register-root coverage is incomplete" >&2
    exit 1
fi

gcc -c "$ROOT/test/parity/stackmap/synthetic_wah.s" -o "$BUILD/synthetic_wah.o"
"$BUILD/cpp_stackmap_dump" "$BUILD/synthetic_wah.o" > "$BUILD/synthetic_wah.cpp.dump"
CJRT_STACKMAP_OBJECTS="$BUILD/synthetic_wah.o" "$BUILD/cangjie_stackmap_dump" \
    > "$BUILD/synthetic_wah.cangjie.dump"
cmp "$BUILD/synthetic_wah.cpp.dump" "$BUILD/synthetic_wah.cangjie.dump"
synthetic_wah_roots=$(awk '$1 == "E" && $2 == 5 { count++ } END { print count + 0 }' \
    "$BUILD/synthetic_wah.cpp.dump")
if [[ "$synthetic_wah_roots" != 33 ]]; then
    echo "synthetic WAH coverage is incomplete" >&2
    exit 1
fi

object_count=$(grep -c '^OBJECT ' "$cpp_dump")
function_count=$(grep -c '^FUNCTION ' "$cpp_dump")
event_count=$(grep -c '^E ' "$cpp_dump")
digest=$(sha256sum "$cpp_dump" | awk '{print $1}')

echo "STACKMAP_PARITY_OBJECTS=$object_count"
echo "STACKMAP_PARITY_FUNCTIONS=$function_count"
echo "STACKMAP_PARITY_EVENTS=$event_count"
for kind in 1 2 3 4 5 6 7 8 9; do
    count=$(awk -v kind="$kind" '$1 == "E" && $2 == kind { count++ } END { print count + 0 }' "$cpp_dump")
    echo "STACKMAP_PARITY_KIND_${kind}=$count"
done
echo "STACKMAP_PARITY_BYTE_DIFF=0"
echo "STACKMAP_PARITY_FIELD_DIFF=0"
echo "STACKMAP_FORBIDDEN_RUNTIME_SYMBOLS=0"
echo "STACKMAP_PARITY_SHA256=$digest"
echo "STACKMAP_SYNTHETIC_REG_ROOTS=$synthetic_reg_roots"
echo "STACKMAP_SYNTHETIC_DERIVED_REG_ROOTS=$synthetic_derived_reg_roots"
echo "STACKMAP_SYNTHETIC_WAH_ROOTS=$synthetic_wah_roots"
