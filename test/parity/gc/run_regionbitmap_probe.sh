#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
export cjHeapSize=${cjHeapSize:-24GB}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_regionbitmap.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
SOURCE="$ROOT/src/rt.gc/RegionBitmap.cj"
[[ $(grep -Fc '@When[os == "Linux" || env == "ohos"]' "$SOURCE") -eq 5 ]]
[[ $(grep -Fc '@When[os == "macOS" || os == "iOS"]' "$SOURCE") -eq 5 ]]
[[ $(grep -Fc '@When[os == "Windows"]' "$SOURCE") -eq 5 ]]
echo 'REGIONBITMAP_SOURCE fresh=PASS linux_ohos=PASS apple=PASS win64=PASS cpp_platform_branches=0'
CPP_FLAGS=(-std=c++17 -O2 -DMRT_USE_CJTHREAD_RENAME -I"$RUNTIME_ROOT/src" -I"$RUNTIME_ROOT/output/temp/include" -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include")
g++ "${CPP_FLAGS[@]}" "$ROOT/test/parity/gc/regionbitmap_ref.cpp" -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime -o "$TMP/ref"
"$TMP/ref" > "$TMP/ref.txt"
g++ -std=c++17 -O2 -fPIC -c "$ROOT/rt0/Atomic.cpp" -o "$TMP/Atomic.o"
cp -a "$ROOT/src/rt.gc" "$TMP/rt.gc.probe"
cp "$ROOT/test/parity/gc/regionbitmap_probe.cj" "$TMP/rt.gc.probe/Probe.cj"
"$SELFHOST_CJC" --package "$TMP/rt.gc.probe" --int-overflow wrapping -Woff unused "$TMP/Atomic.o" --link-option=-lstdc++ --link-option=-lgcc_s -o "$TMP/probe"
"$TMP/probe" > "$TMP/probe.txt"
cmp "$TMP/ref.txt" "$TMP/probe.txt"
cat "$TMP/probe.txt"
echo "REGIONBITMAP_TRANSCRIPT lines=$(wc -l < "$TMP/probe.txt") bytes=$(wc -c < "$TMP/probe.txt") sha256=$(sha256sum "$TMP/probe.txt" | awk '{print $1}') cmp=PASS"
mkdir -p "$TMP/win.release" "$TMP/win.debug"
for mode in release debug; do
    flags=(); [[ $mode == debug ]] && flags=(-g)
    "$SELFHOST_CJC" --package "$ROOT/src/rt.gc" --target x86_64-w64-mingw32 --output-type=staticlib "${flags[@]}" --int-overflow wrapping -Woff unused --output-dir "$TMP/win.$mode" -o librt.gc.a
done
clang++ --target=x86_64-w64-windows-gnu -std=c++14 -O2 -c "$ROOT/rt0/Atomic.cpp" -o "$TMP/Atomic.win.o"
llvm-nm "$TMP/Atomic.win.o" | grep -Fq 'cj_atomic_u64_fetch_or_seq_cst'
echo 'REGIONBITMAP_PLATFORM target=Linux-OHOS compile=PASS execute=PASS atomic_orders=PASS status=PASS'
echo 'REGIONBITMAP_PLATFORM target=Apple source=PASS atomic_builtin=CLANG-DEBT-APPLE-SDK native_execute=DEBT-APPLE-SDK status=EXPLICIT-DEBT'
echo 'REGIONBITMAP_PLATFORM target=Win64 cj_release=PASS cj_debug=PASS atomic_owner=PASS status=PASS'

cp -a "$ROOT/src/rt.gc" "$TMP/rt.gc.noheap"
cp "$ROOT/test/parity/gc/regionbitmap_noheap.cj" "$TMP/rt.gc.noheap/NoHeap.cj"
mkdir -p "$TMP/temps"
"$SELFHOST_CJC" --package "$TMP/rt.gc.noheap" --output-type=staticlib --save-temps "$TMP/temps" --int-overflow wrapping -Woff unused -o "$TMP/librt.gc.a"
mapfile -t PRE_BC < <(find "$TMP/temps" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | sort)
"$CANGJIE_HOME/third_party/llvm/bin/llvm-link" "${PRE_BC[@]}" -o "$TMP/pre.bc"
"$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$TMP/pre.bc" -o "$TMP/pre.ll"
"$CANGJIE_HOME/third_party/llvm/bin/opt" -passes=print-callgraph -disable-output "$TMP/pre.bc" 2> "$TMP/callgraph"
awk '/^Call graph node for function:/{line=$0;sub(/^.*function: '\''/,"",line);sub(/'\''.*$/,"",line);owner=line;next}/calls function '\''/{line=$0;sub(/^.*calls function '\''/,"",line);sub(/'\''.*$/,"",line);if(owner!="")print owner "\t" line}' "$TMP/callgraph" > "$TMP/calls.tsv"
final_args=(); object_args=()
while IFS= read -r bc; do ll="$TMP/$(basename "$bc").ll"; "$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$bc" -o "$ll"; final_args+=(--final "$ll"); done < <(find "$TMP/temps" -maxdepth 1 -type f -name '*.opt.bc' | sort)
while IFS= read -r obj; do dump="$TMP/$(basename "$obj").objdump"; objdump -dr "$obj" > "$dump"; object_args+=(--object "$dump"); done < <(find "$TMP/temps" -maxdepth 1 -type f -name '*.o' | sort)
python3 "$ROOT/test/parity/gc/regionbitmap_closure.py" --pre "$TMP/pre.ll" --calls "$TMP/calls.tsv" "${final_args[@]}" "${object_args[@]}"
echo "REGIONBITMAP_COMPILER path=$SELFHOST_CJC sha256=$(sha256sum "$SELFHOST_CJC" | awk '{print $1}') status=PASS"
echo 'run_regionbitmap_probe: PASS'
