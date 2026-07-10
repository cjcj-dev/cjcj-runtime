# cjcj_runtime

W1 establishes the frozen x86_64 Linux Layer0 archive and the mixed-linking
gate used by later Cangjie runtime modules.

Build and relink without an injected module:

```sh
env -u LD_LIBRARY_PATH cmake -S . -B out/build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_ASM_COMPILER=clang
env -u LD_LIBRARY_PATH cmake --build out/build --target cjcj_rt0 --parallel
python3 build/link_hybrid.py
python3 build/symcheck.py \
  /root/cj_build/cangjie_runtime/runtime/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so \
  out/hybrid/libcangjie-runtime.so
```

Run the full gate, including selfhost-cjc empty-package injection and the 114
case differential suite:

```sh
REPO=/root/cj_build/cangjie_compiler_selfhost bash test/gate.sh
```

`link_hybrid.py --inject module.o` adds PIC Cangjie objects and resolves strong
symbol collisions by removing fully replaced members or transforming only the
colliding definitions in mixed members. Its generated version script is an
allowlist from the official shared object, so private Cangjie package symbols
cannot expand the public ABI.

W5 adds the `rt.abi` CFunc wrapper for `MRT_DumpLog`. The mixed link preserves
the byte-identical C++ Base implementation as an internal callee while the
public C ABI symbol is supplied by Cangjie. Run its export, symbol-parity, and
114-case mixed-runtime gate with:

```sh
REPO=/root/cj_build/cjcj bash test/w5_gate.sh
```
