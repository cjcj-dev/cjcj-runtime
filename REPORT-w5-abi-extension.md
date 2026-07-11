# W5 continuation — Base/log/Env ABI takeover

## Scope and boundary

This continuation rebased `lane/w5` onto local `master=7ab4d808` and surveyed
the dynamic symbols owned by `Base/{CString,LogFile,TimeUtils,MemUtils}` and
`LogManager`. Allocation, Heap, Collector, barrier, Mutator and GC-control
symbols were excluded. `MemorySet` and `MemoryCopy` were also left untouched
because allocator/GC paths consume them.

The accepted unit remains the W5 pattern: a restricted-dialect `@C` function
owns the exact existing ELF symbol and forwards to the byte-identical C++ body,
renamed to a private `CJRT_Base*` alias by the hybrid linker.

## Accepted clusters

The Env commit `6e918ef7` takes three `Base/CString.h` entries:

- `_ZN12MapleRuntime7CString15ParseNumFromEnvERKS0_` —
  `static int CString::ParseNumFromEnv(const CString&)`.
- `_ZN12MapleRuntime7CString12IsPosDecimalERKS0_` —
  `static bool CString::IsPosDecimal(const CString&)`.
- `_ZN12MapleRuntime7CString8IsNumberERKS0_` —
  `static bool CString::IsNumber(const CString&)`.

The log commit `8933bae5` takes three configuration leaves from
`Base/LogFile.h`:

- `_ZN12MapleRuntime7LogFile13CloseLogFilesEv` —
  `static void LogFile::CloseLogFiles()`.
- `_ZN12MapleRuntime7LogFile8SetFlagsEv` —
  `static void LogFile::SetFlags()`.
- `_ZN12MapleRuntime7LogFile14SetFlagWithEnvEPKcNS_7LogTypeE` —
  `static void LogFile::SetFlagWithEnv(const char*, LogType)`.

Together with the existing `MRT_DumpLog`, `rt.abi` now owns seven W5 symbols.
The C++ implementations remain the behavior oracle; fixed-input probes call
the official and hybrid entries after runtime initialization.

## Initialization-window stop line

The survey did not equate “exported” with “safe to interpose.” Three attempted
cuts were rejected after real mixed-runtime startup/teardown probes:

- `TimeUtil::{NanoSeconds,MicroSeconds,MilliSeconds,SleepForNano}` preserved
  433 bytes with `BYTE_DIFF=0`, but startup aborted at the Cangjie N2C entry
  with `Check failed: runtime != nullptr`. Time helpers are used by static GC
  timestamps and other pre-runtime initialization paths.
- `CString::ParsePosNumFromEnv` preserved its body, but a gdb trace showed
  `SemanticVersionInfo::SemanticVersionInfo` calling it from
  `MRT_LibraryOnLoad` before `Runtime::Current()` exists.
- `LogFile::Fini` preserved its body, but teardown entered the Cangjie wrapper
  after safepoint/unwind state was dismantled and faulted in
  `CJ_MCC_HandleSafepoint`.

Source-call timing also excludes `LogFile::Init`, `InitLogLevel`, the early
scheduler Env parsers (`ParseSizeFromEnv`, `ParseTimeFromEnv`,
`ParsePosDecFromEnv`, `ParseValidFromEnv`, `ParseFlagFromEnv`, `IsPosNumber`),
and aggregate-return helpers such as `GetTimestamp`/`Pretty*`. No C shim,
annotation bypass, internal-call rewrite or aggregate-ABI guess was added.

## Compiler and G11 probe

Selfhost compiler revision:
`e53cb9be8ceaacb7957d39959d99339d9f9c698f`; binary SHA-256:
`a2b9f0a4ab53694e772ada3156bd6b8b41695db3e0c91dff688b78bf8edf628d`.
Fresh O0/O2 object builds of `w2_varray_struct_store.cj` produced:

```text
G11-PROBE O0_exit=0 O0_bytes=26736 O2_exit=0 O2_bytes=9792
```

This covers the `@C CStringLayout` fixed-input probe's VArray struct stores;
both outputs are ELF x86-64 relocatable objects.

## Final parity gates

The final hybrid SHA-256 is
`766d45948301be0f28b2384172eb0856fa9b80f284f7f123c3e8178a82333998`.
Raw gate results:

```text
CFUNC PROBE PASS so_c=1 obj_c=1 mangled=0
RT.ABI OBJECT PASS c=1 mangled=0 base_forward=1 env_forward=3 log_forward=3
HYBRID LINK PASS output=/root/cj_build/cjcj_runtime_wt/w5/out/w5-final-gate/hybrid/libcangjie-runtime.so exports=2692 runtime_objects=92 thread_objects=20 rt0_objects=13 injected=2 replaced=11 localized=3
SYMCHECK PASS reference=2692 candidate=2692 missing=0 extra=0
BASE FORWARD PARITY PASS text_bytes=32 byte_diff=0
ENV FORWARD PARITY PASS symbols=3 text_bytes=543 byte_diff=0
LOG FORWARD PARITY PASS symbols=3 text_bytes=339 byte_diff=0
ENV CALL PARITY PASS fixed_cases=5 official=0 hybrid=0
LOG CALL PARITY PASS leaves=3 official=0 hybrid=0
CFUNC CALL PASS log_lines=1 payload=W5_CFUNC_EXPORT
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
```

The first 16-way differential run had one compile timeout and zero mismatches
(`113/114`). Re-running the unchanged hybrid with the repository's established
resource-stable `-j4` setting passed all 114 cases; `test/w5_gate.sh` now uses
four jobs by default without changing the 180-second per-case timeout.
