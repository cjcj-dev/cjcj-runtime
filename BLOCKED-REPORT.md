# BLOCKED — W5 selfhost shared-object compile-target gap

## Resolved prerequisite

The original `SELFHOST-CFUNC-EXPORT-MANGLING` blocker is fixed on selfhost
master `9d9e4360`.  The compiler was rebuilt from that commit and the existing
probe `test/compiler_gap/w5_cfunc_export.cj` now agrees with the nightly
compiler:

```text
00000000000001e0 T W5_CFuncExportProbe
SELF_C=1 REF_C=1 SELF_MANGLED=0
```

## Named gap

`SELFHOST-OBJ-COMPILE-TARGET-DROPPED`: the selfhost cjc accepts
`--compile-target dylib` at the driver level but does not forward it to the
frontend when `--output-type obj` is used.  The frontend therefore treats a
library package as an executable object and rejects it for not defining
`main`.

W1 mixed linking requires the W5 package object to be compiled for a shared
library.  A normal `staticlib` member is not a substitute: its package metadata
uses non-PIC `R_X86_64_PC32` relocations against `__CJMetadataStart`, and the
hybrid shared-object link rejects that object.

This gap is not listed in `CJCJ_RUNTIME_SPEC.md` §3.2.  Layer1 is specified as
having no compiler prerequisite, and the W1 injection gate requires a usable
package object.

## Minimal reproducer

Source: `test/compiler_gap/w5_cfunc_export.cj`

```sh
cjc test/compiler_gap/w5_cfunc_export.cj \
  --experimental --output-type obj --compile-target dylib -O2 \
  -o probe.o
```

With the required rebuilt selfhost compiler:

```text
SELF_OBJ_RC=1
error: 'main' is missing
 ==> test/compiler_gap/w5_cfunc_export.cj:1:1:
1 error generated, 1 error printed.
```

With the nightly compiler at the same toolchain version:

```text
REF_OBJ_RC=0
/tmp/w5_compile_target/ref/probe.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), not stripped
0000000000000000 T W5_CFuncExportProbe
```

For comparison, injecting the selfhost `staticlib` object into W1 reaches the
expected hard failure:

```text
relocation R_X86_64_PC32 against undefined symbol `__CJMetadataStart' can not be used when making a shared object
undefined reference to `_CGPatiiHv'
undefined reference to `_CGPatilHv'
```

The unchanged W1 foundation itself still passes its empty-object link and
complete export-set check:

```text
HYBRID LINK PASS output=/root/cj_build/cjcj_runtime_wt/w5/out/gate/hybrid/libcangjie-runtime.so exports=2692 runtime_objects=92 thread_objects=20 rt0_objects=13 injected=1 replaced=11
SYMCHECK PASS reference=2692 candidate=2692 missing=0 extra=0
EMPTY INJECT PASS objects=1 map_hits=22
DIFFTEST SKIP SKIP_DIFFTEST=1
```

This isolates the stop to producing a selfhost W5 shared-library object; it is
not a regression in the W1 relinker or symbol checker.

## Stop line

No `objcopy`, linker-defined fake metadata boundary, C/assembly trampoline, or
nightly-compiled W5 object was committed.  Any of those would bypass the
required selfhost package-object path.  The `rt.abi` implementation draft and
hybrid-linker experiment were removed after the gap was isolated.

W5 `MRT_DumpLog` implementation, official-runtime `objdump` parity, and the
W1 mixed-link symcheck remain blocked until
`SELFHOST-OBJ-COMPILE-TARGET-DROPPED` is fixed.
