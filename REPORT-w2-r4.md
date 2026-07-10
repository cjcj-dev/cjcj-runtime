# W2 r4 — VArray struct store 解锁与 Demangler 接管复验

## 基线与编译器事实源

- runtime 分支在复验前 rebase 到 `master=4385939dd673c04ee1ef3361aed84fd8a350444f`。
- selfhost cjc 主仓：`74d4fe37507022550934ab515bd0b50c5e99bdf4`，包含
  `90d73105`（reference store lowering）与 `0fcd3fd6`（VArray store route）。
- 主仓已有二进制早于 HEAD，因此在本 worktree 的 ignored `out/` 下创建
  `74d4fe37` 只读共享副本，构建 release cjc；未修改主仓工作树。
- 编译器：`out/cjcj-master-74d4/target/release/bin/cjcj::cjc`。
- 编译器 SHA-256：
  `a3776cab5e4f77c4ce04bf884e6a05008f051ed6bb530f87da2e4677cbc69cd4`。
- 工具链：`nightly-1.2.0-alpha.20260619020029`，目标
  `x86_64-unknown-linux-gnu`。

## G11 探针结论

用全新 O0/O2 目录执行
`test/compiler_gap/w2_varray_struct_store.cj`，通过实验性 obj 输出直接要求 LLVM
产出并验证最终 ELF relocatable object：

```text
G11-PROBE compiler=selfhost revision=74d4fe37507022550934ab515bd0b50c5e99bdf4 O0_exit=0 O0_bytes=31128 O2_exit=0 O2_bytes=13000
out/w2-r4-probe-latest/o0/probe.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), not stripped
out/w2-r4-probe-latest/o2/probe.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), not stripped
```

对象 SHA-256：

```text
dd89e6f4b30badfa91d75490e30805b9834877a950c37bb863d1c1a3aff6790b  O0/probe.o
a9f88a41ae03db078edf25b498f456f14c4f286c8ba822bf5dd097a0358be25f  O2/probe.o
```

结论：原 G11 `IRBuilder2.CallArrayIntrinsicSet` 值 struct typed store 缺口已解除；
O0/O2 均不再出现 `Explicit load/store type does not match pointee type`。无需
`CPointer` 手写存储或字段拆分 workaround。

## 推进面与最终产物证据

以同一 selfhost cjc 重新编译 `rt.demangle` 和 `rt.abi`，并按 W1/W5 的统一混链
机制注入最终 `libcangjie-runtime.so`。受限方言检查：

```text
RESTRICTED DIALECT PASS managed_edges=0
```

最终产物：`out/w2-r4-gate-latest/hybrid/libcangjie-runtime.so`，SHA-256：
`9a065b56c29e4c71f49dd06302cf2d83377eba8b1f942c36bd0855f634e2063f`。

混链和导出集：

```text
HYBRID LINK PASS output=/root/cj_build/cjcj_runtime_wt/w2/out/w2-r4-gate-latest/hybrid/libcangjie-runtime.so exports=2692 runtime_objects=92 thread_objects=20 rt0_objects=13 injected=3 replaced=11 localized=2
SYMCHECK PASS reference=2692 candidate=2692 missing=0 extra=0
INJECT PASS objects=3
```

最终 link map 中三个 W2 C ABI 入口均来自注入的 `rt.abi.o`：

```text
0x0000000000488900 CJ_MRT_Demangle
0x0000000000488990 CJ_MRT_DemangleHandle
0x0000000000488a20 MRT_DemangleHandle
```

官方 runtime 动态 ABI 只包含 `CJ_MRT_DemangleHandle@@CANGJIE`，所以最终产物保持
该符号为动态导出，另外两个兼容入口为本地定义；`symcheck` 证明没有扩大或缩小官方
导出集。

## 对拍结果

以 `/root/cj_build/cjcj` 下全部 selfhost object 的 `_CN` 定义符号为语料：

```text
DEMANGLE_PARITY_PREFIX=_CN
DEMANGLE_PARITY_OBJECTS=209
DEMANGLE_PARITY_SYMBOLS=33015
DEMANGLE_PARITY_ORACLE_BYTES=5795324
DEMANGLE_PARITY_CANDIDATE_BYTES=5795324
DEMANGLE_PARITY_BYTE_DIFF=0
DEMANGLE_PARITY_SHA256=c51cec36aecbbaa60bb8e0673f1594335f55c608bfb96b4b712ef7a39dc59589
```

同一最终 hybrid so 经 `LD_PRELOAD` 运行全量差分套件。fresh clone 首轮 `-j8`
有两个样例恰好触发 180s 编译超时（112/114，0 mismatch）；不放宽超时、不删样例，
降低资源竞争为 `-j4` 后全量重跑：

```text
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
```

结论：VArray struct store 解锁后，W2 被阻断的受限方言编译、三入口符号接管、
最终 ABI 导出对拍、33,015 符号逐字节对拍及 114 项混链差分面全部通过。
