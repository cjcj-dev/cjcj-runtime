#!/usr/bin/env bash
set -euo pipefail

ORACLE=${1:-/root/cj_build/cangjie_runtime}
OUT=${2:-/root/cj_build/reports/RT_ALLOC_GC_SURVEY.tsv}
SRC="$ORACLE/runtime/src"
ARCHIVE_DIR="$ORACLE/runtime/target/temp/ar/x86_64_Relwithdebinfo"

mkdir -p "$(dirname "$OUT")"
printf 'record_kind\tlayer\tmodule\tfile\tline\tloc\tsymbol_kind\tvisibility\tsymbol\tdetail\tevidence\n' > "$OUT"
oracle_commit=$(git -C "$ORACLE" rev-parse HEAD)
printf 'metadata\t\t\t\t\t\tgit\t\toracle_commit\t%s\tgit rev-parse HEAD\n' "$oracle_commit" >> "$OUT"

classify()
{
    case "$1" in
        Common/*) echo 'Layer3;Common' ;;
        Heap/Allocator/*) echo 'Layer3;Heap/Allocator' ;;
        Heap/Barrier/*) echo 'Layer4;Heap/Barrier' ;;
        Heap/Collector/*) echo 'Layer4;Heap/Collector' ;;
        Heap/WCollector/*) echo 'Layer4;Heap/WCollector' ;;
        Heap/GcThreadPool.*|Heap/HeapWork.h) echo 'Layer4;Heap/core' ;;
        Heap/*) echo 'Layer3+4;Heap/facade' ;;
        Mutator/SafepointPageManager.h) echo 'Layer0-retained;SafepointPageManager' ;;
        Mutator/*) echo 'Layer4;Mutator' ;;
        HeapManager.*) echo 'Layer3+4;HeapManager' ;;
        arch/*/HandleSafepointStub.S) echo 'Layer0-retained;SafepointStub' ;;
        arch/*/CalleeSavedStub.S) echo 'Layer0-retained;AllocationStub' ;;
        CommonAlias.h|MacAlias.h|CompilerCalls.*|Cangjie.h|CangjieRuntimeApi.cpp) echo 'ABI-boundary;ABI' ;;
        *) echo 'boundary;other' ;;
    esac
}

emit_file()
{
    local rel=$1 meta layer module loc
    meta=$(classify "$rel")
    layer=${meta%%;*}
    module=${meta#*;}
    loc=$(wc -l < "$SRC/$rel")
    printf 'file\t%s\t%s\t%s\t\t%s\tfile\tsource\t\tfull file\twc -l\n' \
        "$layer" "$module" "$rel" "$loc" >> "$OUT"
}

while IFS= read -r file; do
    emit_file "${file#"$SRC/"}"
done < <(find "$SRC/Common" "$SRC/Heap" "$SRC/Mutator" -type f \( -name '*.h' -o -name '*.cpp' \) | sort)

for rel in HeapManager.cpp HeapManager.h HeapManager.inline.h CommonAlias.h MacAlias.h CompilerCalls.cpp CompilerCalls.h \
    Cangjie.h CangjieRuntimeApi.cpp; do
    emit_file "$rel"
done
while IFS= read -r file; do
    emit_file "${file#"$SRC/"}"
done < <(find "$SRC/arch" -type f \( -name 'HandleSafepointStub.S' -o -name 'CalleeSavedStub.S' \) | sort)

# Source-level named class/struct/enum declarations. Anonymous layout members are
# represented by their owning named type and are intentionally not separate rows.
while IFS= read -r file; do
    rel=${file#"$SRC/"}
    meta=$(classify "$rel")
    layer=${meta%%;*}
    module=${meta#*;}
    perl -ne '
        if (/^\s*(class|struct|enum(?:\s+class)?)\s+([A-Za-z_]\w*)(.*)$/) {
            ($kind, $name, $tail) = ($1, $2, $3);
            next if $tail =~ /^\s+[A-Za-z_]\w*(?:\s*\[[^]]*\])?\s*;/;
            $state = ($tail =~ /^\s*;/) ? "forward" : "definition";
            $text = $_; chomp $text; $text =~ s/\t/ /g;
            print "$.:$kind:$state:$name:$text\n";
        }
    ' "$file" | while IFS=: read -r line kind state name detail; do
        printf 'type\t%s\t%s\t%s\t%s\t\ttype-%s\t%s\t%s\t%s\tsource declaration\n' \
            "$layer" "$module" "$rel" "$line" "$kind" "$state" "$name" "$detail" >> "$OUT"
    done
done < <(find "$SRC/Common" "$SRC/Heap" "$SRC/Mutator" -type f \( -name '*.h' -o -name '*.cpp' \) | sort; \
         printf '%s\n' "$SRC/HeapManager.h")

archive_meta()
{
    case "$1" in
        Common) echo 'Layer3;Common;Common' ;;
        Allocator) echo 'Layer3;Heap/Allocator;Heap/Allocator' ;;
        Heap) echo 'Layer3+4;Heap/core;Heap' ;;
        Barrier) echo 'Layer4;Heap/Barrier;Heap/Barrier' ;;
        Collector) echo 'Layer4;Heap/Collector;Heap/Collector' ;;
        WCollector) echo 'Layer4;Heap/WCollector;Heap/WCollector' ;;
        Mutator) echo 'Layer4;Mutator;Mutator' ;;
    esac
}

# Existing official RelWithDebInfo archives give an exact linkable C++ symbol
# surface without rebuilding the oracle. Rows retain duplicates when two object
# files emit the same weak/template symbol.
for archive in Common Allocator Heap Barrier Collector WCollector Mutator; do
    path="$ARCHIVE_DIR/lib${archive}.a"
    meta=$(archive_meta "$archive")
    layer=${meta%%;*}; rest=${meta#*;}; module=${rest%%;*}; prefix=${rest#*;}
    nm -A -g --defined-only -P "$path" | while read -r owner mangled type _value size; do
        member=${owner##*\[}; member=${member%\]:}
        source=${member%.o}
        demangled=$(printf '%s\n' "$mangled" | c++filt)
        stamp=$(stat -c '%y' "$path")
        printf 'linked_symbol\t%s\t%s\t%s/%s\t\t\t%s\tglobal\t%s\tmangled=%s;size=%s\tofficial archive %s\n' \
            "$layer" "$module" "$prefix" "$source" "$type" "$demangled" "$mangled" "${size:-0}" "$stamp" >> "$OUT"
    done
done

# C ABI surface is taken from the current source and the platform stub macros.
perl -ne '
    while (/\b((?:CJ_)?MCC_(?:New\w*|OnFinalizerCreated|Write\w*|Read\w*|Atomic\w*|InvokeGC\w*|GetRealHeapSize|GetAllocatedHeapSize|GetMaxHeapSize|DumpCJHeapData|GetGCCount|GetGCTimeUs|GetGCFreedSize|IsGCRunning|SetGCThreshold|AcquireRawData|ReleaseRawData|HandleSafepoint|CheckThreadLocalDataOffset)|(?:CJ_)?MRT_(?:DumpHeapSnapshot|ForceFullGC|FlushGCInfo|StopGCWork|GetSafepointProtectedPage|GetThreadLocalData|EnterSaferegion|LeaveSaferegion|ProcessFinalizers))\b/g) {
        print "$ARGV:$.:$1\n";
    }
' "$SRC/CompilerCalls.cpp" "$SRC/CompilerCalls.h" "$SRC/CommonAlias.h" "$SRC/MacAlias.h" \
  "$SRC/Cangjie.h" "$SRC/CangjieRuntimeApi.cpp" "$SRC/Mutator/Mutator.cpp" \
  "$SRC/Mutator/MutatorManager.cpp" "$SRC/Mutator/ThreadLocal.cpp" \
  "$SRC/Heap/Collector/CollectorResources.cpp" "$SRC/Heap/Collector/FinalizerProcessor.cpp" \
  | awk -F: '!seen[$3]++' | while IFS=: read -r file line symbol; do
      rel=${file#"$SRC/"}
      printf 'abi_symbol\tABI-boundary\tC-ABI\t%s\t%s\t\tfunction\tC ABI\t%s\tcanonical source occurrence\tcurrent oracle source\n' \
          "$rel" "$line" "$symbol" >> "$OUT"
  done

for stub in "$SRC"/arch/*/CalleeSavedStub.S; do
    rel=${stub#"$SRC/"}
    awk '/CalleeSavedRegistersStub(New)? MCC_/ {
        for (i = 1; i <= NF; i++)
            if ($i ~ /^(CJ_)?MCC_(New|InvokeGC|AcquireRawData|DumpCJHeapData)/) print NR ":" $i
    }' "$stub" | while IFS=: read -r line symbol; do
        printf 'abi_symbol\tLayer0-retained\tAllocationStub\t%s\t%s\t\tassembly-stub\tC ABI\t%s\tcallee-saved allocation/GC trampoline\tcurrent oracle source\n' \
            "$rel" "$line" "$symbol" >> "$OUT"
    done
done
for stub in "$SRC"/arch/*/HandleSafepointStub.S; do
    rel=${stub#"$SRC/"}
    awk '/^[[:space:]]*\.global[[:space:]]/ { print NR ":" $2 }' "$stub" | while IFS=: read -r line symbol; do
        printf 'abi_symbol\tLayer0-retained\tSafepointStub\t%s\t%s\t\tassembly-label\tplatform ABI\t%s\tsafepoint entry/unwind landmark\tcurrent oracle source\n' \
            "$rel" "$line" "$symbol" >> "$OUT"
    done
done

printf 'wrote %s rows to %s\n' "$(( $(wc -l < "$OUT") - 1 ))" "$OUT"
