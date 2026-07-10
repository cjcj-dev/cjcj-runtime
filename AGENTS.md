# cjcj_runtime 工程纪律（每任务必读）
本仓=用 Cangjie 重写 Cangjie runtime（参考 Go 自举模式）。权威设计=/root/cj_build/audit_persist/CJCJ_RUNTIME_SPEC.md（先读你任务对应节+§4 混链+§5 分层+§8 风险）。
1. **不是 1:1 忠实移植 C++ 语法，而是行为等价重写**：验收=逐字节/逐字段对拍（spec 各 W 任务的验收标准是硬门）。C ABI 符号签名必须与 C++ 版完全一致（照抄 Cangjie.h/CompilerCalls.h）。
2. **受限方言**（Layer1 起）：运行时代码不得依赖会触发 GC 分配的高层设施（String 拼接/Array 动态增长/闭包捕获堆分配），用 CPointer/VArray/LibC.malloc/@C struct；unsafe 块显式标注。禁 panic 式吞错，错误经返回码/RTLOG。
3. 参考实现只读：/root/cj_build/cangjie_runtime（C++ 原版）、/root/cj_build/cangjie_compiler_selfhost（selfhost cjc+能力先例）。绝不修改这两仓（W4 例外，它在 selfhost worktree 做）。
4. 编译器=selfhost cjc：/root/cj_build/cangjie_compiler_selfhost/target/release/bin/cangjie_compiler::cjc（CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029，LD_LIBRARY_PATH 带 third_party/llvm/lib+runtime lib）。
5. commit：单行 semantic 前缀（feat(rt.demangle): 等），作者 Zxilly <zxilly@outlook.com>，禁 AI 署名，正文注明对拍验收结果。
6. 撞 cjc 能力缺口（spec §3.2 之外的新缺口）→ BLOCKED-REPORT 记 named 缺口，不造 workaround。
7. 交付自检：对拍数字原文粘贴+git status 干净+commit sha。
