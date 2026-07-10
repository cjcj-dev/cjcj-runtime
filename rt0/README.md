# Layer0 frozen subset

This directory vendors the x86_64 Linux Layer0 sources from the read-only
`cangjie_runtime` oracle at commit
`f56e60bfb05121f138f39dec46d7e0b38eb3165a`.

`libcjcj_rt0.a` contains all ten architecture assembly files, Linux loader/path
code, the signal stack/trampoline support, and the header-only mmap-backed
`SafepointPageManager`. The CMake target intentionally still consumes common
ABI headers from `CANGJIE_RUNTIME_SOURCE`; those headers are not forked into
this repository and the oracle tree is never written.

Only these archive members are linked into `libcangjie-runtime.so`:

- the six runtime stubs plus `RestoreContextForEH.S`;
- `Loader.cpp`, `Path.cpp`, `SignalStack.cpp`, and `SignalUtils.cpp`;
- `CjNativeRuntimeStartAndEnd.S` for the dynamic runtime address bounds.

`SignalVectorCompat.cpp` preserves one weak `std::vector<SignalAction>` symbol
that the official build exposed through its older libstdc++ headers; newer
headers no longer emit that template spelling automatically.

`Cjstart.S` remains a program-start object and `Cjpgo.S` remains a PGO support
object, so neither is forced into the shared runtime image.
