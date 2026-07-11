# G1/G5 A4 前置门报告

## 范围与结论

本波只增加验证设施，不切换任何 `MCC_New*` 分配 ABI，也不修改 oracle。门由三层证据组成：

1. 运行 selfhost cjc 的 W4 注解正反例，确认 `@NoHeapAlloc` 静态调用闭包检查实际启用；
2. 从 Cangjie 源码生成标注根函数清单，对编译对象的反汇编和 relocation 扫描 `MCC_New*` 与 G5 TLS 引用；
3. 在标注根函数进入至返回的窗口内，用 GDB 断点分别计数 `malloc`、全部 30 个 `(CJ_)?MCC_New*` ABI 名和 `MRT_GetThreadLocalData`，同一探针分别加载 oracle 与混链产物。

设施首次运行通过。当前 G5 证据是 spec §3.2 允许的 `MRT_GetThreadLocalData` FFI 慢路径，不宣称已经具备尚未落地的 TLS 直读 intrinsic。`src/` 当前没有 Layer3 分配器实现，也没有生产 `@NoHeapAlloc` 根；本报告只证明 A4 切换前置门可运行，不授权现在切换 ABI。

## 重跑

```text
OUT=$PWD/out/a4-gate-first bash test/a4_gate.sh
```

默认输入：

- selfhost cjc：`/root/cj_build/cjcj/target/release/bin/cjcj::cjc`
- oracle：`/root/cj_build/cangjie_runtime/runtime/target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so`
- hybrid：`out/gate/hybrid/libcangjie-runtime.so`；不存在时脚本先以 `SKIP_DIFFTEST=1` 调用既有混链 gate 构建
- 标注探针：`test/a4_gate/noheap_tls_probe.cj`

`SELFHOST`、`CJC`、`CANGJIE_HOME`、`RUNTIME_ROOT`、`ORACLE`、`HYBRID` 和 `OUT` 均可由环境覆盖。生成的 `noheap-roots.tsv` 是后续 A4 审计所用的稳定清单格式：`source / line / function / link_symbol`。

## 首次运行事实源

```text
runtime branch base=7ab4d80
selfhost_cjc_commit=e53cb9be8ceaacb7957d39959d99339d9f9c698f
oracle_commit=f56e60bfb05121f138f39dec46d7e0b38eb3165a
oracle_sha256=efae8e8228389b957a423d75208cd905fff7279b1f12a5383491c14f39651702
hybrid_sha256=94ea05a13c87b16ca7ec02bbfa91841e9c10445e60e7a17ace6644a7b14f89d0
```

标注清单原文：

```text
ANNOTATION_INVENTORY roots=2 c_symbols=2
CJRT_G1StackOnlyProbe line=7 link_symbol=CJRT_G1StackOnlyProbe
CJRT_G5ThreadLocalProbe line=13 link_symbol=CJRT_G5ThreadLocalProbe
ANNOTATION_INVENTORY roots=0 c_symbols=0 output=out/a4-gate-first/production-noheap-roots.tsv
```

编译器 W4 门原文：

```text
W4ANNOT: PASS=11 FAIL=0
```

对象与 runtime 静态门原文：

```text
STATIC root=CJRT_G1StackOnlyProbe symbol=CJRT_G1StackOnlyProbe reachable_functions=1 managed_alloc_refs=0 tls_refs=0 status=PASS
STATIC root=CJRT_G5ThreadLocalProbe symbol=CJRT_G5ThreadLocalProbe reachable_functions=1 managed_alloc_refs=0 tls_refs=0 status=PASS
STATIC_SUMMARY roots=2 object_managed_alloc_refs=0 object_tls_refs=1 failures=0
RUNTIME oracle allocation_exports=30 tls_exports=1 tls_offset_check_exports=3 status=PASS
RUNTIME hybrid allocation_exports=30 tls_exports=1 tls_offset_check_exports=3 status=PASS
```

C ABI 包装器经 N2C/C2N 间接进入 Cangjie 函数体，所以逐根 `tls_refs` 为 0，而对象 relocation 的 `object_tls_refs=1` 是 `MRT_GetThreadLocalData` 的静态 G5 证据。G1 的闭包级结论由同一次编译中的 W4 checker 给出，对象扫描是独立的产物复核。

动态门原文（oracle 与 hybrid 各一次，计数完全一致）：

```text
stack_result=42 tls_nonnull=1
DYNAMIC_SUMMARY roots=2 malloc_hits=0 mcc_new_hits=0 tls_hits=21
stack_result=42 tls_nonnull=1
DYNAMIC_SUMMARY roots=2 malloc_hits=0 mcc_new_hits=0 tls_hits=21
A4 HARNESS PASS probe_annotations=2 production_annotations=0 compiler_w4=11/11 static_managed_refs=0 static_tls_refs=1 DYNAMIC_SUMMARY roots=2 malloc_hits=0 mcc_new_hits=0 tls_hits=21
```

`tls_hits` 大于 1 是 Cangjie/native 栈切换与包装路径的 TLS 读取；门只要求非零并要求 oracle/hybrid 完全相等。进程启动和 `main` 的分配不在根函数窗口内，不计入 `malloc_hits`/`mcc_new_hits`。

## A4 使用约束

真正切换分配 ABI 时，必须把待接管的每个 C ABI 根标为 `@NoHeapAlloc`，将实际 A4 对象纳入同样的清单/静态扫描，并由能覆盖每条慢路径的 driver 执行动态窗口计数。任一条件失败即禁止切换：W4 编译拒绝、清单缺根、对象出现 `(CJ_)?MCC_New*` 引用、G5 TLS 证据为零、运行窗口内 `malloc`/`MCC_New*` 非零，或 oracle/hybrid 计数不一致。
