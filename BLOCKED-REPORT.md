# BLOCKED-REPORT: W2 Demangler resume

## 状态

`BLOCKED`。G10 已按原报告的四项解除条件复测通过，但恢复 `rt.demangle`
后命中另一个 spec §3.2 未登记的 selfhost codegen 缺口。按 `AGENTS.md` 第 6
条停止；没有把固定值槽改写成手工字段或 `CPointer` 存储来规避编译器错误。

当前没有可验收的 `rt.demangle` / `rt.abi` 对象，因此官方 runtime 逐字节对拍与
W1 混链 gate 未执行。

## G10 解除复测

编译器事实源：

- source commit at rebuild: `ebc8527199a9f11cf43f639c1198c6dac535668d`
  （模块重命名改动随后提交为 `18366cc3`，二进制内容未变）
- selfhost binary: `/root/cj_build/cjcj/target/release/bin/cjcj::cjc`
- selfhost binary SHA-256:
  `277367aeb3685799f323ce9def70c85a83e93432bffbc3f62f614cba8b9fc361`
- toolchain: `nightly-1.2.0-alpha.20260619020029`

官方 `test/g10_probe/run_matrix.sh` 在每次运行都创建全新目录：

```text
G10-PROBE variant=arena_first run=1 exit=0 bytes=152794
G10-PROBE variant=arena_first run=2 exit=0 bytes=152794
G10-PROBE variant=literal_first run=1 exit=0 bytes=152794
G10-PROBE variant=literal_first run=2 exit=0 bytes=152794
G10-PROBE variant=literals_first run=1 exit=0 bytes=152810
G10-PROBE variant=literals_first run=2 exit=0 bytes=152810
```

另以同一份 `@C struct` / `CPointer<T>` / 大整数 `match` 包，交换三个文件的
字典序并插入空行；每个目录原地连续构建两次，不删除 `.cached`：

```text
G10-RESUME layout=raw_first run=1 exit=0 bytes=152818 cached=yes
G10-RESUME layout=raw_first run=2 exit=0 bytes=152818 cached=yes
G10-RESUME layout=literal_first run=1 exit=0 bytes=152818 cached=yes
G10-RESUME layout=literal_first run=2 exit=0 bytes=152818 cached=yes
G10-RESUME layout=probe_first run=1 exit=0 bytes=152818 cached=yes
G10-RESUME layout=probe_first run=2 exit=0 bytes=152818 cached=yes
```

结论：G10 的文件顺序、空行位置、全新目录、低层类型、大 `match` 表和缓存独立性
六个维度均稳定，原阻塞已解除。

## Named gap

**G11 — `IRBuilder2.CallArrayIntrinsicSet` 缺少值 struct 的 typed store / memcpy
分流，生成 pointer-pointee 类型不一致的 LLVM bitcode。**

受限 Demangler 用 `VArray<RtString, $16>` 作为固定参数槽，避免 `Array` 动态增长和
GC 分配。`RtString` 是只含裸指针和整数的 `@C struct`。最小探针位于
`test/compiler_gap/w2_varray_struct_store.cj`：

```text
G11-PROBE compiler=reference exit=0
G11-PROBE compiler=selfhost exit=1
error: Explicit load/store type does not match pointee type of pointer operand
```

完整恢复源码也给出相同对照：

```text
reference cjc: exit=0 archive_bytes=439270
selfhost cjc O0: exit=1 Explicit load/store type does not match pointee type
selfhost cjc O2: exit=1 Explicit load/store type does not match pointee type
```

该错误发生在 selfhost 已完成 AST→CHIR 后、toolchain `opt` 读取 selfhost 生成的
bitcode 时；不是 Cangjie 源码类型错误。最小探针由参考 cjc 编译通过。

## 根因边界与解除条件

selfhost 发射入口是：

```text
packages/codegen/src/IRBuilder.cj:3346 CallArrayIntrinsicSet
```

C++ 事实源 `CJNativeIntrinsicsCall.cpp:250` 对无引用 struct 走 `CreateMemCpy`，而
selfhost 当前会把 struct 地址作为值交给 typed raw store。忠实补齐该函数的分流还
依赖 selfhost 尚缺的 C++ API：

```text
IRBuilder2.GetSize_32(Type): LLVMValueRef
IRBuilder2.GetSize_64(Type): LLVMValueRef
```

C++ 声明在 `CodeGen/IRBuilder.h:403-404`，实现位于
`CJNativeIRBuilder.cpp:1847-1873`。这与编译器审计中的 O2 typed-load/store 债是
同一根因族；W2 不修改编译器仓，也不能在 runtime 源码中造替代路径。

解除条件：上述两个 size API 与 `CallArrayIntrinsicSet` 的 struct-without-ref memcpy
路径忠实移植后，最小探针必须在 O0/O2 均通过 LLVM verifier；随后重新构建 selfhost
cjc，再恢复 W2 的逐字节对拍和混链 gate。

当前验收数字：

```text
G10 unlock: 12/12 PASS
G11 reference/selfhost: 1/0 PASS
demangle byte parity: PENDING-G11
hybrid difftest: PENDING-G11
```
