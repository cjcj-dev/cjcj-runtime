# cjcj_runtime

W1 establishes the frozen x86_64 Linux Layer0 archive and mixed-linking gate.
W2 adds the restricted-dialect Cangjie demangler and its three `rt.abi` C
entry points.

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

Run the full gate, including empty-package injection, demangler byte parity
over every selfhost object, ABI parity, and the 114-case differential suite:

```sh
REPO=/root/cj_build/cjcj bash test/gate.sh
```

`link_hybrid.py --inject module.o` adds PIC Cangjie objects and localizes only
colliding definitions in official archive members. This symbol-granular
interposition preserves unrelated definitions that share the same object (for
example `RunCJTaskSignal`). Its generated version script is an allowlist from
the official shared object, so private Cangjie package symbols cannot expand
the public ABI.
