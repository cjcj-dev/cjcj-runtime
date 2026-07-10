# BLOCKED — W5 selfhost CFunc export ABI gap

## Named gap

`SELFHOST-CFUNC-EXPORT-MANGLING`: the required selfhost cjc does not lower a
top-level `@C public func` to an unmangled C ABI symbol. It emits a normal
Cangjie-mangled symbol instead.

This gap is not listed in `CJCJ_RUNTIME_SPEC.md` §3.2. That section treats
`CFunc`/`@C` export support as an existing capability, while W5 requires the
exact C symbol and signature:

```c
extern "C" void MRT_DumpLog(const char* message);
```

Without a working CFunc export, W5 cannot satisfy the C ABI hard gate, cannot
replace the `MRT_DumpLog` symbol cluster in the hybrid link, and cannot run the
required mixed-runtime gate.

## Minimal reproducer

Source: `test/compiler_gap/w5_cfunc_export.cj`

Compiler required by `AGENTS.md`:

```text
/root/cj_build/cangjie_compiler_selfhost/target/release/bin/cangjie_compiler::cjc
```

Compile it as a static library, then inspect its global definitions. The
selfhost result is:

```text
00000000000001e0 T _CN34cjcj_runtime:w5_cfunc_export_probe19W5_CFuncExportProbeHi
```

The exact required symbol `W5_CFuncExportProbe` is absent.

Control compilation with the toolchain cjc at the same nightly version emits:

```text
00000000000001e0 T W5_CFuncExportProbe
```

This confirms that the source and annotation are valid and isolates the fault
to the selfhost compiler path.

## Stop line

No linker alias, C shim, assembly trampoline, or `objcopy --redefine-sym`
workaround was added. Such a workaround would bypass the mandated CFunc ABI
implementation and violate the task instruction for new compiler gaps.

W5 implementation, byte-for-byte log parity, and hybrid difftest 114 remain
blocked until `SELFHOST-CFUNC-EXPORT-MANGLING` is fixed. The W1 hybrid-link
dependency is also not present on `lane/w5`, but it is not the primary blocker.
