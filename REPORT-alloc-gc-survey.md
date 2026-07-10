# Runtime allocator/GC official surface survey

Date: 2026-07-11  
Oracle: `/root/cj_build/cangjie_runtime` at `f56e60bfb05121f138f39dec46d7e0b38eb3165a`  
Spec: `CJCJ_RUNTIME_SPEC.md` sections 4, 5, 7 and 8  
Machine-readable inventory: `/root/cj_build/reports/RT_ALLOC_GC_SURVEY.tsv`

## Scope and method

This is a zero-build source survey. The implementation scope is every `.h` and
`.cpp` under `runtime/src/Common`, `runtime/src/Heap` and `runtime/src/Mutator`,
plus `HeapManager.{h,cpp,inline.h}`. Shared ABI files (`CompilerCalls`,
`Cangjie.h`, `CangjieRuntimeApi.cpp`, `CommonAlias.h`, `MacAlias.h`) and every
platform `CalleeSavedStub.S`/`HandleSafepointStub.S` are boundary rows, not
charged to implementation LOC.

LOC is physical `wc -l`. Named class/struct/enum declarations are extracted
from current source. Linkable C++ symbols come from the oracle's existing
RelWithDebInfo static archives with `nm -A -g --defined-only`; this avoids an
oracle build, but those archives are dated 2026-06-16. The only later scoped
source change is `2bbd308` (MutatorManager writer preference), so source type,
file and ABI rows are authoritative while archive symbol rows are explicitly
snapshot evidence. The TSV retains duplicate weak/template emissions by object
and also carries mangled names, demangled signatures and object ownership.

## Measured surface

The core is 101 files and 20,249 lines, exactly matching the spec's three
directory totals. `HeapManager` adds 3 facade files/88 lines. There are 208
named type declaration rows after excluding local `struct T variable` uses.

| Layer/module | Files | LOC | Named types (definitions/forwards) | Linked rows / unique mangled names |
|---|---:|---:|---:|---:|
| Layer3 `Common` | 26 | 3,361 | 76 (52/24) | 39 / 37 |
| Layer3 `Heap/Allocator` | 19 | 5,747 | 36 (33/3) | 157 / 144 |
| **Layer3 subtotal** | **45** | **9,108** | **112 (85/27)** | **196 / 178** |
| Layer3+4 `Heap` facade | 2 | 511 | 7 (3/4) | included below | included below |
| Layer4 `Heap/core` | 3 | 567 | 6 (5/1) | 93 / 93 (includes facade archive) |
| Layer4 `Heap/Barrier` | 3 | 400 | 3 (2/1) | 28 / 28 |
| Layer4 `Heap/Collector` | 24 | 3,929 | 45 (40/5) | 358 / 284 |
| Layer4 `Heap/WCollector` | 14 | 2,758 | 11 (11/0) | 223 / 198 |
| Layer4 `Mutator` excluding safepoint page | 9 | 2,918 | 22 (20/2) | 144 / 131 |
| **Layer4 subtotal excluding shared Heap facade** | **53** | **10,572** | **87 (78/9)** | **846 / 683 (including shared Heap archive)** |
| Layer0 `SafepointPageManager.h` | 1 | 58 | 1 (1/0) | header-only |
| `HeapManager` facade | 3 | 88 | 1 (1/0) | in top-level runtime archive |

Archive uniqueness in the table is per archive; the TSV is the canonical row
set. The boundary inventory adds 6 shared ABI files (4,494 physical lines) and
16 platform assembly files (3,582 lines), but neither number is allocator/GC
implementation size. Current-source ABI extraction finds 75 direct C names,
30 distinct allocation/GC trampoline names across platform
`CalleeSavedStub.S`, and 6 distinct safepoint entry/unwind labels. The TSV has
one row per platform occurrence.

Complete type names and all linkable signatures are in the TSV. The ownership
anchors are:

- Common/native: `NativeAllocator`, `PagePool`, `PageCache`, `CentralCache`,
  `ThreadCache`, `PageAllocator`, `AggregateAllocator`, `FreeList`, `Span`.
- Allocator: `Allocator`, `AllocBuffer`, `AllocBufferManager`, `RegionInfo`,
  `RegionList`, `RegionCache`, `RegionManager`, `RegionSpace`, `CartesianTree`,
  `FreeRegionManager`, `LocalDeque`, `SlotList`, `MemMap`.
- Collector: `Collector`, `CollectorProxy`, `CollectorResources`,
  `TracingCollector`, `CopyCollector`, `FinalizerProcessor`, `TaskQueue`,
  `ForwardDataManager`, `LiveInfo`, `GCInfos`, `GCStats`, `GCRequest`.
- WCollector/barriers: `WCollector`, `ForwardTable`, `Barrier`, `IdleBarrier`,
  `EnumBarrier`, `TraceBarrier`, `PostTraceBarrier`, `PreforwardBarrier`,
  `ForwardBarrier`.
- Mutator/safepoint: `Mutator`, `MutatorManager`, `ThreadLocal`, `SatbBuffer`,
  `WeakRefBuffer`, `SafepointPageManager`, `ScopedStopTheWorld`,
  `ScopedLightSync`, `ScopedSTWLock`.

## Dependency graph

```text
Layer0: os/mmap+mprotect + arch/CalleeSavedStub + arch/HandleSafepointStub
   |                         |                         |
   v                         v                         v
Common native allocator --> Heap/Allocator <------ Mutator TLS + AllocBuffer
   |                         |  ^                    |  |
   |                         |  | shared RegionInfo  |  +--> SATB/weak buffers
   v                         v  |                    v
BaseObject/StateWord ---> Heap facade <-------- Safepoint/STW manager <--> CJThread
                              |                         |
                              v                         |
                     Collector/TracingCollector <-------+
                              |  ^
                              v  | phase/barrier switch
                  CopyCollector/WCollector <--> six barriers
                              |
                              v
              StackMap + UnwindStack + ObjectModel + finalizers

CompilerCalls/CommonAlias/CalleeSavedStub --> MCC_New*/MCC_Write*/MCC_Read*
CangjieRuntimeApi/HeapManager -------------> ForceFullGC/heap statistics
```

This is not a strict DAG. The hard cycles are source-visible:

- `RegionInfo`/`RegionSpace` are owned by Allocator but consumed and mutated by
  Collector, WCollector, barriers and Mutator. This is spec risk R1.
- Mutator contains per-thread `AllocBuffer` and SATB state; Allocator and GC
  therefore both call back into Mutator.
- Collector stops/resumes Mutators and reaches CJThread scheduling, while thread
  creation registers Mutators. This is the Layer2/Layer4 STW cycle (R4).
- Barrier dispatch reads the active Collector, while phase collectors install
  barrier implementations. Barrier takeover cannot be treated as independent
  leaf functions despite the six implementation files.
- TracingCollector consumes compiler StackMap data and UnwindStack/ObjectModel
  readers; W3 currently provides a parity decoder but has not interposed it.

## External symbol boundary

The allocation ABI begins at `MCC_NewObject`, `MCC_NewWeakRefObject`,
`MCC_NewPinnedObject`, `MCC_NewFinalizer`, `MCC_NewArray{,8,16,32,64}`,
`MCC_NewObjArray`, `MCC_NewGenericObject`, `MCC_NewArrayGeneric` and
`MCC_NewAndInitEnumTupleObject`. On Linux/Windows their `CJ_MCC_*` entries are
callee-saved assembly trampolines, not plain C aliases. These stubs must remain
Layer0 even after the slow paths switch to Cangjie.

The barrier ABI is `MCC_WriteRefField`, `MCC_WriteStructField`,
`MCC_WriteStaticRef`, `MCC_WriteStaticStruct`, the four atomic reference calls,
and `CJ_MCC_Read*`/`CJ_MCC_WriteGeneric*`. LLVM owns inline fast-path insertion;
runtime owns these slow-path signatures and semantics. `CommonAlias.h` and
`MacAlias.h` make the platform alias spelling part of the contract.

The GC/control ABI includes `MCC_InvokeGCImpl`, heap size/stat counters,
`MCC_SetGCThreshold`, `MRT_StopGCWork`, `MRT_ProcessFinalizers`,
`MRT_FlushGCInfo`, `CJ_MRT_ForceFullGC` and `CJ_MRT_DumpHeapSnapshot`.
Safepoint/TLS includes `CJ_MCC_HandleSafepoint`, `HandleSafepoint{,ForArm}`,
`MRT_GetSafepointProtectedPage`, `MRT_GetThreadLocalData`,
`MRT_EnterSaferegion`, `MRT_LeaveSaferegion`, and the unwind landmark labels.

## W1-W5 boundary

| Existing wave | Current ownership | Allocator/GC consequence |
|---|---|---|
| W1 rt0 | All official arch files, os/signal, copied `SafepointPageManager.h`, hybrid link/symcheck | Already owns allocation/safepoint trampolines and page mapping as retained Layer0. Do not duplicate them in Layer3/4. The copied header is byte-identical (58 lines) to oracle. |
| W2 demangle | `CJ_MRT_Demangle*` interposition | No direct dependency; validates the same hybrid symbol-removal mechanism. |
| W3 StackMap | Decoder and parity harness, not interposed | TracingCollector remains on the C++ StackMap reader until its root-scan wave. Its decoded structures are the required handoff contract. |
| W4 annotations | Compiler worktree task, absent from this runtime branch | G1 `NoHeapAlloc` is a hard Layer3 gate; G2 recursive no-write-barrier and G4 system stack are hard Layer4 gates. No runtime workaround should be invented. |
| W5 Base/log/Env | `MRT_DumpLog` hybrid takeover | RTLOG can be consumed by later ports, but current branch has no allocator/GC symbol takeover. Logging on no-allocation/no-safepoint paths still needs closure checking. |

No W1-W5 runtime object currently replaces a `Common`, `Heap`, `Mutator` or
`HeapManager` implementation symbol. W1 is the only ownership overlap and is
deliberate Layer0 retention.

## Recommended takeover waves

1. **A0 contract/layout gate.** Freeze the 75 direct C ABI names plus platform
   trampoline manifest; add `sizeof/alignof/offsetof` parity for `RegionInfo`,
   `UnitMetadata`, atomics/bitfields, `AllocBuffer`, `ThreadLocalData` and
   `BaseObject`. Require G1/G5 before switching allocation. Trigger R1 stop-loss
   if accessor coverage would exceed 30%.
2. **A1 native allocator.** Port `MemCommon`, `PagePool`, `PageCache`,
   `CentralCache`, `ThreadCache`, `NativeAllocator`, `PageAllocator` and
   `AggregateAllocator`. It must use mmap/native memory only and initialize
   before Heap. Keep every `MCC_New*` routed to C++.
3. **A2 region data plane.** Port `RegionInfo`, `RegionList`, `RouteInfo`,
   `SlotList`, `LocalDeque`, `AllocBuffer` and `AllocBufferManager`; land layout
   parity before behavior. This is the last safe point to choose accessor shim
   versus paired Layer3+4 switch.
4. **A3 region allocation policy.** Port `MemMap`, `CartesianTree`,
   `FreeRegionManager`, `RegionManager`, `RegionSpace`, `Allocator`, then Heap
   allocation facade. Run old Collector against new layouts only if A0 proves
   exact coexistence.
5. **A4 allocation ABI switch.** Replace slow paths behind `MCC_New*` as one
   symbol cluster, retaining Layer0 callee-saved stubs. Parity gates are bytes,
   object headers, region accounting, heap statistics and allocation pressure,
   not merely successful allocation.
6. **G0 mutator substrate.** After G1/G2/G4, port `ThreadLocal`, `SatbBuffer`,
   `WeakRefBuffer`, `MarkWorkStack` and non-page portions of Mutator/Manager.
   Keep page mmap/mprotect and assembly safepoint entry in Layer0.
7. **G1 phase/barrier cluster.** Port Barrier plus all six WCollector barriers
   together with `MCC_Write*`, atomic and `CJ_MCC_Read*` slow paths. Parallel
   implementation is possible, but interposition is one phase-consistent switch.
8. **G2 tracing/control plane.** Port `GcRequest`, `GcStats`, `GCInfos`,
   `TaskQueue`, `CollectorResources`, `GcThreadPool`, Collector/Proxy and
   TracingCollector. Interpose W3 StackMap decoding at this wave and verify root
   slots field-for-field.
9. **G3 copying/finalization.** Port `LiveInfo`, `ForwardDataManager`,
   CopyCollector, `ForwardTable`, WCollector and FinalizerProcessor; then switch
   force-GC/finalizer/control ABI as one collector build option. Gate large
   graphs, weak refs, cycles, finalizers, FullGC, difftest 114 and selfhost cjc.

The safest scheduling unit is therefore not “one class”: native allocation can
advance incrementally, but `RegionInfo` is a layout gate, allocation entry is a
single ABI cluster, barriers are a phase cluster, and copying GC/finalization is
an end-to-end collector cluster.

## Reproduction

```sh
tools/survey_alloc_gc.sh \
  /root/cj_build/cangjie_runtime \
  /root/cj_build/reports/RT_ALLOC_GC_SURVEY.tsv
```

The script reads the oracle and existing archives only. It does not configure,
compile, link or modify the oracle.
