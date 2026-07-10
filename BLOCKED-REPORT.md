# BLOCKED-REPORT: W2 Demangler

## 状态

`BLOCKED`。W2 尚未产出可提交的 `rt.demangle` / `rt.abi`，对拍和 W1 混链均未执行。

按 `AGENTS.md` 第 6 条停止：受限方言的原生字符串底座遇到 spec §3.2 未登记的
selfhost cjc 缺口；没有用改源码排版、拆分表达式或参考 cjc 产物绕过。

## Named gap

**G10 — Faithful AST2CHIR 的局部声明缓存/父类型解析对源码位置不稳定。**

合法的多文件包包含 `@C struct`、`CPointer<T>`、同包函数调用以及较大的纯整数
`match` 表时，selfhost cjc 在 AST→CHIR 阶段异常退出。观察到两种同源症状：

```text
IllegalStateException: faithful AST2CHIR localCache miss: value
  at cangjie_compiler::chir::FaithfulLocalValueMap::Get(...)
  at packages/chir/src/Translator.cj:402
  ...
  at cangjie_compiler::chir::Translator::TranslateMemberFuncCall(...)
  at packages/chir/src/Translator.cj:6601
```

以及：

```text
NoneValueException
  at cangjie_compiler::chir::Translator::GetExactParentType(...)
  at packages/chir/src/Translator.cj:1859
  at cangjie_compiler::chir::Translator::TranslateRawArrayByCollection(...)
  at packages/chir/src/Translator.cj:5691
```

最小化过程中，保持声明和语义不变、只把 `RtArenaCreate` 前移一行即可令同一探针
从失败变为通过；移回原行再次失败。该现象指向 `FaithfulLocalAstDeclHash` /
`FaithfulLocalValueMap` 或其作用域 mark/restore 的源位置相关身份问题，而非 Cangjie
源代码类型错误。这里是根据栈和位置敏感行为作出的定位推断，最终根因仍需在 cjc
侧确认。

## 对照结果

同一份探针在全新的隔离目录中执行，避免 `.cached` 干扰：

```text
reference cjc: PASS (exit=0)
selfhost cjc:  FAIL (exit=1, stack as above)
```

两者报告相同语言版本：

```text
Cangjie Compiler: 1.2.0-alpha.20260619020029 (cjnative)
Target: x86_64-unknown-linux-gnu
```

编译器事实源：

- selfhost commit: `e358136d17ac60487333be7a7c8fbbcc38a76371`
- selfhost binary SHA-256: `9ea33877e7c48825bef46d1fc589fdb7f255903a1f6c9a21a4e876f25b96f17e`
- reference `/root/.cjv/bin/cjc` SHA-256: `5ef08b567f31ee624222bfd7a2570b36c30706bebab3de89c355064dfc2d7d9d`

## 对 W2 的阻塞

Demangler 不能使用 `String`、`ArrayList` 或异常来承载解析结果；原生字节串需要
`CPointer` / `@C struct`，其所有 Cangjie 关键路径都必须由指定 selfhost cjc 编译。
当前异常发生在这个底座进入 CHIR 时，因而无法继续到 ABI 导出、selfhost `.o`
语料逐字节对拍或混链 gate。参考 cjc 能通过只能证明源码合法，不能替代任务指定
的 selfhost 编译器验收。

## 解除条件

在 selfhost cjc 修复并重建后，至少需要先证明以下探针稳定：

1. 相同源码在不同文件顺序、空行位置和全新构建目录中均可编译；
2. `@C struct`/`CPointer<T>` 返回值和成员调用进入 CHIR 不再出现上述两种异常；
3. 较大的整数 `match` 表与这些低层类型同包时仍可编译；
4. 连续两次构建不依赖删除或复用 `.cached` 才成功。

解除后从 W2 源码实现继续；当前逐字节对拍数字为 `PENDING-G10`，混链为
`PENDING-G10`（并仍依赖 W1）。
