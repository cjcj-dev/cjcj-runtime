# cjcj_runtime 工程纪律（每任务必读）
本仓=用 Cangjie 重写 Cangjie runtime（参考 Go 自举模式）。权威设计=/root/cj_build/audit_persist/CJCJ_RUNTIME_SPEC.md（先读你任务对应节+§4 混链+§5 分层+§8 风险）。
1. **不是 1:1 忠实移植 C++ 语法，而是行为等价重写**：验收=逐字节/逐字段对拍（spec 各 W 任务的验收标准是硬门）。C ABI 符号签名必须与 C++ 版完全一致（照抄 Cangjie.h/CompilerCalls.h）。**禁发明**：C++ 没有的分配/分支/抽象一律不加；不确定的忠实判断宁可 BLOCKED-REPORT 也不发明。
2. **受限方言**（Layer1 起）：运行时代码不得依赖会触发 GC 分配的高层设施（String 拼接/Array 动态增长/闭包捕获堆分配），用 CPointer/VArray/LibC 原语/@C struct；unsafe 块显式标注。禁 panic 式吞错，错误经返回码/RTLOG。
3. 参考实现只读：/root/cj_build/cangjie_runtime（C++ 原版）、/root/cj_build/cjcj（selfhost 编译器仓）。绝不修改这两仓。
4. 编译器=selfhost cjc：/root/cj_build/cjcj/target/release/bin/cjcj::cjc（CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029，LD_LIBRARY_PATH 带 third_party/llvm/lib+runtime lib，cjHeapSize=24GB）。
5. commit：单行 semantic 前缀（feat(rt.heap): 等），作者 Zxilly <zxilly@outlook.com>，禁 AI 署名/Co-Authored-By，正文注明 C++ file:line 锚点+对拍验收结果原文。
6. 撞 cjc 能力缺口 → BLOCKED-REPORT 记 named 缺口，不造 workaround。**BLOCKED=合格交付，发明=不合格**。
7. **先 commit 再 verify**：verify/门脚本可能 reset 工作树，任何改动先 commit 落分支再跑验证。
8. **报告不入 git**：REPORT/STATE/BLOCKED 类 md 一律 untracked，绝不 git add。
9. **noheap 门=全闭包**：从根+静态初始化遍历 pre-opt BC 调用图，扫全部可达定义的 final BC+目标码，断言 reachable_defs == scanned_defs，fail closed。孤立包局部图不算证据。
10. **平台面完整**：每个 C++ @When/#ifdef 分支逐条对齐；Linux 之外不可执行的分支以显式 per-target 债务记入 commit 正文，静默省略=不合格。
11. 交付自检：对拍数字原文粘贴+git status 干净（除 untracked 报告）+commit sha。
