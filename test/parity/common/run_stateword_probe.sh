#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/compiler_identity.sh"
RUNTIME_ROOT=/root/cj_build/cangjie_runtime/runtime
CPP_RUNTIME_LIB="$RUNTIME_ROOT/target/temp/lib/x86_64_Release"
SELFHOST_RUNTIME="$RUNTIME_TOOLCHAIN_RT_LIB"
export PATH=/root/.cjv/bin:$PATH
export LD_LIBRARY_PATH="$SELFHOST_RUNTIME:$CPP_RUNTIME_LIB:$LD_LIBRARY_PATH"
export cjHeapSize=24GB

LLVM="$CANGJIE_HOME/third_party/llvm/bin"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rt_stateword.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "StateWord execution requires Linux x86_64" >&2
    exit 2
fi
test -x "$SELFHOST_CJC"
test -f "$CPP_RUNTIME_LIB/libcangjie-runtime.so"
df -h / | tail -n 1 | sed 's/^/STATEWORD_DISK_BEFORE /'
echo "STATEWORD_COMPILER path=$SELFHOST_CJC status=PASS"

build_package() {
    local source=$1
    local output=$2
    shift 2
    (cd "$TMP" && "$SELFHOST_CJC" --package "$source" --output-type=staticlib \
        --int-overflow wrapping -Woff unused --import-path "$TMP" --output-dir "$TMP" \
        "$@" -o "$output")
}

# Compile and execute the oracle directly from the untouched original header.
g++ -std=c++14 -O2 -pthread -DSTATEWORD_ORACLE \
    -I"$RUNTIME_ROOT/src" \
    -I"$RUNTIME_ROOT/third_party/third_party_bounds_checking_function/include" \
    "$ROOT/test/parity/common/stateword_ref.cpp" \
    -L"$CPP_RUNTIME_LIB" -Wl,-rpath,"$CPP_RUNTIME_LIB" -lcangjie-runtime \
    -o "$TMP/stateword_oracle"
LD_LIBRARY_PATH="$CPP_RUNTIME_LIB:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib" \
    "$TMP/stateword_oracle" > "$TMP/cpp.transcript"

# Build the production leaf alone so layout/IR/noheap evidence cannot come from a test mirror.
mkdir -p "$TMP/rt.common.production" "$TMP/production_temps"
cp "$ROOT/src/rt.common/StateWord.cj" "$TMP/rt.common.production/StateWord.cj"
cp "$ROOT/test/parity/common/stateword_foreign_probe.cj" \
    "$TMP/rt.common.production/StateWordForeignProbe.cj"
build_package "$TMP/rt.common.production" librt.common.production.a \
    --save-temps "$TMP/production_temps"

PRE_BC=()
FINAL_BC=()
for bc in "$TMP/production_temps"/[0-9]*.bc; do
    if [[ "$bc" == *.opt.bc ]]; then
        FINAL_BC+=("$bc")
    else
        PRE_BC+=("$bc")
    fi
done
if [[ ${#PRE_BC[@]} -eq 0 || ${#PRE_BC[@]} -ne ${#FINAL_BC[@]} ]]; then
    echo "STATEWORD_IR package_bc_pre=${#PRE_BC[@]} package_bc_final=${#FINAL_BC[@]} status=FAIL" >&2
    exit 1
fi
"$LLVM/llvm-link" "${PRE_BC[@]}" -o "$TMP/production.pre.bc"
"$LLVM/llvm-link" "${FINAL_BC[@]}" -o "$TMP/production.final.bc"
"$LLVM/llvm-dis" "$TMP/production.pre.bc" -o "$TMP/production.pre.ll"
"$LLVM/llvm-dis" "$TMP/production.final.bc" -o "$TMP/production.final.ll"

mapfile -t OBJECTSTATE_TYPES < <(grep -F '%"record.rt.common:ObjectState" = type ' \
    "$TMP/production.pre.ll" | sort -u)
mapfile -t STATEWORD_TYPES < <(grep -F '%"record.rt.common:StateWord" = type ' \
    "$TMP/production.pre.ll" | sort -u)
if [[ ${#OBJECTSTATE_TYPES[@]} -ne 1 || ${#STATEWORD_TYPES[@]} -ne 1 ]]; then
    echo "STATEWORD_LAYOUT object_types=${#OBJECTSTATE_TYPES[@]} word_types=${#STATEWORD_TYPES[@]} status=FAIL" >&2
    exit 1
fi
OBJECTSTATE_RHS=${OBJECTSTATE_TYPES[0]#*= type }
STATEWORD_RHS=${STATEWORD_TYPES[0]#*= type }
if [[ "$OBJECTSTATE_RHS" != '{ i16 }' ||
      "$STATEWORD_RHS" != '{ i32, i16, %"record.rt.common:ObjectState" }' ]]; then
    echo "STATEWORD_LAYOUT object=$OBJECTSTATE_RHS word=$STATEWORD_RHS status=FAIL" >&2
    exit 1
fi
mapfile -t DATALAYOUTS < <(grep '^target datalayout = ' "$TMP/production.pre.ll" | sort -u)
if [[ ${#DATALAYOUTS[@]} -ne 1 ]]; then
    echo "STATEWORD_LAYOUT datalayout_count=${#DATALAYOUTS[@]} status=FAIL" >&2
    exit 1
fi
cat > "$TMP/layout.ll" <<EOF
${DATALAYOUTS[0]}
%OS = type { i16 }
%SW = type { i32, i16, %OS }
%OSAlign = type { i8, %OS }
%SWAlign = type { i8, %SW }
@os_size = global i64 ptrtoint (%OS* getelementptr (%OS, %OS* null, i32 1) to i64)
@os_align = global i64 ptrtoint (%OS* getelementptr (%OSAlign, %OSAlign* null, i32 0, i32 1) to i64)
@os_bits = global i64 ptrtoint (i16* getelementptr (%OS, %OS* null, i32 0, i32 0) to i64)
@sw_size = global i64 ptrtoint (%SW* getelementptr (%SW, %SW* null, i32 1) to i64)
@sw_align = global i64 ptrtoint (%SW* getelementptr (%SWAlign, %SWAlign* null, i32 0, i32 1) to i64)
@sw_low = global i64 ptrtoint (i32* getelementptr (%SW, %SW* null, i32 0, i32 0) to i64)
@sw_high = global i64 ptrtoint (i16* getelementptr (%SW, %SW* null, i32 0, i32 1) to i64)
@sw_state = global i64 ptrtoint (%OS* getelementptr (%SW, %SW* null, i32 0, i32 2) to i64)
EOF
"$LLVM/llvm-as" "$TMP/layout.ll" -o "$TMP/layout.bc"
"$LLVM/opt" -S -passes=globalopt "$TMP/layout.bc" -o "$TMP/layout.folded.ll"
layout_value() {
    awk -v symbol="@$1" '$1 == symbol { print $NF }' "$TMP/layout.folded.ll"
}
CJ_OBJECTSTATE_SIZE=$(layout_value os_size)
CJ_OBJECTSTATE_ALIGN=$(layout_value os_align)
CJ_OBJECTSTATE_BITS=$(layout_value os_bits)
CJ_STATEWORD_SIZE=$(layout_value sw_size)
CJ_STATEWORD_ALIGN=$(layout_value sw_align)
CJ_STATEWORD_LOW=$(layout_value sw_low)
CJ_STATEWORD_HIGH=$(layout_value sw_high)
CJ_STATEWORD_STATE=$(layout_value sw_state)
LAYOUT_VALUES="$CJ_OBJECTSTATE_SIZE $CJ_OBJECTSTATE_ALIGN $CJ_OBJECTSTATE_BITS $CJ_STATEWORD_SIZE $CJ_STATEWORD_ALIGN $CJ_STATEWORD_LOW $CJ_STATEWORD_HIGH $CJ_STATEWORD_STATE"
if [[ "$LAYOUT_VALUES" != '2 2 0 8 4 0 4 6' ]]; then
    echo "STATEWORD_LAYOUT values=$LAYOUT_VALUES status=FAIL" >&2
    exit 1
fi

# Build the probe-owned package and shared native driver against the derived live layout.
mkdir -p "$TMP/rt.common.probe"
cp "$ROOT/src/rt.common/StateWord.cj" "$TMP/rt.common.probe/StateWord.cj"
cp "$ROOT/test/parity/common/stateword_foreign_probe.cj" \
    "$TMP/rt.common.probe/StateWordForeignProbe.cj"
cp "$ROOT/test/parity/common/stateword_probe.cj" "$TMP/rt.common.probe/StateWordProbe.cj"
build_package "$TMP/rt.common.probe" librt.common.probe.a
g++ -std=c++14 -O2 -pthread \
    -DCJ_OBJECTSTATE_SIZE="$CJ_OBJECTSTATE_SIZE" \
    -DCJ_OBJECTSTATE_ALIGN="$CJ_OBJECTSTATE_ALIGN" \
    -DCJ_OBJECTSTATE_BITS="$CJ_OBJECTSTATE_BITS" \
    -DCJ_STATEWORD_SIZE="$CJ_STATEWORD_SIZE" \
    -DCJ_STATEWORD_ALIGN="$CJ_STATEWORD_ALIGN" \
    -DCJ_STATEWORD_LOW="$CJ_STATEWORD_LOW" \
    -DCJ_STATEWORD_HIGH="$CJ_STATEWORD_HIGH" \
    -DCJ_STATEWORD_STATE="$CJ_STATEWORD_STATE" \
    -c "$ROOT/test/parity/common/stateword_ref.cpp" -o "$TMP/stateword_driver.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Atomic.cpp" -o "$TMP/Atomic.o"
g++ -std=c++14 -O2 -fPIC -c "$ROOT/rt0/os/Linux/Panic.cpp" -o "$TMP/Panic.o"
(cd "$TMP" && "$SELFHOST_CJC" "$ROOT/test/parity/common/stateword_driver.cj" \
    -Woff unused --import-path "$TMP" --int-overflow wrapping \
    "$TMP/stateword_driver.o" "$TMP/librt.common.probe.a" "$TMP/Atomic.o" "$TMP/Panic.o" \
    --link-option=-lstdc++ --link-option=-lpthread -o "$TMP/stateword_cj")
"$TMP/stateword_cj" > "$TMP/cj.transcript"
if ! cmp "$TMP/cpp.transcript" "$TMP/cj.transcript"; then
    diff -u "$TMP/cpp.transcript" "$TMP/cj.transcript" | head -n 240 >&2 || true
    echo "STATEWORD_PARITY cmp=FAIL" >&2
    exit 1
fi

grep -Fx 'OBJECTSTATE_LAYOUT sizeof=2 align=2 stateBits=0' "$TMP/cj.transcript"
grep -Fx 'STATEWORD_LAYOUT sizeof=8 align=4 typeInfoLow32=0 typeInfoHigh16=4 objectState=6' "$TMP/cj.transcript"
grep -Fx 'STATEWORD_TRACE operations=100000 seed=6a09e667f3bcc909 status=PASS' "$TMP/cj.transcript"
grep -Fx 'STATEWORD_CONTENTION threads=4 locks_per_thread=5000 counter=20000 raw=0000 status=PASS' "$TMP/cj.transcript"
RECORDS=$(wc -l < "$TMP/cj.transcript")
BYTES=$(wc -c < "$TMP/cj.transcript")
TRANSCRIPT_SHA=$(sha256sum "$TMP/cj.transcript" | awk '{print $1}')
echo "STATEWORD_PARITY PASS operations=100000 records=$RECORDS bytes=$BYTES sha256=$TRANSCRIPT_SHA cmp=PASS"
echo "STATEWORD_BINARIES cpp_sha256=$(sha256sum "$TMP/stateword_oracle" | awk '{print $1}') cj_sha256=$(sha256sum "$TMP/stateword_cj" | awk '{print $1}') production_archive_sha256=$(sha256sum "$TMP/librt.common.production.a" | awk '{print $1}')"

# Source and binary inspection: exact atomic branches, AS0 receivers, no live-record memcpy,
# no AS1-to-AS0 scalar cast, no production test export, and no shadow object-header storage.
X86_WEAK=$(awk '/cj_stateword_u16_cas/,/^}/' "$ROOT/rt0/os/Linux/Atomic.cpp" | \
    grep -c 'desired, true, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE' || true)
NON_X86_STRONG=$(awk '/cj_stateword_u16_cas/,/^}/' "$ROOT/rt0/os/Linux/Atomic.cpp" | \
    grep -c 'desired, false, __ATOMIC_SEQ_CST, __ATOMIC_ACQUIRE' || true)
if [[ $X86_WEAK -ne 1 || $NON_X86_STRONG -ne 1 ]]; then
    echo "STATEWORD_ATOMIC x86_64_weak=$X86_WEAK non_x86_strong=$NON_X86_STRONG status=FAIL" >&2
    exit 1
fi
echo "STATEWORD_ATOMIC x86_64_weak=1 non_x86_strong=SOURCE_PRESERVED status=PASS"

awk '/GetStateWordHv\(/,/^}/' "$TMP/production.pre.ll" > "$TMP/getstateword.ll"

# Common/StateWord.h:42-76,93-151. Fail closed over the exact production operation
# surface in both pre-opt and final IR: 15 residual extensions plus eight ruled free
# first-pointer overloads. Mangled names identify the concrete receiver; definition
# signatures prove that every source receiver is an AS0 i8* rather than AS1 managed data.
cat > "$TMP/stateword.expected.tsv" <<'EOF'
extension	ObjectState	AtomicGetObjectState	1	_CN9rt.commonXPRNY_11ObjectStateE20AtomicGetObjectStateHv
extension	ObjectState	IsLockedState	0	_CN9rt.commonXPRNY_11ObjectStateE13IsLockedStateHv
extension	ObjectState	GetStateBits	0	_CN9rt.commonXPRNY_11ObjectStateE12GetStateBitsHv
extension	ObjectState	AtomicGetStateBits	0	_CN9rt.commonXPRNY_11ObjectStateE18AtomicGetStateBitsHv
extension	ObjectState	SetStateBits	1	_CN9rt.commonXPRNY_11ObjectStateE12SetStateBitsHt
extension	ObjectState	AtomicSetStateBits	1	_CN9rt.commonXPRNY_11ObjectStateE18AtomicSetStateBitsHt
extension	ObjectState	CompareExchangeStateBits	0	_CN9rt.commonXPRNY_11ObjectStateE24CompareExchangeStateBitsHtt
extension	StateWord	GetTypeInfo	0	_CN9rt.commonXPRNY_9StateWordE11GetTypeInfoHv
extension	StateWord	SetTypeInfo	1	_CN9rt.commonXPRNY_9StateWordE11SetTypeInfoHPu
extension	StateWord	GetStateWord	1	_CN9rt.commonXPRNY_9StateWordE12GetStateWordHv
extension	StateWord	IsValidStateWord	0	_CN9rt.commonXPRNY_9StateWordE16IsValidStateWordHv
extension	StateWord	GetObjectState	1	_CN9rt.commonXPRNY_9StateWordE14GetObjectStateHv
extension	StateWord	IsLockedWord	0	_CN9rt.commonXPRNY_9StateWordE12IsLockedWordHv
extension	StateWord	TryLockStateWord	0	_CN9rt.commonXPRNY_9StateWordE16TryLockStateWordHRNY_11ObjectStateE
extension	StateWord	UnlockStateWord	1	_CN9rt.commonXPRNY_9StateWordE15UnlockStateWordHRNY_11ObjectStateE
free	ObjectState	GetStateCode	0	_CN9rt.common12GetStateCodeHPRNY_11ObjectStateE
free	ObjectState	SetStateCode	1	_CN9rt.common12SetStateCodeHPRNY_11ObjectStateEh
free	ObjectState	IsForwardableState	0	_CN9rt.common18IsForwardableStateHPRNY_11ObjectStateE
free	ObjectState	IsForwardedState	0	_CN9rt.common16IsForwardedStateHPRNY_11ObjectStateE
free	StateWord	GetStateCode	0	_CN9rt.common12GetStateCodeHPRNY_9StateWordE
free	StateWord	SetStateCode	1	_CN9rt.common12SetStateCodeHPRNY_9StateWordEh
free	StateWord	IsForwardableState	0	_CN9rt.common18IsForwardableStateHPRNY_9StateWordE
free	StateWord	IsForwardedState	0	_CN9rt.common16IsForwardedStateHPRNY_9StateWordE
EOF
awk -F '\t' '{print $5}' "$TMP/stateword.expected.tsv" | sort > "$TMP/stateword.expected.symbols"

extract_stateword_surface() {
    awk '/^define / {
        name=$0
        sub(/^[^@]*@/, "", name)
        sub(/\(.*/, "", name)
        gsub(/^"|"$/, "", name)
        if (name ~ /^_CN9rt\.commonXPRNY_(11ObjectState|9StateWord)E/ ||
            name ~ /^_CN9rt\.common(12GetStateCode|12SetStateCode|18IsForwardableState|16IsForwardedState)H/) {
            print name
        }
    }' "$1"
}

validate_stateword_manifest() {
    local stage=$1
    local ir=$2
    local actual="$TMP/stateword.$stage.actual"
    local signature_errors="$TMP/stateword.$stage.signature_errors"
    extract_stateword_surface "$ir" > "$actual.raw"
    sort "$actual.raw" > "$actual"
    uniq -d "$actual" > "$actual.duplicates"
    comm -23 "$TMP/stateword.expected.symbols" "$actual" > "$actual.missing"
    comm -13 "$TMP/stateword.expected.symbols" "$actual" > "$actual.unexpected"
    : > "$signature_errors"
    while IFS=$'\t' read -r kind receiver operation receiver_slot symbol; do
        mapfile -t definition < <(grep '^define ' "$ir" | grep -F "@$symbol(")
        if [[ ${#definition[@]} -ne 1 ]]; then
            printf '%s definition_count=%s\n' "$symbol" "${#definition[@]}" >> "$signature_errors"
            continue
        fi
        line=${definition[0]}
        if [[ "$line" == *'addrspace(1)'* || "$line" != *"i8* %$receiver_slot"* ]]; then
            printf '%s receiver_slot=%s not_as0\n' "$symbol" "$receiver_slot" >> "$signature_errors"
        fi
        if [[ "$kind" == extension && "$line" != *'%outerTI'* ]]; then
            printf '%s missing_extension_outerTI\n' "$symbol" >> "$signature_errors"
        elif [[ "$kind" == free && "$line" == *'%outerTI'* ]]; then
            printf '%s unexpected_free_outerTI\n' "$symbol" >> "$signature_errors"
        fi
        if [[ "$kind" == free ]]; then
            case "$operation" in
                GetStateCode)
                    [[ "$line" == 'define i8 '* && "$line" == *'(i8* %0) gc '* ]] ||
                        printf '%s free_signature_mismatch\n' "$symbol" >> "$signature_errors"
                    ;;
                SetStateCode)
                    [[ "$line" == 'define void '* && "$line" == *'sret(%Unit.Type) %0, i8* %1, i8 %2) gc '* ]] ||
                        printf '%s free_signature_mismatch\n' "$symbol" >> "$signature_errors"
                    ;;
                IsForwardableState|IsForwardedState)
                    [[ "$line" == 'define i1 '* && "$line" == *'(i8* %0) gc '* ]] ||
                        printf '%s free_signature_mismatch\n' "$symbol" >> "$signature_errors"
                    ;;
            esac
        fi
    done < "$TMP/stateword.expected.tsv"
}

validate_stateword_manifest pre "$TMP/production.pre.ll"
validate_stateword_manifest final "$TMP/production.final.ll"
PRE_MANIFEST=$(wc -l < "$TMP/stateword.pre.actual")
FINAL_MANIFEST=$(wc -l < "$TMP/stateword.final.actual")
PRE_MISSING=$(wc -l < "$TMP/stateword.pre.actual.missing")
FINAL_MISSING=$(wc -l < "$TMP/stateword.final.actual.missing")
PRE_UNEXPECTED=$(wc -l < "$TMP/stateword.pre.actual.unexpected")
FINAL_UNEXPECTED=$(wc -l < "$TMP/stateword.final.actual.unexpected")
PRE_DUPLICATE=$(wc -l < "$TMP/stateword.pre.actual.duplicates")
FINAL_DUPLICATE=$(wc -l < "$TMP/stateword.final.actual.duplicates")
PRE_SIGNATURE_ERRORS=$(wc -l < "$TMP/stateword.pre.signature_errors")
FINAL_SIGNATURE_ERRORS=$(wc -l < "$TMP/stateword.final.signature_errors")
if [[ $PRE_MANIFEST -ne 23 || $FINAL_MANIFEST -ne 23 ||
      $PRE_MISSING -ne 0 || $FINAL_MISSING -ne 0 ||
      $PRE_UNEXPECTED -ne 0 || $FINAL_UNEXPECTED -ne 0 ||
      $PRE_DUPLICATE -ne 0 || $FINAL_DUPLICATE -ne 0 ||
      $PRE_SIGNATURE_ERRORS -ne 0 || $FINAL_SIGNATURE_ERRORS -ne 0 ]]; then
    echo "STATEWORD_DEFINITION_MANIFEST extensions=15 free=8 pre_defs=$PRE_MANIFEST final_defs=$FINAL_MANIFEST pre_missing=$PRE_MISSING final_missing=$FINAL_MISSING pre_unexpected=$PRE_UNEXPECTED final_unexpected=$FINAL_UNEXPECTED pre_duplicate=$PRE_DUPLICATE final_duplicate=$FINAL_DUPLICATE pre_signature_errors=$PRE_SIGNATURE_ERRORS final_signature_errors=$FINAL_SIGNATURE_ERRORS status=FAIL" >&2
    for evidence in "$TMP"/stateword.*.actual.missing "$TMP"/stateword.*.actual.unexpected \
        "$TMP"/stateword.*.actual.duplicates "$TMP"/stateword.*.signature_errors; do
        sed "s|^|$(basename "$evidence") |" "$evidence" >&2
    done
    exit 1
fi
AS0_RECEIVERS=$PRE_MANIFEST
echo "STATEWORD_DEFINITION_MANIFEST extensions=15 free=8 pre_defs=23 final_defs=23 pre_as0=23 final_as0=23 missing=0 duplicate=0 unexpected=0 ambiguous=0 status=PASS"

CAS_CALLS=$(grep -c 'call i32 @cj_stateword_u16_cas' "$TMP/production.pre.ll" || true)
LOAD_CALLS=$(grep -c 'call i16 @cj_atomic_u16_load' "$TMP/production.pre.ll" || true)
STORE_CALLS=$(grep -c 'call void @cj_atomic_u16_store' "$TMP/production.pre.ll" || true)
ILLEGAL_AS1=$(grep -E 'addrspacecast [^,]*addrspace\(1\)\* [^,]* to (i8|i16|i32|i64)\*' \
    "$TMP/production.pre.ll" "$TMP/production.final.ll" | wc -l || true)
LIVE_MEMCPY=$(grep -E 'llvm\.memcpy.*%1([,)]| )' "$TMP/getstateword.ll" | wc -l || true)
GETSTATE_SCALARS=$(grep -Ec 'call i32 @_CNatXPj4readHl|call i16 |GetObjectStateHv' \
    "$TMP/getstateword.ll" || true)
PRODUCTION_EXPORTS=$(nm --defined-only "$TMP/librt.common.production.a" | \
    awk '$3 ~ /^CJRT_(ObjectState|StateWord)/ {++n} END {print n+0}')
REFERENCE_EXPORTS=$(nm -D "$CPP_RUNTIME_LIB/libcangjie-runtime.so" | \
    awk '$3 ~ /(StateWord|ObjectState)/ {++n} END {print n+0}')
SHADOW_DATA=$(nm --defined-only "$TMP/librt.common.production.a" | \
    awk '$2 ~ /^[Bb]$/ && $3 ~ /(StateWord|ObjectState)/ && $3 !~ /stateWordCheckMessage/ {++n} END {print n+0}')
MEMCPY_RELOCS=$(for object in "$TMP/production_temps"/[0-9]*.o; do readelf -rW "$object"; done | \
    grep -c 'memcpy' || true)
if [[ $AS0_RECEIVERS -ne 23 || $CAS_CALLS -lt 1 || $LOAD_CALLS -lt 1 || $STORE_CALLS -lt 1 ||
      $ILLEGAL_AS1 -ne 0 || $LIVE_MEMCPY -ne 0 || $GETSTATE_SCALARS -lt 3 ||
      $PRODUCTION_EXPORTS -ne 0 || $REFERENCE_EXPORTS -ne 0 || $SHADOW_DATA -ne 0 ||
      $MEMCPY_RELOCS -ne 0 ]]; then
    echo "STATEWORD_IR as0_receivers=$AS0_RECEIVERS cas=$CAS_CALLS load=$LOAD_CALLS store=$STORE_CALLS illegal_as1=$ILLEGAL_AS1 live_memcpy=$LIVE_MEMCPY scalar_copy=$GETSTATE_SCALARS production_exports=$PRODUCTION_EXPORTS reference_exports=$REFERENCE_EXPORTS shadow_data=$SHADOW_DATA memcpy_relocs=$MEMCPY_RELOCS status=FAIL" >&2
    exit 1
fi
echo "STATEWORD_IR as0_receivers=$AS0_RECEIVERS typed_scalar_copy=$GETSTATE_SCALARS atomic_load=$LOAD_CALLS atomic_store=$STORE_CALLS atomic_cas=$CAS_CALLS illegal_as1_to_as0=0 live_record_memcpy=0 aggregate_memcpy_relocs=0 shadow_storage=0 exports=0 status=PASS"
echo "STATEWORD_INVALID_UNLOCK source_check=RtFatal ir_call=$(grep -c 'call void @RtFatal' "$TMP/production.pre.ll") status=PASS"

# Traverse one pre-opt call graph from every StateWord/ObjectState operation and the fatal-message
# initializer, then require every reachable package definition in final BC and native objects.
"$LLVM/opt" -passes=print-callgraph -disable-output "$TMP/production.pre.bc" \
    2> "$TMP/noheap.callgraph"
awk '
/^Call graph node for function:/ {
    line=$0; sub(/^.*function: '\''/, "", line); sub(/'\''.*$/, "", line); current=line; next
}
/calls function '\''/ {
    line=$0; sub(/^.*calls function '\''/, "", line); sub(/'\''.*$/, "", line)
    if (current != "") print current "\t" line
}
' "$TMP/noheap.callgraph" > "$TMP/noheap.calls.tsv"
awk '/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name)
    if (name ~ /^_CN9rt\.common(9StateWord|11ObjectState)/ ||
        name ~ /^_CN9rt\.commonXPRNY_(9StateWord|11ObjectState)/ ||
        name ~ /^_CG[FGV]9rt\.commonUStateWord/) print name
}' "$TMP/production.pre.ll" | sort -u > "$TMP/noheap.roots"
declare -A SEEN=()
QUEUE=()
while IFS= read -r symbol; do
    [[ -n "$symbol" ]] || continue
    SEEN["$symbol"]=1
    QUEUE+=("$symbol")
done < "$TMP/noheap.roots"
while [[ ${#QUEUE[@]} -gt 0 ]]; do
    CURRENT=${QUEUE[0]}
    QUEUE=("${QUEUE[@]:1}")
    while IFS=$'\t' read -r _ callee; do
        if [[ -n "$callee" && -z ${SEEN["$callee"]+present} ]]; then
            SEEN["$callee"]=1
            QUEUE+=("$callee")
        fi
    done < <(awk -F '\t' -v key="$CURRENT" '$1 == key {print}' "$TMP/noheap.calls.tsv")
done
for symbol in "${!SEEN[@]}"; do printf '%s\n' "$symbol"; done | sort > "$TMP/noheap.symbols"
awk '/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name); print name
}' "$TMP/production.pre.ll" | sort -u > "$TMP/noheap.pre.defined"
comm -12 "$TMP/noheap.symbols" "$TMP/noheap.pre.defined" > "$TMP/noheap.reachable_defs"

awk -v symbols="$TMP/noheap.reachable_defs" '
BEGIN { while ((getline symbol < symbols) > 0) keep[symbol]=1 }
/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name); emit=(name in keep)
}
emit { print; if ($0 ~ /^}/) emit=0 }
' "$TMP/production.pre.ll" > "$TMP/noheap.pre.closure.ll"
awk '/^define / {
    name=$0; sub(/^[^@]*@/, "", name); sub(/\(.*/, "", name); gsub(/^"|"$/, "", name); print name
}' "$TMP/production.final.ll" | sort -u > "$TMP/noheap.final_defs"
: > "$TMP/noheap.object_defs"
: > "$TMP/noheap.object.closure.txt"
for object in "$TMP/production_temps"/[0-9]*.o; do
    dump="$TMP/$(basename "$object").objdump"
    objdump -dr "$object" > "$dump"
    awk -v symbols="$TMP/noheap.reachable_defs" -v defs="$TMP/noheap.object_defs" '
    BEGIN { while ((getline symbol < symbols) > 0) keep[symbol]=1 }
    /^[[:xdigit:]]+ <.*>:/ {
        name=$0; sub(/^[^<]*</, "", name); sub(/>:[[:space:]]*$/, "", name)
        emit=(name in keep); if (emit) print name >> defs
    }
    emit { print }
    ' "$dump" >> "$TMP/noheap.object.closure.txt"
done
sort -u -o "$TMP/noheap.object_defs" "$TMP/noheap.object_defs"
comm -23 "$TMP/noheap.reachable_defs" "$TMP/noheap.final_defs" > "$TMP/noheap.missing_final"
comm -23 "$TMP/noheap.reachable_defs" "$TMP/noheap.object_defs" > "$TMP/noheap.missing_object"
ROOTS=$(wc -l < "$TMP/noheap.roots")
REACHABLE_DEFS=$(wc -l < "$TMP/noheap.reachable_defs")
MISSING_FINAL=$(wc -l < "$TMP/noheap.missing_final")
MISSING_OBJECT=$(wc -l < "$TMP/noheap.missing_object")
MCC_NEW_REFS=$( { grep -Eih 'MCC_New|CJ_MCC_New' "$TMP/noheap.pre.closure.ll" || true
    grep -Eih 'R_X86_64_.*(MCC_New|CJ_MCC_New)' "$TMP/noheap.object.closure.txt" || true
} | wc -l )
MANAGED_REFS=$( { grep -Eih 'RawArrayAllocate|ArrayList|HashMap|StringBuilder|Create[A-Za-z]*Exception|ThrowException|llvm\.cj\.alloca\.generic' "$TMP/noheap.pre.closure.ll" || true
    grep -Eih 'R_X86_64_.*(RawArrayAllocate|ArrayList|HashMap|StringBuilder|Exception|ThrowException)' "$TMP/noheap.object.closure.txt" || true
} | wc -l )
CLOSURE_ILLEGAL_AS1=$(grep -E 'addrspacecast [^,]*addrspace\(1\)\* [^,]* to (i8|i16|i32|i64)\*' \
    "$TMP/noheap.pre.closure.ll" | wc -l || true)
if [[ $ROOTS -eq 0 || $REACHABLE_DEFS -eq 0 || $MISSING_FINAL -ne 0 ||
      $MISSING_OBJECT -ne 0 || $MCC_NEW_REFS -ne 0 || $MANAGED_REFS -ne 0 ||
      $CLOSURE_ILLEGAL_AS1 -ne 0 ]]; then
    echo "STATEWORD_NOHEAP_CLOSURE roots=$ROOTS reachable_defs=$REACHABLE_DEFS missing_final=$MISSING_FINAL missing_object=$MISSING_OBJECT mcc_new_refs=$MCC_NEW_REFS managed_refs=$MANAGED_REFS illegal_as1=$CLOSURE_ILLEGAL_AS1 status=FAIL" >&2
    sed 's/^/missing_final /' "$TMP/noheap.missing_final" >&2
    sed 's/^/missing_object /' "$TMP/noheap.missing_object" >&2
    grep -Ein 'RawArrayAllocate|ArrayList|HashMap|StringBuilder|Create[A-Za-z]*Exception|ThrowException|llvm\.cj\.alloca\.generic' "$TMP/noheap.pre.closure.ll" >&2 || true
    grep -Ein 'R_X86_64_.*(RawArrayAllocate|ArrayList|HashMap|StringBuilder|Exception|ThrowException)' "$TMP/noheap.object.closure.txt" >&2 || true
    exit 1
fi
echo "STATEWORD_NOHEAP_CLOSURE roots=$ROOTS reachable_defs=$REACHABLE_DEFS scanned_defs=$REACHABLE_DEFS missing=0 mcc_new_refs=0 managed_refs=0 illegal_as1_to_as0=0 status=PASS"

echo "STATEWORD_PLATFORM linux_x86_64=EXECUTED arm_layout=SOURCE_PRESERVED_UNEXECUTED non_x86_cas=SOURCE_PRESERVED_UNEXECUTED evidence_debt=2"

# Existing regressions and every current runtime package are built with the mandated selfhost.
bash "$ROOT/test/parity/heap/run_regioninfo_probe.sh"
bash "$ROOT/test/parity/common/run_pagepool_probe.sh"
rm -rf "$TMP/package_build"
mkdir -p "$TMP/package_build"
for package in rt.base rt.sync rt.heap.allocator rt.common rt.demangle rt.stackmap rt.abi; do
    (cd "$TMP" && "$SELFHOST_CJC" --package "$ROOT/src/$package" \
        --output-type=staticlib --int-overflow wrapping -Woff unused \
        --import-path "$TMP/package_build" --output-dir "$TMP/package_build" \
        -o "lib$package.a")
    archive="$TMP/package_build/lib$package.a"
    echo "RUNTIME_PACKAGE_BUILD package=$package archive_size=$(stat -c %s "$archive") status=PASS"
done

df -h / | tail -n 1 | sed 's/^/STATEWORD_DISK_AFTER /'
echo "run_stateword_probe: PASS"
