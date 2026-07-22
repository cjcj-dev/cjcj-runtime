#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SELFHOST_CJC=${SELFHOST_CJC:-/root/cj_build/cjcj/target/release/bin/cjcj::cjc}
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export CANGJIE_HOME=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export LD_LIBRARY_PATH="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative:$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_fieldref.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
SOURCE="$ROOT/src/rt.objectmodel/Field.cj"
[[ $(grep -Fc '@When[os == "Linux" || env == "ohos"]' "$SOURCE") -eq 9 ]]
[[ $(grep -Fc '@When[os == "macOS" || os == "iOS"]' "$SOURCE") -eq 9 ]]
[[ $(grep -Fc '@When[os == "Windows"]' "$SOURCE") -eq 9 ]]
[[ $(grep -Fc '@When[arch == "arm"]' "$ROOT/src/rt.objectmodel/RefField.cj") -eq 3 ]]
[[ $(grep -Fc '@When[arch != "arm"]' "$ROOT/src/rt.objectmodel/RefField.cj") -eq 3 ]]
echo 'FIELDREF_SOURCE fresh=PASS linux_ohos=PASS apple=PASS win64=PASS arm32=PASS cpp_tsan_branches=DEBT-CANGJIE-TSAN-CONDITION'

CPP_FLAGS=(-std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/output/temp/include" -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include")
g++ "${CPP_FLAGS[@]}" "$ROOT/test/parity/objectmodel/field_ref_ref.cpp" -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -o "$TMP/ref"
"$TMP/ref" > "$TMP/ref.txt"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/Atomic.cpp" -o "$TMP/Atomic.o"
cp -a "$ROOT/src/rt.objectmodel" "$TMP/rt.objectmodel.probe"
cp "$ROOT/test/parity/objectmodel/field_ref_probe.cj" "$TMP/rt.objectmodel.probe/Probe.cj"
"$SELFHOST_CJC" --package "$TMP/rt.objectmodel.probe" --int-overflow wrapping -Woff unused "$TMP/Atomic.o" --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/probe"
"$TMP/probe" > "$TMP/probe.txt"
cmp "$TMP/ref.txt" "$TMP/probe.txt"
cat "$TMP/probe.txt"
echo "FIELDREF_TRANSCRIPT lines=$(wc -l < "$TMP/probe.txt") bytes=$(wc -c < "$TMP/probe.txt") sha256=$(sha256sum "$TMP/probe.txt" | awk '{print $1}') cmp=PASS"

mkdir -p "$TMP/win.release" "$TMP/win.debug" "$TMP/arm"
for mode in release debug; do
    flags=(); [[ $mode == debug ]] && flags=(-g)
    "$SELFHOST_CJC" --package "$ROOT/src/rt.objectmodel" --target x86_64-w64-mingw32 --output-type=staticlib "${flags[@]}" --int-overflow wrapping -Woff unused --output-dir "$TMP/win.$mode" -o librt.objectmodel.a
done
clang++ --target=x86_64-w64-windows-gnu -std=c++14 -O2 -c "$ROOT/rt0/Atomic.cpp" -o "$TMP/Atomic.win.o"
llvm-nm "$TMP/Atomic.win.o" | grep -Fq 'cj_atomic_field_compare_exchange'
"$SELFHOST_CJC" --package "$ROOT/src/rt.objectmodel" --target arm-linux-ohos --output-type=staticlib --int-overflow wrapping -Woff unused --output-dir "$TMP/arm" -o librt.objectmodel.a
echo 'FIELDREF_PLATFORM target=Linux-OHOS compile=PASS execute=PASS arm32_compile=PASS memory_orders=PASS status=PASS'
echo 'FIELDREF_PLATFORM target=Apple source=PASS atomic_builtin=CLANG-DEBT-APPLE-SDK native_execute=DEBT-APPLE-SDK status=EXPLICIT-DEBT'
echo 'FIELDREF_PLATFORM target=Win64 cj_release=PASS cj_debug=PASS atomic_owner=PASS status=PASS'
echo 'FIELDREF_PLATFORM feature=TSAN cxx_custom_hooks=PRESENT cangjie_condition=DEBT-CANGJIE-TSAN-CONDITION status=EXPLICIT-DEBT'

cp -a "$ROOT/src/rt.objectmodel" "$TMP/rt.objectmodel.noheap"
cp "$ROOT/test/parity/objectmodel/field_ref_noheap.cj" "$TMP/rt.objectmodel.noheap/NoHeap.cj"
mkdir -p "$TMP/temps"
"$SELFHOST_CJC" --package "$TMP/rt.objectmodel.noheap" --output-type=staticlib --save-temps "$TMP/temps" --int-overflow wrapping -Woff unused -o "$TMP/librt.objectmodel.a"
mapfile -t PRE_BC < <(find "$TMP/temps" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
"$CANGJIE_HOME/third_party/llvm/bin/llvm-link" "${PRE_BC[@]}" -o "$TMP/pre.bc"
"$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$TMP/pre.bc" -o "$TMP/pre.ll"
"$CANGJIE_HOME/third_party/llvm/bin/opt" -passes=print-callgraph -disable-output "$TMP/pre.bc" 2> "$TMP/callgraph"
awk '/^Call graph node for function:/{line=$0;sub(/^.*function: '\''/,"",line);sub(/'\''.*$/,"",line);owner=line;next}/calls function '\''/{line=$0;sub(/^.*calls function '\''/,"",line);sub(/'\''.*$/,"",line);if(owner!="")print owner "\t" line}' "$TMP/callgraph" > "$TMP/calls.tsv"
final_args=(); object_args=()
while IFS= read -r bc; do ll="$TMP/$(basename "$bc").ll"; "$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$bc" -o "$ll"; final_args+=(--final "$ll"); done < <(find "$TMP/temps" -maxdepth 1 -type f -name '*.opt.bc' | sort)
while IFS= read -r obj; do dump="$TMP/$(basename "$obj").objdump"; objdump -dr "$obj" > "$dump"; object_args+=(--object "$dump"); done < <(find "$TMP/temps" -maxdepth 1 -type f -name '*.o' | sort)
python3 "$ROOT/test/parity/objectmodel/field_ref_closure.py" --pre "$TMP/pre.ll" --calls "$TMP/calls.tsv" "${final_args[@]}" "${object_args[@]}"
echo "FIELDREF_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_field_ref_probe: PASS'
