#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CJC_BIN_DIR=$(cd "$(dirname "$SELFHOST_CJC")" && pwd)
SELFHOST_RUNTIME="$CJC_BIN_DIR/../runtime/lib/linux_x86_64_cjnative"
LLVM="$LLVM_BIN"
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$LD_LIBRARY_PATH"
export cjHeapSize=24GB

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "TypeDef parity execution requires Linux x86_64" >&2
    exit 2
fi
test -x "$SELFHOST_CJC"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_typedef_probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

artifact_manifest() {
    find "$ROOT" -path "$ROOT/.git" -prune -o -type f \
        \( -name '*.bc' -o -name '*.opt.bc' -o -name '*.o' -o -name '*.cjo' \
        -o -name '*.a' -o -name '*.log' -o -name '*.transcript' -o -perm -111 \) \
        -printf '%P\t%s\n' | sort
}

artifact_manifest > "$TMP/repository.before.manifest"
df -h / | tail -n 1 | sed 's/^/TYPEDEF_DISK_BEFORE /'
echo "TYPEDEF_COMPILER path=$SELFHOST_CJC status=PASS"

# The failure-injection path uses the mandated compiler and must fail before any live build.
if [[ ${TYPEDEF_INJECT_EARLY_COMPILER_FAILURE:-0} == 1 ]]; then
    set +e
    (cd "$TMP" && "$SELFHOST_CJC" --package "$TMP/injected-missing-package" \
        --output-type=staticlib --int-overflow wrapping -o injected-failure.a)
    injected_rc=$?
    set -e
    if [[ $injected_rc -eq 0 ]]; then
        echo "TYPEDEF_INJECTED_COMPILER_FAILURE rc=0 status=FAIL" >&2
        exit 1
    fi
    echo "TYPEDEF_INJECTED_COMPILER_FAILURE rc=$injected_rc status=PASS" >&2
    exit 86
fi

build_package() {
    local package=$1
    local temps=$2
    mkdir -p "$temps"
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$package" \
        --output-type=staticlib --int-overflow wrapping -Woff unused \
        --import-path "$TMP" --output-dir "$TMP" --save-temps "$temps" \
        -o "lib$package.a")
    test -s "$TMP/lib$package.a"
}

# Build the real live closure in dependency order. No production source is copied.
for package in rt.base rt.sync rt.heap.allocator rt.common; do
    build_package "$package" "$TMP/temps/$package"
done

# Complete the seven-package live build in dependency/import order.
for package in rt.demangle rt.stackmap rt.abi; do
    build_package "$package" "$TMP/temps/$package"
done

for package in rt.base rt.sync rt.heap.allocator rt.common; do
    pre_count=$(find "$TMP/temps/$package" -maxdepth 1 -type f -name '*.bc' ! -name '*.opt.bc' | wc -l)
    final_count=$(find "$TMP/temps/$package" -maxdepth 1 -type f -name '*.opt.bc' | wc -l)
    object_count=$(find "$TMP/temps/$package" -maxdepth 1 -type f -name '[0-9]*.o' | wc -l)
    if [[ $pre_count -eq 0 || $pre_count -ne $final_count || $pre_count -ne $object_count ]]; then
        echo "TYPEDEF_LIVE_MODULES package=$package pre=$pre_count final=$final_count objects=$object_count status=FAIL" >&2
        exit 1
    fi
    echo "TYPEDEF_LIVE_MODULES package=$package pre=$pre_count final=$final_count objects=$object_count status=PASS"
done

# Compile the C++ oracle directly against the untouched Common/TypeDef.h.
(cd "$TMP" && g++ -std=c++17 -O2 \
    -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/common/typedef_ref.cpp" -o "$TMP/typedef_cpp")

# Existing dependencies of the complete live rt.common archive; TypeDef adds no bridge.
(cd "$TMP" && g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o Panic.o)
(cd "$TMP" && g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o Atomic.o)
(cd "$TMP" && g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/PagePoolMutex.cpp" -o PagePoolMutex.o)
(cd "$TMP" && g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/SpinLock.cpp" -o SpinLock.o)
NATIVE_INCLUDES=(-I"$RUNTIME_ROOT/include")
while IFS= read -r directory; do NATIVE_INCLUDES+=(-I"$directory"); done < <(find "$RUNTIME_ROOT/src" -type d)
NATIVE_FLAGS=(-std=c++17 -O2 -pthread -DMRT_USE_CJTHREAD_RENAME
    -I"$RUNTIME_ROOT/output/temp/include"
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include"
    "${NATIVE_INCLUDES[@]}")
(cd "$TMP" && g++ "${NATIVE_FLAGS[@]}" -fPIC -c "$ROOT/rt0/AllocBufferNative.cpp" -o AllocBufferNative.o)
(cd "$TMP" && g++ "${NATIVE_FLAGS[@]}" -fPIC -c "$ROOT/rt0/ScopedSaferegion.cpp" -o ScopedSaferegion.o)

mkdir -p "$TMP/temps/typedef_driver"
(cd "$TMP" && "$SELFHOST_CJC" "$ROOT/test/parity/common/typedef_driver.cj" \
    --int-overflow wrapping -Woff unused --import-path "$TMP" \
    --save-temps "$TMP/temps/typedef_driver" \
    "$TMP/librt.common.a" "$TMP/librt.heap.allocator.a" \
    "$TMP/librt.sync.a" "$TMP/librt.base.a" \
    "$TMP/Panic.o" "$TMP/Atomic.o" "$TMP/PagePoolMutex.o" "$TMP/SpinLock.o" \
    "$TMP/AllocBufferNative.o" "$TMP/ScopedSaferegion.o" \
    --link-option=-lstdc++ --link-option=-lgcc_s --link-option=-lpthread -o "$TMP/typedef_cj")

"$TMP/typedef_cpp" > "$TMP/cpp.transcript"
"$TMP/typedef_cj" > "$TMP/cj.transcript"
if ! cmp "$TMP/cpp.transcript" "$TMP/cj.transcript"; then
    diff -u "$TMP/cpp.transcript" "$TMP/cj.transcript" | head -n 240 >&2 || true
    echo "TYPEDEF_PARITY cmp=FAIL" >&2
    exit 1
fi

grep -Fx 'LAYOUT MAddress 8 8' "$TMP/cj.transcript"
grep -Fx 'LAYOUT MSize 4 4' "$TMP/cj.transcript"
grep -Fx 'LAYOUT MOffset 4 4' "$TMP/cj.transcript"
grep -Fx 'LAYOUT MIndex 8 8' "$TMP/cj.transcript"
for reference in ObjRef ArrayRef FuncRef FuncDescRef StringRef ExceptionRef \
    MethodInfoRef PackageInfoRef ParameterInfoRef; do
    grep -Fx "LAYOUT $reference 8 8" "$TMP/cj.transcript"
done
grep -Fx 'LAYOUT FuncPtr 8 8' "$TMP/cj.transcript"
grep -Fx 'LAYOUT AllocType 4 4' "$TMP/cj.transcript"
grep -Fx 'CONSTANT NULL_ADDRESS 0' "$TMP/cj.transcript"
grep -Fx 'CONSTANT GENERIC_PAYLOAD_SIZE 2147483647' "$TMP/cj.transcript"
grep -Fx 'CONSTANT MAX_ARRAY_SIZE 18446744073709551615' "$TMP/cj.transcript"
grep -Fx 'SCALAR MSize 4294967295' "$TMP/cj.transcript"
grep -Fx 'SCALAR MOffset 4294967295' "$TMP/cj.transcript"
grep -Fx 'ALLOC 0 1 2' "$TMP/cj.transcript"
for pointer_record in \
    'POINTER ObjRef NULL 0' 'POINTER ArrayRef NULL 0' 'POINTER FuncRef NULL 0' \
    'POINTER FuncDescRef NULL 0' 'POINTER StringRef NULL 0' \
    'POINTER ExceptionRef NULL 0' 'POINTER MethodInfoRef NULL 0' \
    'POINTER PackageInfoRef NULL 0' 'POINTER ParameterInfoRef NULL 0' \
    'POINTER ObjRef NONNULL 4096' 'POINTER ArrayRef NONNULL 4352' \
    'POINTER FuncRef NONNULL 4608' 'POINTER FuncDescRef NONNULL 4864' \
    'POINTER StringRef NONNULL 5120' 'POINTER ExceptionRef NONNULL 5376' \
    'POINTER MethodInfoRef NONNULL 5632' 'POINTER PackageInfoRef NONNULL 5888' \
    'POINTER ParameterInfoRef NONNULL 6144'; do
    grep -Fx "$pointer_record" "$TMP/cj.transcript"
done
grep -Fx 'FUNCPTR callbacks=4096 indirect_calls=4096 value=4096 null=0 nonnull=1' \
    "$TMP/cj.transcript"

ALIGN_OPERATIONS=$(grep -c '^ALIGN ' "$TMP/cj.transcript")
RECORDS=$(wc -l < "$TMP/cj.transcript")
BYTES=$(wc -c < "$TMP/cj.transcript")
TRANSCRIPT_SHA=$(sha256sum "$TMP/cj.transcript" | awk '{print $1}')
if [[ $ALIGN_OPERATIONS -ne 100000 || $RECORDS -ne 100040 ]]; then
    echo "TYPEDEF_ALIGN_PARITY operations=$ALIGN_OPERATIONS records=$RECORDS status=FAIL" >&2
    exit 1
fi

# Build the complete five-owner definition universe before any reachability
# filtering. Every split pre-opt BC, final BC, and object is indexed.
OWNERS=(rt.base rt.sync rt.heap.allocator rt.common typedef_driver)
EXPECTED_PACKAGES=rt.base,rt.sync,rt.heap.allocator,rt.common,typedef_driver
: > "$TMP/pre.index"
: > "$TMP/final.index"
: > "$TMP/object.index"

index_ir() {
    local ir=$1
    local package=$2
    local index=$3
    awk -v package="$package" -v module="$ir" '
    /^define / {
        line=$0
        name=line
        sub(/^[^@]*@/, "", name)
        sub(/\(.*/, "", name)
        gsub(/^"|"$/, "", name)
        scope="global"
        linkage="strong"
        if (line ~ /^define private /) { scope="local"; linkage="private" }
        else if (line ~ /^define internal /) { scope="local"; linkage="internal" }
        else if (line ~ /^define weak_odr /) { linkage="weak_odr" }
        else if (line ~ /^define weak /) { linkage="weak" }
        else if (line ~ /^define linkonce_odr /) { linkage="linkonce_odr" }
        else if (line ~ /^define linkonce /) { linkage="linkonce" }
        print name "\t" package "\t" module "\t" scope "\t" linkage
    }
    ' "$ir" >> "$index"
}

for package in "${OWNERS[@]}"; do
    mkdir -p "$TMP/ll/$package"
    pre_count=0
    final_count=0
    object_count=0
    for bc in "$TMP/temps/$package"/*.bc; do
        ir="$TMP/ll/$package/$(basename "$bc").ll"
        "$LLVM/llvm-dis" "$bc" -o "$ir"
        if [[ $bc == *.opt.bc ]]; then
            index_ir "$ir" "$package" "$TMP/final.index"
            final_count=$((final_count + 1))
        else
            index_ir "$ir" "$package" "$TMP/pre.index"
            pre_count=$((pre_count + 1))
        fi
    done
    for object in "$TMP/temps/$package"/[0-9]*.o; do
        nm --defined-only "$object" | awk -v package="$package" -v object="$object"             '$2 ~ /^[TtWw]$/ {print $3 "\t" package "\t" object}'             >> "$TMP/object.index"
        object_count=$((object_count + 1))
    done
    if [[ $pre_count -eq 0 || $pre_count -ne $final_count ||
          $pre_count -ne $object_count ]]; then
        echo "TYPEDEF_OWNER_STAGES package=$package pre=$pre_count final=$final_count objects=$object_count status=FAIL" >&2
        exit 1
    fi
    echo "TYPEDEF_OWNER_STAGES package=$package pre=$pre_count final=$final_count objects=$object_count status=PASS"

    owner_pre=()
    for bc in "$TMP/temps/$package"/*.bc; do
        [[ $bc == *.opt.bc ]] || owner_pre+=("$bc")
    done
    "$LLVM/llvm-link" "${owner_pre[@]}" -o "$TMP/$package.pre.bc"
done

# The link order is the dependency order in reverse, with each real dependency
# overriding imported copies emitted by its consumers. llvm-link therefore makes
# the ownership choice that the index records below.
"$LLVM/llvm-link" "$TMP/typedef_driver.pre.bc"     --override="$TMP/rt.common.pre.bc"     --override="$TMP/rt.heap.allocator.pre.bc"     --override="$TMP/rt.sync.pre.bc"     --override="$TMP/rt.base.pre.bc"     -o "$TMP/typedef.live.pre.bc"
"$LLVM/llvm-dis" "$TMP/typedef.live.pre.bc" -o "$TMP/typedef.live.pre.ll"
"$LLVM/opt" -passes=print-callgraph -disable-output "$TMP/typedef.live.pre.bc"     2> "$TMP/typedef.live.callgraph"

INDEXED_DEFS=$(wc -l < "$TMP/pre.index")
FINAL_INDEXED_DEFS=$(wc -l < "$TMP/final.index")
OBJECT_INDEXED_DEFS=$(wc -l < "$TMP/object.index")
: > "$TMP/linked.defs"
awk '/^define / {
    name=$0
    sub(/^[^@]*@/, "", name)
    sub(/\(.*/, "", name)
    gsub(/^"|"$/, "", name)
    print name
}' "$TMP/typedef.live.pre.ll" | sort -u > "$TMP/linked.defs"
LINKED_DEFS=$(wc -l < "$TMP/linked.defs")

DERIVED_PACKAGES=""
MISSING_OWNERS=0
for package in "${OWNERS[@]}"; do
    owner_count=$(awk -F '\t' -v owner="$package" '$2 == owner {++n} END {print n+0}'         "$TMP/pre.index")
    if [[ $owner_count -eq 0 ]]; then
        MISSING_OWNERS=$((MISSING_OWNERS + 1))
    else
        if [[ -n $DERIVED_PACKAGES ]]; then DERIVED_PACKAGES="$DERIVED_PACKAGES,"; fi
        DERIVED_PACKAGES="$DERIVED_PACKAGES$package"
    fi
    case "$package" in
        rt.base) BASE_INDEXED=$owner_count ;;
        rt.sync) SYNC_INDEXED=$owner_count ;;
        rt.heap.allocator) ALLOCATOR_INDEXED=$owner_count ;;
        rt.common) COMMON_INDEXED=$owner_count ;;
        typedef_driver) DRIVER_INDEXED=$owner_count ;;
    esac
done
if [[ $DERIVED_PACKAGES != "$EXPECTED_PACKAGES" || $MISSING_OWNERS -ne 0 ]]; then
    echo "TYPEDEF_DEFINITION_UNIVERSE packages=$DERIVED_PACKAGES missing_owners=$MISSING_OWNERS status=FAIL" >&2
    exit 1
fi

select_owner() {
    local symbol=$1
    awk -F '\t' -v symbol="$symbol" '
    $1 == symbol {
        if ($4 == "local") {
            localCount++
            localOwner=$2
            next
        }
        rank=99
        if ($2 == "rt.base") rank=1
        else if ($2 == "rt.sync") rank=2
        else if ($2 == "rt.heap.allocator") rank=3
        else if ($2 == "rt.common") rank=4
        else if ($2 == "typedef_driver") rank=5
        if (best == 0 || rank < best) { best=rank; owner=$2 }
    }
    END {
        if (owner != "") print owner
        else if (localCount == 1) print localOwner
    }
    ' "$TMP/pre.index"
}

extract_body() {
    local ir=$1
    local symbol=$2
    local output=$3
    awk -v target="$symbol" '
    /^define / {
        name=$0
        sub(/^[^@]*@/, "", name)
        sub(/\(.*/, "", name)
        gsub(/^"|"$/, "", name)
        emit=(name == target)
    }
    emit {
        print
        if ($0 ~ /^}/) emit=0
    }
    ' "$ir" > "$output"
}

normalized_body_hash() {
    local ir=$1
    local symbol=$2
    awk -v target="$symbol" '
    /^define / {
        name=$0
        sub(/^[^@]*@/, "", name)
        sub(/\(.*/, "", name)
        gsub(/^"|"$/, "", name)
        emit=(name == target)
    }
    emit {
        line=$0
        gsub(/ !dbg ![0-9]+/, "", line)
        gsub(/#[0-9]+/, "#ATTR", line)
        gsub(/![0-9]+/, "!MD", line)
        gsub(/__cj_personality_v0\$[^"]*/, "__cj_personality_v0$", line)
        gsub(/[[:space:]]+/, " ", line)
        print line
        if ($0 ~ /^}/) emit=0
    }
    ' "$ir" | sha256sum | awk '{print $1}'
}

# Retain every raw owner definition in pre.index. Global duplicates are resolved
# only after proving that llvm-link emitted exactly one definition and that its
# selected body is the canonical override body. Identical imported bodies are
# recorded separately from the one known nonempty-live/empty-import initializer.
awk -F '\t' '$4 == "global" {count[$1]++}
    END {for (symbol in count) if (count[symbol] > 1) print symbol}'     "$TMP/pre.index" | sort > "$TMP/duplicate.symbols"
: > "$TMP/ownership.resolutions"
AMBIGUOUS=0
DUPLICATE_EXCESS=0
while IFS= read -r symbol; do
    [[ -n $symbol ]] || continue
    candidate_count=$(awk -F '\t' -v symbol="$symbol"         '$1 == symbol && $4 == "global" {++n} END {print n+0}' "$TMP/pre.index")
    DUPLICATE_EXCESS=$((DUPLICATE_EXCESS + candidate_count - 1))
    selected_owner=$(select_owner "$symbol")
    selected_count=$(awk -F '\t' -v symbol="$symbol" -v owner="$selected_owner"         '$1 == symbol && $2 == owner && $4 == "global" {++n} END {print n+0}'         "$TMP/pre.index")
    linked_count=$(grep -Fxc "$symbol" "$TMP/linked.defs" || true)
    first_hash=""
    identical=1
    selected_hash=""
    selected_ir=""
    while IFS=$'\t' read -r _ candidate_owner candidate_ir _ _; do
        candidate_hash=$(normalized_body_hash "$candidate_ir" "$symbol")
        if [[ -z $first_hash ]]; then first_hash=$candidate_hash; fi
        if [[ $candidate_hash != "$first_hash" ]]; then identical=0; fi
        if [[ $candidate_owner == "$selected_owner" ]]; then
            selected_hash=$candidate_hash
            selected_ir=$candidate_ir
        fi
    done < <(awk -F '\t' -v symbol="$symbol"         '$1 == symbol && $4 == "global" {print}' "$TMP/pre.index")
    linked_hash=$(normalized_body_hash "$TMP/typedef.live.pre.ll" "$symbol")
    disposition=identical-override
    if [[ $identical -ne 1 ]]; then
        nonselected_nonempty=0
        while IFS=$'\t' read -r _ candidate_owner candidate_ir _ _; do
            if [[ $candidate_owner == "$selected_owner" ]]; then continue; fi
            instruction_count=$(awk -v target="$symbol" '
                /^define / {line=$0; sub(/^[^@]*@/, "", line); sub(/\(.*/, "", line);
                    gsub(/^"|"$/, "", line); emit=(line == target); next}
                emit && $0 !~ /^bb[0-9.]*:/ && $0 !~ /^[[:space:]]*ret void/ &&
                    $0 !~ /^}/ && $0 !~ /^[[:space:]]*$/ {++n}
                END {print n+0}
            ' "$candidate_ir")
            if [[ $instruction_count -ne 0 ]]; then nonselected_nonempty=1; fi
        done < <(awk -F '\t' -v symbol="$symbol"             '$1 == symbol && $4 == "global" {print}' "$TMP/pre.index")
        if [[ $symbol == _CGF* && $nonselected_nonempty -eq 0 ]]; then
            disposition=live-owner-over-empty-import
        else
            AMBIGUOUS=$((AMBIGUOUS + 1))
            disposition=unexplained
        fi
    fi
    if [[ $selected_count -ne 1 || $linked_count -ne 1 ||
          -z $selected_ir || $linked_hash != "$selected_hash" ]]; then
        AMBIGUOUS=$((AMBIGUOUS + 1))
        disposition=linked-body-mismatch
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$symbol" "$selected_owner"         "$candidate_count" "$selected_hash" "$disposition"         >> "$TMP/ownership.resolutions"
done < "$TMP/duplicate.symbols"

if [[ $((INDEXED_DEFS - DUPLICATE_EXCESS)) -ne $LINKED_DEFS ||
      $AMBIGUOUS -ne 0 ]]; then
    echo "TYPEDEF_OWNERSHIP indexed=$INDEXED_DEFS duplicate_excess=$DUPLICATE_EXCESS linked=$LINKED_DEFS ambiguous=$AMBIGUOUS status=FAIL" >&2
    cat "$TMP/ownership.resolutions" >&2
    exit 1
fi

# A structural fail-closed lookup proves that each dependency owner really
# contributed an indexed definition. The chosen symbol is derived as a global
# definition unique to that owner; an actual four-owner link must omit it.
: > "$TMP/structural.index"
for package in rt.base rt.sync rt.heap.allocator; do
    structural_symbol=$(awk -F '\t' -v owner="$package" '
        $2 == owner && $4 == "global" && $1 ~ /^_CN/ {candidate[$1]=1}
        {all[$1 SUBSEP $2]=1}
        END {
            for (symbol in candidate) {
                owners=0
                for (key in all) {
                    split(key, fields, SUBSEP)
                    if (fields[1] == symbol) owners++
                }
                if (owners == 1) print symbol
            }
        }
    ' "$TMP/pre.index" | sort | head -n 1)
    if [[ -z $structural_symbol ]]; then
        echo "TYPEDEF_STRUCTURAL_INDEX owner=$package symbol=NONE status=FAIL" >&2
        exit 1
    fi
    no_owner_inputs=("$TMP/typedef_driver.pre.bc")
    for input_owner in rt.common rt.heap.allocator rt.sync rt.base; do
        [[ $input_owner == "$package" ]] && continue
        no_owner_inputs+=("--override=$TMP/$input_owner.pre.bc")
    done
    "$LLVM/llvm-link" "${no_owner_inputs[@]}" -o "$TMP/without.$package.bc"
    "$LLVM/llvm-dis" "$TMP/without.$package.bc" -o "$TMP/without.$package.ll"
    removed_count=$(awk -v target="$structural_symbol" '
        /^define / {line=$0; sub(/^[^@]*@/, "", line); sub(/\(.*/, "", line);
            gsub(/^"|"$/, "", line); if (line == target) ++n}
        END {print n+0}
    ' "$TMP/without.$package.ll")
    if [[ $removed_count -ne 0 ]]; then
        echo "TYPEDEF_STRUCTURAL_INDEX owner=$package symbol=$structural_symbol remove_owner_lookup=$removed_count status=FAIL" >&2
        exit 1
    fi
    printf '%s\t%s\n' "$package" "$structural_symbol" >> "$TMP/structural.index"
    echo "TYPEDEF_STRUCTURAL_INDEX owner=$package symbol=$structural_symbol remove_owner_lookup=FAIL_CLOSED status=PASS"
done

awk '
/^Call graph node for function:/ {
    line=$0
    sub(/^.*function: '\''/, "", line)
    sub(/'\''.*$/, "", line)
    current=line
    next
}
/calls function '\''/ {
    line=$0
    sub(/^.*calls function '\''/, "", line)
    sub(/'\''.*$/, "", line)
    if (current != "") print current "\t" line
}
' "$TMP/typedef.live.callgraph" > "$TMP/calls.tsv"

# The live manifest roots every executable initializer that survived the
# five-owner link. The restricted TypeDef/noheap closure is separately rooted
# at TypeDef's own initializer and executable bodies; unrelated package
# initializers remain in the live manifest without being mislabeled TypeDef.
awk '/^define / {
    name=$0
    sub(/^[^@]*@/, "", name)
    sub(/\(.*/, "", name)
    gsub(/^"|"$/, "", name)
    if (name ~ /^_CN9rt.common9MRT_ALIGN/ ||
        name ~ /\$iiHv$/ ||
        name ~ /^TypeDef(Probe|Align|Callback)/) print name
}' "$TMP/typedef.live.pre.ll" | sort -u > "$TMP/live.roots"
awk '$0 !~ /\$iiHv$/ || $0 == "_CGF9rt.commonUTypeDef$iiHv"' \
    "$TMP/live.roots" > "$TMP/roots"

MRT_ROOTS=$(grep -c '^_CN9rt.common9MRT_ALIGN' "$TMP/roots")
TEST_ROOTS=$(grep -Ec '^TypeDef(Probe|Align|Callback)' "$TMP/roots")
INIT_ROOTS=$(grep -Ec '\$iiHv$' "$TMP/live.roots")
TYPEDEF_INIT_ROOTS=$(grep -Fxc '_CGF9rt.commonUTypeDef$iiHv' "$TMP/roots" || true)
ADDRESS_TAKEN_CALLBACK=$(grep -Ec     'store void \(i8\*\)\* @TypeDefCallback, void \(i8\*\)\*\*'     "$TMP/typedef.live.pre.ll" || true)
if [[ $MRT_ROOTS -ne 4 || $TEST_ROOTS -ne 21 || $INIT_ROOTS -eq 0 ||
      $TYPEDEF_INIT_ROOTS -ne 1 || $ADDRESS_TAKEN_CALLBACK -ne 1 ]] ||
   ! grep -Fxq 'TypeDefCallback' "$TMP/roots"; then
    echo "TYPEDEF_ROOTS mrt=$MRT_ROOTS initializers=$INIT_ROOTS typedef_init=$TYPEDEF_INIT_ROOTS test=$TEST_ROOTS address_taken_callback=$ADDRESS_TAKEN_CALLBACK status=FAIL" >&2
    exit 1
fi

declare -A SEEN=()
QUEUE=()
: > "$TMP/unresolved.live"
: > "$TMP/external.declarations"
while IFS= read -r symbol; do
    [[ -n $symbol ]] || continue
    if ! grep -Fxq "$symbol" "$TMP/linked.defs"; then
        echo "TYPEDEF_ROOT_MISSING symbol=$symbol status=FAIL" >&2
        exit 1
    fi
    SEEN["$symbol"]=1
    QUEUE+=("$symbol")
done < "$TMP/live.roots"
while [[ ${#QUEUE[@]} -gt 0 ]]; do
    CURRENT=${QUEUE[0]}
    QUEUE=("${QUEUE[@]:1}")
    while IFS=$'\t' read -r _ callee; do
        [[ -n $callee ]] || continue
        if grep -Fxq "$callee" "$TMP/linked.defs"; then
            if [[ -z ${SEEN["$callee"]+present} ]]; then
                SEEN["$callee"]=1
                QUEUE+=("$callee")
            fi
        elif awk -F '\t' -v symbol="$callee"             '$1 == symbol && $4 == "global" {found=1} END {exit found ? 0 : 1}'             "$TMP/pre.index"; then
            printf '%s\t%s\n' "$CURRENT" "$callee" >> "$TMP/unresolved.live"
        else
            printf '%s\t%s\n' "$CURRENT" "$callee" >> "$TMP/external.declarations"
        fi
    done < <(awk -F '\t' -v key="$CURRENT" '$1 == key {print}' "$TMP/calls.tsv")
done
for symbol in "${!SEEN[@]}"; do
    printf '%s\n' "$symbol"
done | sort > "$TMP/reachable.defs"
sort -u -o "$TMP/unresolved.live" "$TMP/unresolved.live"
UNRESOLVED_LIVE=$(wc -l < "$TMP/unresolved.live")
if [[ $UNRESOLVED_LIVE -ne 0 ]]; then
    echo "TYPEDEF_REACHABILITY unresolved_live=$UNRESOLVED_LIVE status=FAIL" >&2
    cat "$TMP/unresolved.live" >&2
    exit 1
fi

declare -A NOHEAP_SEEN=()
NOHEAP_QUEUE=()
while IFS= read -r symbol; do
    [[ -n $symbol ]] || continue
    NOHEAP_SEEN["$symbol"]=1
    NOHEAP_QUEUE+=("$symbol")
done < "$TMP/roots"
while [[ ${#NOHEAP_QUEUE[@]} -gt 0 ]]; do
    CURRENT=${NOHEAP_QUEUE[0]}
    NOHEAP_QUEUE=("${NOHEAP_QUEUE[@]:1}")
    while IFS=$'\t' read -r _ callee; do
        [[ -n $callee ]] || continue
        if grep -Fxq "$callee" "$TMP/linked.defs"; then
            if [[ -z ${NOHEAP_SEEN["$callee"]+present} ]]; then
                NOHEAP_SEEN["$callee"]=1
                NOHEAP_QUEUE+=("$callee")
            fi
        elif awk -F '\t' -v symbol="$callee" \
            '$1 == symbol && $4 == "global" {found=1} END {exit found ? 0 : 1}' \
            "$TMP/pre.index"; then
            printf '%s\t%s\n' "$CURRENT" "$callee" >> "$TMP/unresolved.live"
        fi
    done < <(awk -F '\t' -v key="$CURRENT" '$1 == key {print}' "$TMP/calls.tsv")
done
for symbol in "${!NOHEAP_SEEN[@]}"; do
    printf '%s\n' "$symbol"
done | sort > "$TMP/noheap.reachable.defs"
sort -u -o "$TMP/unresolved.live" "$TMP/unresolved.live"
UNRESOLVED_LIVE=$(wc -l < "$TMP/unresolved.live")
if [[ $UNRESOLVED_LIVE -ne 0 ]]; then
    echo "TYPEDEF_NOHEAP_REACHABILITY unresolved_live=$UNRESOLVED_LIVE status=FAIL" >&2
    cat "$TMP/unresolved.live" >&2
    exit 1
fi

# TypeDef has three compile-time constant globals and one executable initializer.
STATIC_INITIALIZERS=$(awk -F '\t'     '$2 == "rt.common" && $1 == "_CGF9rt.commonUTypeDef$iiHv" {++n} END {print n+0}'     "$TMP/pre.index")
CONSTANT_GLOBALS=$(grep -Ec '^@_CN9rt\.common(12NULL_ADDRESS|20GENERIC_PAYLOAD_SIZE|14MAX_ARRAY_SIZE)E = weak_odr constant '     "$TMP/typedef.live.pre.ll")
if [[ $STATIC_INITIALIZERS -ne 1 || $CONSTANT_GLOBALS -ne 3 ]]; then
    echo "TYPEDEF_STATIC_INITIALIZERS executable=$STATIC_INITIALIZERS constants=$CONSTANT_GLOBALS status=FAIL" >&2
    exit 1
fi

: > "$TMP/body.manifest"
printf 'symbol\tpackage\tpre_module\tpre_body\tfinal_module\tfinal_body\tobject\tobject_body\tdisposition\n'     >> "$TMP/body.manifest"
: > "$TMP/pre.closure.ll"
: > "$TMP/final.closure.ll"
: > "$TMP/object.closure.txt"
: > "$TMP/manifest.defs"
: > "$TMP/scanned.pre.defs"
: > "$TMP/scanned.final.defs"
: > "$TMP/scanned.object.defs"
: > "$TMP/reachable.owners"
REACHABLE_DEFS=$(wc -l < "$TMP/reachable.defs")
SCANNED_DEFS=0
MISSING=0
MANIFEST_AMBIGUOUS=0
ordinal=0
while IFS= read -r symbol; do
    ordinal=$((ordinal + 1))
    owner=$(select_owner "$symbol")
    pre_count=$(awk -F '\t' -v symbol="$symbol" -v owner="$owner"         '$1 == symbol && $2 == owner {++n} END {print n+0}' "$TMP/pre.index")
    final_count=$(awk -F '\t' -v symbol="$symbol" -v owner="$owner"         '$1 == symbol && $2 == owner {++n} END {print n+0}' "$TMP/final.index")
    object_count=$(awk -F '\t' -v symbol="$symbol" -v owner="$owner"         '$1 == symbol && $2 == owner {++n} END {print n+0}' "$TMP/object.index")
    if [[ -z $owner || $pre_count -eq 0 || $final_count -eq 0 ||
          $object_count -eq 0 ]]; then
        MISSING=$((MISSING + 1))
        echo "TYPEDEF_BODY_MISSING symbol=$symbol owner=$owner pre=$pre_count final=$final_count object=$object_count" >&2
        continue
    fi
    if [[ $pre_count -ne 1 || $final_count -ne 1 || $object_count -ne 1 ]]; then
        MANIFEST_AMBIGUOUS=$((MANIFEST_AMBIGUOUS + 1))
        echo "TYPEDEF_BODY_AMBIGUOUS symbol=$symbol owner=$owner pre=$pre_count final=$final_count object=$object_count" >&2
        continue
    fi
    pre_module=$(awk -F '\t' -v symbol="$symbol" -v owner="$owner"         '$1 == symbol && $2 == owner {print $3}' "$TMP/pre.index")
    final_module=$(awk -F '\t' -v symbol="$symbol" -v owner="$owner"         '$1 == symbol && $2 == owner {print $3}' "$TMP/final.index")
    object=$(awk -F '\t' -v symbol="$symbol" -v owner="$owner"         '$1 == symbol && $2 == owner {print $3}' "$TMP/object.index")
    pre_body="$TMP/bodies/$ordinal.pre.ll"
    final_body="$TMP/bodies/$ordinal.final.ll"
    object_body="$TMP/bodies/$ordinal.object.txt"
    mkdir -p "$TMP/bodies"
    extract_body "$pre_module" "$symbol" "$pre_body"
    extract_body "$final_module" "$symbol" "$final_body"
    objdump -dr --disassemble="$symbol" "$object" > "$object_body"
    if [[ ! -s $pre_body || ! -s $final_body ]] ||
       ! grep -Fq "<$symbol>:" "$object_body"; then
        MISSING=$((MISSING + 1))
        echo "TYPEDEF_BODY_EXTRACT symbol=$symbol owner=$owner status=FAIL" >&2
        continue
    fi
    disposition=survives
    duplicate_disposition=$(awk -F '\t' -v symbol="$symbol"         '$1 == symbol {print $5}' "$TMP/ownership.resolutions")
    if [[ -n $duplicate_disposition ]]; then
        disposition="$disposition+$duplicate_disposition"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n'         "$symbol" "$owner" "$(basename "$pre_module")" "$(basename "$pre_body")"         "$(basename "$final_module")" "$(basename "$final_body")"         "$(basename "$object")" "$(basename "$object_body")" "$disposition"         >> "$TMP/body.manifest"
    printf '; symbol=%s package=%s module=%s body=%s\n'         "$symbol" "$owner" "$pre_module" "$pre_body" >> "$TMP/pre.closure.ll"
    cat "$pre_body" >> "$TMP/pre.closure.ll"
    printf '; symbol=%s package=%s module=%s body=%s\n'         "$symbol" "$owner" "$final_module" "$final_body" >> "$TMP/final.closure.ll"
    cat "$final_body" >> "$TMP/final.closure.ll"
    printf '\nBODY symbol=%s package=%s object=%s body=%s\n'         "$symbol" "$owner" "$object" "$object_body" >> "$TMP/object.closure.txt"
    cat "$object_body" >> "$TMP/object.closure.txt"
    printf '%s\n' "$symbol" >> "$TMP/manifest.defs"
    printf '%s\n' "$symbol" >> "$TMP/scanned.pre.defs"
    printf '%s\n' "$symbol" >> "$TMP/scanned.final.defs"
    printf '%s\n' "$symbol" >> "$TMP/scanned.object.defs"
    printf '%s\t%s\n' "$symbol" "$owner" >> "$TMP/reachable.owners"
    SCANNED_DEFS=$((SCANNED_DEFS + 1))
done < "$TMP/reachable.defs"

for set_file in manifest.defs scanned.pre.defs scanned.final.defs scanned.object.defs; do
    sort -u -o "$TMP/$set_file" "$TMP/$set_file"
    if ! cmp "$TMP/reachable.defs" "$TMP/$set_file"; then
        echo "TYPEDEF_SET_EQUALITY set=$set_file status=FAIL" >&2
        exit 1
    fi
done
if [[ $REACHABLE_DEFS -eq 0 || $SCANNED_DEFS -ne $REACHABLE_DEFS ||
      $MISSING -ne 0 || $MANIFEST_AMBIGUOUS -ne 0 ]]; then
    echo "TYPEDEF_BODY_SCAN reachable=$REACHABLE_DEFS scanned=$SCANNED_DEFS missing=$MISSING ambiguous=$MANIFEST_AMBIGUOUS status=FAIL" >&2
    exit 1
fi

REACHABLE_PACKAGES=""
for package in "${OWNERS[@]}"; do
    package_reachable=$(awk -F '\t' -v owner="$package"         '$2 == owner {++n} END {print n+0}' "$TMP/reachable.owners")
    if [[ $package_reachable -gt 0 ]]; then
        if [[ -n $REACHABLE_PACKAGES ]]; then REACHABLE_PACKAGES="$REACHABLE_PACKAGES,"; fi
        REACHABLE_PACKAGES="$REACHABLE_PACKAGES$package"
    fi
    case "$package" in
        rt.base) BASE_REACHABLE=$package_reachable ;;
        rt.sync) SYNC_REACHABLE=$package_reachable ;;
        rt.heap.allocator) ALLOCATOR_REACHABLE=$package_reachable ;;
        rt.common) COMMON_REACHABLE=$package_reachable ;;
        typedef_driver) DRIVER_REACHABLE=$package_reachable ;;
    esac
done
if [[ $REACHABLE_PACKAGES != "$EXPECTED_PACKAGES" ]]; then
    echo "TYPEDEF_LIVE_CLOSURE packages=$REACHABLE_PACKAGES status=FAIL" >&2
    exit 1
fi

# Exact imported alias/signature evidence from the actual driver IR.
ADDRESS_ABI=$(grep -Ec '^define i64 @TypeDefProbeMAddress\(i64 ' "$TMP/typedef.live.pre.ll" || true)
SIZE_ABI=$(grep -Ec '^define i32 @TypeDefProbeMSize\(i32 ' "$TMP/typedef.live.pre.ll" || true)
OFFSET_ABI=$(grep -Ec '^define i32 @TypeDefProbeMOffset\(i32 ' "$TMP/typedef.live.pre.ll" || true)
INDEX_ABI=$(grep -Ec '^define i64 @TypeDefProbeMIndex\(i64 ' "$TMP/typedef.live.pre.ll" || true)
REF_ABI=$(grep -Ec '^define i8\* @TypeDefProbe(ObjRef|ArrayRef|FuncRef|FuncDescRef|StringRef|ExceptionRef|MethodInfoRef|PackageInfoRef|ParameterInfoRef)\(i8\* ' "$TMP/typedef.live.pre.ll" || true)
FUNCPTR_ABI=$(grep -Ec '^define void \(i8\*\)\* @TypeDefProbeFuncPtr\(void \(i8\*\)\* ' "$TMP/typedef.live.pre.ll" || true)
ALLOC_ABI=$(grep -Ec '^define i32 @TypeDefProbeAllocType\(i32 ' "$TMP/typedef.live.pre.ll" || true)
INVOKE_ABI=$(grep -Ec '^define void @TypeDefProbeInvoke\(void \(i8\*\)\* ' "$TMP/typedef.live.pre.ll" || true)
CALLBACK_ABI=$(grep -Ec '^define void @TypeDefCallback\(i8\* ' "$TMP/typedef.live.pre.ll" || true)
ALIGN_ABI=$(grep -Ec '^define (i16|i32|i64) @TypeDefAlign(16|32|64|Native)Root\(' "$TMP/typedef.live.pre.ll" || true)
MRT_ABI=$(grep -Ec '^define (i16|i32|i64) @_CN9rt\.common9MRT_ALIGNH(tt|jj|mm|rr)\(' "$TMP/typedef.live.pre.ll" || true)
if [[ $ADDRESS_ABI -ne 1 || $SIZE_ABI -ne 1 || $OFFSET_ABI -ne 1 ||
      $INDEX_ABI -ne 1 || $REF_ABI -ne 9 || $FUNCPTR_ABI -ne 1 ||
      $ALLOC_ABI -ne 1 || $INVOKE_ABI -ne 1 || $CALLBACK_ABI -ne 1 ||
      $ALIGN_ABI -ne 4 || $MRT_ABI -ne 4 ]]; then
    echo "TYPEDEF_ABI scalar=$ADDRESS_ABI,$SIZE_ABI,$OFFSET_ABI,$INDEX_ABI refs=$REF_ABI funcptr=$FUNCPTR_ABI alloc=$ALLOC_ABI invoke=$INVOKE_ABI callback=$CALLBACK_ABI align=$ALIGN_ABI mrt=$MRT_ABI status=FAIL" >&2
    exit 1
fi

for closure in pre final object; do
    : > "$TMP/noheap.$closure.closure"
done
: > "$TMP/noheap.scanned.defs"
NOHEAP_SCANNED_DEFS=0
while IFS= read -r symbol; do
    manifest_row=$(awk -F '\t' -v symbol="$symbol" 'NR > 1 && $1 == symbol {print}' \
        "$TMP/body.manifest")
    manifest_count=$(awk -F '\t' -v symbol="$symbol" \
        'NR > 1 && $1 == symbol {++n} END {print n+0}' "$TMP/body.manifest")
    if [[ $manifest_count -ne 1 || -z $manifest_row ]]; then
        echo "TYPEDEF_NOHEAP_MANIFEST symbol=$symbol count=$manifest_count status=FAIL" >&2
        exit 1
    fi
    IFS=$'\t' read -r _ owner _ pre_body _ final_body _ object_body _ \
        <<< "$manifest_row"
    printf '; symbol=%s package=%s body=%s\n' "$symbol" "$owner" "$pre_body" \
        >> "$TMP/noheap.pre.closure"
    cat "$TMP/bodies/$pre_body" >> "$TMP/noheap.pre.closure"
    printf '; symbol=%s package=%s body=%s\n' "$symbol" "$owner" "$final_body" \
        >> "$TMP/noheap.final.closure"
    cat "$TMP/bodies/$final_body" >> "$TMP/noheap.final.closure"
    printf 'BODY symbol=%s package=%s body=%s\n' "$symbol" "$owner" "$object_body" \
        >> "$TMP/noheap.object.closure"
    cat "$TMP/bodies/$object_body" >> "$TMP/noheap.object.closure"
    printf '%s\n' "$symbol" >> "$TMP/noheap.scanned.defs"
    NOHEAP_SCANNED_DEFS=$((NOHEAP_SCANNED_DEFS + 1))
done < "$TMP/noheap.reachable.defs"
sort -u -o "$TMP/noheap.scanned.defs" "$TMP/noheap.scanned.defs"
if ! cmp "$TMP/noheap.reachable.defs" "$TMP/noheap.scanned.defs"; then
    echo "TYPEDEF_NOHEAP_SET_EQUALITY status=FAIL" >&2
    exit 1
fi
NOHEAP_REACHABLE_DEFS=$(wc -l < "$TMP/noheap.reachable.defs")

LIVE_MCC_NEW_REFS=$(grep -E '(CJ_)?MCC_New' "$TMP/pre.closure.ll" \
    "$TMP/final.closure.ll" "$TMP/object.closure.txt" | wc -l || true)
LIVE_MANAGED_REFS=$(grep -E 'RawArrayAllocate|llvm\.cj\.alloca\.generic|CJ_MCC_(Write|Throw)|std\.core::(String|Array|ArrayList|HashMap)|lambda|closure' \
    "$TMP/pre.closure.ll" "$TMP/final.closure.ll" "$TMP/object.closure.txt" | wc -l || true)
LIVE_MEMCPY_REFS=$(grep -Ei 'llvm\.memcpy|R_X86_64_.*memcpy' "$TMP/pre.closure.ll" \
    "$TMP/final.closure.ll" "$TMP/object.closure.txt" | wc -l || true)

MCC_NEW_REFS=$(grep -E '(CJ_)?MCC_New' "$TMP/noheap.pre.closure" \
    "$TMP/noheap.final.closure" "$TMP/noheap.object.closure" | wc -l || true)
MANAGED_REFS=$(grep -E 'RawArrayAllocate|llvm\.cj\.alloca\.generic|CJ_MCC_(Write|Throw)|std\.core::(String|Array|ArrayList|HashMap)|lambda|closure' \
    "$TMP/noheap.pre.closure" "$TMP/noheap.final.closure" "$TMP/noheap.object.closure" | wc -l || true)
ILLEGAL_AS1=$(grep -E 'addrspacecast .*addrspace\(1\)\* .* to (i8|i16|i32|i64|void \(i8\*\))\*' \
    "$TMP/noheap.pre.closure" "$TMP/noheap.final.closure" | wc -l || true)
MEMCPY_REFS=$(grep -Ei 'llvm\.memcpy|R_X86_64_.*memcpy' "$TMP/noheap.pre.closure" \
    "$TMP/noheap.final.closure" "$TMP/noheap.object.closure" | wc -l || true)
INDIRECT_IR_SITES=$(grep -E 'call void %[A-Za-z0-9._-]+\(i8\* ' "$TMP/noheap.pre.closure" | wc -l || true)
INDIRECT_OBJECT_SITES=$(grep -E '\bcallq?[[:space:]]+\*' "$TMP/noheap.object.closure" | wc -l || true)
if [[ $MCC_NEW_REFS -ne 0 || $MANAGED_REFS -ne 0 || $ILLEGAL_AS1 -ne 0 ||
      $MEMCPY_REFS -ne 0 || $INDIRECT_IR_SITES -ne 1 ||
      $INDIRECT_OBJECT_SITES -ne 1 ]]; then
    echo "TYPEDEF_NOHEAP_SCAN mcc_new=$MCC_NEW_REFS managed=$MANAGED_REFS illegal_as1=$ILLEGAL_AS1 memcpy=$MEMCPY_REFS indirect_ir=$INDIRECT_IR_SITES indirect_object=$INDIRECT_OBJECT_SITES status=FAIL" >&2
    exit 1
fi

# Production archive checks apply to the complete live rt.common archive built above.
PRODUCTION_EXPORTS=$(nm --defined-only "$TMP/librt.common.a" | \
    awk '$3 ~ /^(CJRT_TypeDef|TypeDefProbe)/ {++n} END {print n+0}')
SHADOW_BSS=$(nm --defined-only "$TMP/librt.common.a" | \
    awk '$2 ~ /^[Bb]$/ && $3 ~ /(MAddress|MSize|MOffset|MIndex|ObjRef|ArrayRef|FuncRef|FuncDescRef|StringRef|ExceptionRef|MethodInfoRef|PackageInfoRef|ParameterInfoRef|FuncPtr|AllocType)/ {++n} END {print n+0}')
SHADOW_DATA=$(nm --defined-only "$TMP/librt.common.a" | \
    awk '$2 ~ /^[Dd]$/ && $3 ~ /(MAddress|MSize|MOffset|MIndex|ObjRef|ArrayRef|FuncRef|FuncDescRef|StringRef|ExceptionRef|MethodInfoRef|PackageInfoRef|ParameterInfoRef|FuncPtr|AllocType)/ {++n} END {print n+0}')
if [[ $PRODUCTION_EXPORTS -ne 0 || $SHADOW_BSS -ne 0 || $SHADOW_DATA -ne 0 ]]; then
    echo "TYPEDEF_PRODUCTION exports=$PRODUCTION_EXPORTS shadow_bss=$SHADOW_BSS shadow_data=$SHADOW_DATA status=FAIL" >&2
    exit 1
fi

# Canonical ownership, restricted production dialect, and exact platform audit.
ARRAYREF_OWNERS=$(rg -n '^public type ArrayRef = ' "$ROOT/src/rt.common" --glob '*.cj' | wc -l)
STACKTYPE_DUPLICATES=$(rg -n '^public type ArrayRef = ' "$ROOT/src/rt.common/StackType.cj" | wc -l || true)
FORBIDDEN_SOURCE=$(rg -n '\b(String|Array|ArrayList|HashMap)\b|\b(throw|try|catch|malloc|free)\b|=>|interpol' \
    "$ROOT/src/rt.common/TypeDef.cj" | wc -l || true)
BRIDGE_SOURCE=$(rg -n 'Atomic|Futex|Panic|PagePoolMutex|foreign func|malloc|free' \
    "$ROOT/src/rt.common/TypeDef.cj" | wc -l || true)
OS_BRANCHES=$(rg -n '_WIN32|__APPLE__|__OHOS__|__linux__|hongmeng|#elif' \
    "$RUNTIME_ROOT/src/Common/TypeDef.h" | wc -l || true)
CPP_LINKAGE=$(rg -n '#ifdef __cplusplus' "$RUNTIME_ROOT/src/Common/TypeDef.h" | wc -l || true)
if [[ $ARRAYREF_OWNERS -ne 1 || $STACKTYPE_DUPLICATES -ne 0 ||
      $FORBIDDEN_SOURCE -ne 0 || $BRIDGE_SOURCE -ne 0 || $OS_BRANCHES -ne 0 ||
      $CPP_LINKAGE -ne 2 ]]; then
    echo "TYPEDEF_SOURCE owners=$ARRAYREF_OWNERS stacktype_duplicates=$STACKTYPE_DUPLICATES forbidden=$FORBIDDEN_SOURCE bridges=$BRIDGE_SOURCE os_branches=$OS_BRANCHES cpp_linkage=$CPP_LINKAGE status=FAIL" >&2
    exit 1
fi

# The four unchanged accepted regressions are prerequisites, invoked by absolute path
# from the TypeDef workspace with complete summaries preserved both here and in logs.
REGRESSION_STACK="$ROOT/test/parity/common/run_stacktype_probe.sh"
REGRESSION_STATE="$ROOT/test/parity/common/run_stateword_probe.sh"
REGRESSION_REGION="$ROOT/test/parity/heap/run_regioninfo_probe.sh"
REGRESSION_PAGE="$ROOT/test/parity/common/run_pagepool_probe.sh"
(cd "$TMP" && "$REGRESSION_STACK") | tee "$TMP/regression.stacktype.log"
grep -Fxq 'STACKTYPE_PROBE PASS records=29 byte_structs=4' "$TMP/regression.stacktype.log"
(cd "$TMP" && "$REGRESSION_STATE") | tee "$TMP/regression.stateword.log"
grep -Fxq 'run_stateword_probe: PASS' "$TMP/regression.stateword.log"
(cd "$TMP" && "$REGRESSION_REGION") | tee "$TMP/regression.regioninfo.log"
grep -Fxq 'run_regioninfo_probe: PASS' "$TMP/regression.regioninfo.log"
(cd "$TMP" && "$REGRESSION_PAGE") | tee "$TMP/regression.pagepool.log"
grep -Fxq 'run_pagepool_probe: PASS' "$TMP/regression.pagepool.log"

PACKAGE_SUMMARY=""
for package in rt.base rt.sync rt.heap.allocator rt.common rt.demangle rt.stackmap rt.abi; do
    archive="$TMP/lib$package.a"
    test -s "$archive"
    archive_size=$(stat -c %s "$archive")
    PACKAGE_SUMMARY="$PACKAGE_SUMMARY $package=$archive_size"
done

artifact_manifest > "$TMP/repository.after.manifest"
if ! cmp "$TMP/repository.before.manifest" "$TMP/repository.after.manifest"; then
    diff -u "$TMP/repository.before.manifest" "$TMP/repository.after.manifest" >&2 || true
    echo "TYPEDEF_ARTIFACT_ISOLATION status=FAIL" >&2
    exit 1
fi
ARTIFACT_COUNT=$(wc -l < "$TMP/repository.before.manifest")
ARTIFACT_SHA=$(sha256sum "$TMP/repository.before.manifest" | awk '{print $1}')
MANIFEST_SHA=$(sha256sum "$TMP/body.manifest" | awk '{print $1}')

echo "TYPEDEF_LAYOUT maddress=8/8 msize=4/4 moffset=4/4 mindex=8/8 refs=8/8 funcptr=8/8 alloctype=4/4 status=PASS"
echo "TYPEDEF_CONSTANTS null=0 generic_payload=2147483647 max_array=18446744073709551615 alloc=0,1,2 status=PASS"
echo "TYPEDEF_FUNCPTR callbacks=4096 indirect_calls=4096 ir_sites=$INDIRECT_IR_SITES object_sites=$INDIRECT_OBJECT_SITES status=PASS"
echo "TYPEDEF_ALIGN_PARITY operations=$ALIGN_OPERATIONS records=$RECORDS bytes=$BYTES sha256=$TRANSCRIPT_SHA cmp=PASS"
echo "TYPEDEF_DEFINITION_STAGES pre=$INDEXED_DEFS final=$FINAL_INDEXED_DEFS object=$OBJECT_INDEXED_DEFS linked_pre=$LINKED_DEFS duplicate_excess=$DUPLICATE_EXCESS status=PASS"
echo "TYPEDEF_DEFINITION_UNIVERSE packages=$DERIVED_PACKAGES indexed_defs=$INDEXED_DEFS base=$BASE_INDEXED sync=$SYNC_INDEXED allocator=$ALLOCATOR_INDEXED common=$COMMON_INDEXED driver=$DRIVER_INDEXED missing_owners=0 ambiguous=0 status=PASS"
echo "TYPEDEF_LIVE_CLOSURE packages=$REACHABLE_PACKAGES reachable_defs=$REACHABLE_DEFS scanned_defs=$SCANNED_DEFS base=$BASE_REACHABLE sync=$SYNC_REACHABLE allocator=$ALLOCATOR_REACHABLE common=$COMMON_REACHABLE driver=$DRIVER_REACHABLE missing=0 unresolved_live=0 status=PASS"
echo "TYPEDEF_LIVE_INITIALIZER_BODIES roots=$INIT_ROOTS live_mcc_new_refs=$LIVE_MCC_NEW_REFS live_managed_refs=$LIVE_MANAGED_REFS live_memcpy_refs=$LIVE_MEMCPY_REFS scope=INDEXED_NOT_TYPEDEF_REPRESENTATION status=PASS"
echo "TYPEDEF_NOHEAP_CLOSURE roots=$(wc -l < "$TMP/roots") reachable_defs=$NOHEAP_REACHABLE_DEFS scanned_defs=$NOHEAP_SCANNED_DEFS missing=0 mcc_new_refs=0 managed_refs=0 status=PASS"
echo "TYPEDEF_BODY_MANIFEST entries=$SCANNED_DEFS sha256=$MANIFEST_SHA ambiguous=0 status=PASS"
echo "TYPEDEF_ABI scalar_signatures=4 refs=9 funcptr=1 alloctype=1 align=4 illegal_as1_to_as0=0 memcpy=0 shadow_bss=0 shadow_data=0 production_exports=0 status=PASS"
echo "TYPEDEF_STATIC_INITIALIZERS executable=$INIT_ROOTS rooted=$INIT_ROOTS typedef=1 constant_globals=3 status=PASS"
echo "TYPEDEF_PLATFORM cpp_linkage_wrappers=2 os_arch_branches=0 linux_x86_64=EXECUTED other_pointer_width_targets=UNEXECUTED_DEBT status=PASS"
echo "TYPEDEF_REGRESSIONS stacktype=PASS stateword=PASS regioninfo=PASS pagepool=PASS status=PASS"
echo "TYPEDEF_ALL_PACKAGES count=7$PACKAGE_SUMMARY status=PASS"
echo "TYPEDEF_ARTIFACT_ISOLATION entries=$ARTIFACT_COUNT sha256=$ARTIFACT_SHA unchanged=PASS"
echo "TYPEDEF_BINARIES cpp_sha256=$(sha256sum "$TMP/typedef_cpp" | awk '{print $1}') cj_sha256=$(sha256sum "$TMP/typedef_cj" | awk '{print $1}') production_archive_sha256=$(sha256sum "$TMP/librt.common.a" | awk '{print $1}') header_sha256=$(sha256sum "$RUNTIME_ROOT/src/Common/TypeDef.h" | awk '{print $1}')"
df -h / | tail -n 1 | sed 's/^/TYPEDEF_DISK_AFTER /'
echo "run_typedef_probe: PASS"
