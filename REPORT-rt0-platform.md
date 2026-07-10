# rt0 全平台 vendor 扩展报告

## 交付范围

- 起点：`lane/w1` 已成功 rebase 到 `master`（起点 `db77fa5`）。
- oracle：`/root/cj_build/cangjie_runtime`，固定提交
  `f56e60bfb05121f138f39dec46d7e0b38eb3165a`，全程只读。
- `rt0/arch` 已 vendor 官方全部 8 个目录，共 71 个汇编源文件。
- `rt0/os` 已 vendor Linux、Windows、Macos 与公共头，共 12 个文件。
- `rt0/signal` 的 5 个 oracle 公共源/头保持逐字节一致；
  `SignalVectorCompat.cpp` 是既有的本仓兼容文件，不计入 oracle 对拍。
- 原 x86_64 Linux 的 4 个漂移文件已恢复 oracle 原字节，包括行尾空格与
  EOF newline 状态。

## Vendor 字节门

逐文件 `cmp -s` 覆盖 `arch` 71、`os` 12、`Signal` 5，共 88 个 oracle 文件：

```text
VENDOR_BYTE_DIFF=0
```

## CMake 选择矩阵

`CJCJ_RT0_CONFIGURE_ONLY=ON` 只验证平台分支、文件存在性和生成阶段，不声称
完成交叉编译。实际选择输出如下：

```text
aarch64_ios: aarch64_ios system=Linux processor=aarch64 arch_sources=8
aarch64_linux: aarch64_linux system=Linux processor=aarch64 arch_sources=10
aarch64_macos: aarch64_macos system=Darwin processor=aarch64 arch_sources=8
arm_linux: arm_linux system=Linux processor=arm arch_sources=9
x86_64_ios: x86_64_ios system=Linux processor=x86_64 arch_sources=8
x86_64_linux: x86_64_linux system=Linux processor=x86_64 arch_sources=10
x86_64_macos: x86_64_macos system=Darwin processor=x86_64 arch_sources=8
x86_64_windows: x86_64_windows system=Windows processor=x86_64 arch_sources=10
ohos_1: aarch64_linux system=Linux processor=aarch64 arch_sources=10
ohos_2: x86_64_linux system=Linux processor=x86_64 arch_sources=10
ohos_3: arm_linux system=Linux processor=arm arch_sources=9
```

iOS 在 Linux 主机上直接指定 `-DCMAKE_SYSTEM_NAME=iOS` 时，CMake 在进入本仓
选择逻辑前终止：

```text
ios_sdk_probe: exit=1 requirement=iphoneos is not an iOS SDK
```

因此 iOS 两变体使用 oracle 同款 `IOS_FLAG` / `IOS_SIMULATOR_FLAG` 完成选择
干跑。真实 configure/build 需要 Apple SDK 以及 oracle 的
`ios_cangjie.cmake`、`ios_simulator_aarch64_cangjie.cmake` 或
`ios_simulator_x86_64_cangjie.cmake` toolchain。

## Linux x86_64 全量门

本机 Release archive 实际构建成功；完整 `test/gate.sh` 原文数字：

```text
HYBRID LINK PASS exports=2692 runtime_objects=92 thread_objects=20 rt0_objects=13 injected=3 replaced=11 localized=2
SYMCHECK PASS reference=2692 candidate=2692 missing=0 extra=0
DEMANGLE_PARITY_OBJECTS=209
DEMANGLE_PARITY_SYMBOLS=33015
DEMANGLE_PARITY_ORACLE_BYTES=5795324
DEMANGLE_PARITY_CANDIDATE_BYTES=5795324
DEMANGLE_PARITY_BYTE_DIFF=0
DEMANGLE_PARITY_SHA256=c51cec36aecbbaa60bb8e0673f1594335f55c608bfb96b4b712ef7a39dc59589
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
W2 GATE PASS rt0=1 inject=3 symcheck=2692/2692 demangle=byte-identical difftest=114/114
```

任务说明中的
`/root/cj_build/cangjie_compiler_selfhost/target/release/bin/cangjie_compiler::cjc`
在当前环境不存在；全量门使用改名后现存的
`/root/cj_build/cjcj/target/release/bin/cjcj::cjc`。
