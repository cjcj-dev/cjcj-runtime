# REPORT — fix_rt_cstring_r2

作者：Zxilly <zxilly@outlook.com>  
日期：2026-07-17  
语义 HEAD：`a8becb7aa580228852693616e0e06be63ff2d21c`

## 结论

按用户 0717 裁决，以“可达子集移植 + 排除项具名记账”完成 CString。本轮没有移植空壳，也没有让 `FormatString` 或 `Split` 进入目标日志闭包。

生产实现位于 `src/rt.cstring/CString.cj`。采用独立 `rt.cstring` 包，是为了避免遮蔽 `rt.base` 已有代码中表示 C ABI 的内建 `std.core.CString`；类名与全部成员名仍逐字符保持 C++ 名称。

## 用户裁决

0717 用户令允许 CString 成为 no-partial-facility 的特例：只移植目标日志链实际可达的成员，并把语言边界排除项写入 FEATURE_DEBT 与源码标记。两项排除仅为：

| 排除成员 | C++ 锚 | 债键 | reopen |
|---|---|---|---|
| `CString::FormatString(const char*, ...)` | `Base/CString.cpp:356-369` | `CSTRING_VARIADIC_FORMAT` | C 侧包普通函数 foreign 桥 |
| `CString::Split(CString&, char)` | `Base/CString.cpp:339-352` | `CSTRING_SPLIT_VECTOR` | 容器映射裁决 |

## 可达闭包机械扫描

根链逐调用点如下：

| 调用点 | C++ file:line | 后继 |
|---|---|---|
| `RegionList::DumpRegionList` 首条日志 | `Heap/Allocator/RegionManager.cpp:246-248` | `DLOG(REGION, ...)` |
| `RegionList::DumpRegionList` 循环日志 | `Heap/Allocator/RegionManager.cpp:249-254` | `DLOG(REGION, ...)` |
| `DLOG` debug 展开 | `Base/LogFile.h:199-203` | `VLOG` |
| `VLOG` 非 OHOS 展开 | `Base/LogFile.h:192-197` | `LogFile::LogIsEnabled`、`WriteLog` |
| `VLOG` OHOS 展开 | `Base/LogFile.h:185-191` | REPORT 走 `LOG`，其余走 `LogIsEnabled`、`WriteLog` |
| `LogFile::LogIsEnabled` | `Base/LogFile.h:229-237` | 读取日志开关 |
| `WriteLog` | `Base/LogFile.cpp:189-195` | `WriteLogImpl` |
| `WriteLogImpl` | `Base/LogFile.cpp:133-187` | `TimeUtil::GetTimestamp().Str()`；OHOS 另有 `CString(getenv).Str()` |
| `TimeUtil::GetTimestamp` | `Base/TimeUtils.cpp:68-90` | `CString(const char*)` |
| `LogFile` 静态日志级别 | `Base/LogFile.cpp:38` | `InitLogLevel()` |
| `InitLogLevel` | `Base/LogFile.cpp:271-305` | 构造、`Str`、`RemoveBlankSpace`、`Length`、`Str` |
| `RemoveBlankSpace` 内部 | `Base/CString.cpp:301-316` | `Str`、`CString(const char*)` |

排除项零调用扫描原命令：

```text
rg -n "FormatString\\(|\\.Split\\(|CString::Split|CString::FormatString" \
  runtime/src/Heap/Allocator/RegionManager.cpp \
  runtime/src/Base/LogFile.cpp runtime/src/Base/LogFile.h
RG_EXIT=1
```

`rg` 无正文输出且退出码为 1，故 `FormatString`/`Split` 不在目标闭包，用户裁决前提成立。

## 依赖闭包预扫

已有实体：

| 依赖 | C++ 锚 | selfhost 对应 |
|---|---|---|
| `malloc/free` | `Base/CString.cpp:34,159-165` | C ABI foreign 声明 |
| `strlen` | `Base/CString.cpp:30` | C ABI foreign 声明 |
| `memcpy_s` / `EOK == 0` | `Base/CString.cpp:36-38` | C ABI foreign 声明，返回值与 0 比较 |
| fatal 分支 | `Base/Print.h:151-162`; `Base/Log.cpp:417-419` | 已有 `rt.base.LOG(RTLOG_FATAL, ...)`，最终走 `RtFatal` |
| Cangjie finalizer 语法 | C++ `CString::~CString` 对应对象清理 | `~init()`，包内已有相同语法先例 |

零匹配依赖：无。没有撞到需要另开依赖 lane 的 named 设施或系统根。

## 移植成员表

| Cangjie 成员 | C++ 锚 | 语义对位 |
|---|---|---|
| `CString.init(CPointer<UInt8>)` | `Base/CString.cpp:27-42` | null 保持空指针；非 null 取 `strlen`，容量按 2 倍增长，`malloc`，非空复制，写终止零 |
| `CString.~init()` | `Base/CString.cpp:159-165` | 仅非 null 时 `free`，随后清空指针；构造者分配、同一对象析构释放 |
| `CString.Length` | `Base/CString.cpp:240` | 返回 `length` |
| `CString.Str` | `Base/CString.cpp:242` | 返回原生字符指针，可为 null |
| `CString.RemoveBlankSpace` | `Base/CString.cpp:301-316` | 先复制输入，再原地压缩所有 ASCII 空格，补终止零并更新长度，不修改源对象 |

源码排除标记在 `CString.cj:81-82`，未定义 `FormatString`/`Split`，因此没有 throw stub 或伪实现。

## 所有权与最终二进制证据

从语义 HEAD 重建命令：

```text
/root/cj_build/cjcj/target/release/bin/cjcj::cjc \
  --package src/rt.cstring --output-type=staticlib \
  --int-overflow wrapping --import-path "$TMP" --output-dir "$TMP" \
  --save-temps "$TMP/temps" -o librt.cstring.a
```

原始产物绑定：

```text
SEMANTIC_HEAD=a8becb7aa580228852693616e0e06be63ff2d21c
CSTRING_ARCHIVE_SIZE=35348
077146ee3b70ccc7770d0f7cc3d557c3d741ee8564ea4e25e2b546f6132da8a4  librt.cstring.a
FINAL_PACKAGE_BUILD_RC=0
```

`nm -C librt.cstring.a` 的关键原始行：

```text
0000000000000704 T _CN10rt.cstring7CString5~initHv
00000000000001e4 T _CN10rt.cstring7CString6<init>HPh
0000000000000484 T _CN10rt.cstring7CString16RemoveBlankSpaceHv
00000000000008e0 T _CN10rt.cstring7CString3StrHv
0000000000000920 T _CN10rt.cstring7CString6LengthHv
                 U free
                 U malloc
```

`llvm-objdump -dr` 把分配/释放绑定到具体成员：

```text
00000000000001e4 <_CN10rt.cstring7CString6<init>HPh>:
00000000000002d6: R_X86_64_PLT32 malloc-0x4
0000000000000704 <_CN10rt.cstring7CString5~initHv>:
000000000000076f: R_X86_64_PLT32 free-0x4
```

## 全分支覆盖

- `CString(const char*)`：全部 5 个 branch/loop 已覆盖：null 判断、容量增长循环、malloc 失败、空串判断、memcpy 失败。计数含 `PRINT_FATAL_IF` 宏展开。
- `CString::~CString`：全部 1 个 branch 已覆盖：非 null 才释放。
- `Length`、`Str`：各 0 个 branch。
- `RemoveBlankSpace`：全部 3 个 branch/loop 已覆盖：空串 early return、遍历循环、非空格复制判断。

因此已覆盖所移植五个 C++ 成员的全部 9 个 branch/loop；没有静默删去成员内部 case、early-return 或错误分支。

## 平台分支审计

原命令：

```text
rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" \
  Base/CString.cpp Base/CString.h Base/LogFile.cpp Base/LogFile.h \
  Base/TimeUtils.cpp Heap/Allocator/RegionManager.cpp
```

与 CString 子集直接相关的结果是：

```text
Base/CString.cpp:325:#ifdef __OHOS__
Base/TimeUtils.cpp:78:#ifdef _WIN64
Base/LogFile.h:185:#if defined (__OHOS__)
Base/LogFile.h:231:#if (defined(__OHOS__) && (__OHOS__ == 1))
Base/LogFile.cpp:156:#if defined(__OHOS__) && (__OHOS__ == 1)
```

`CString.cpp:325` 仅包围闭包外 `ReplaceAll`；本轮五个成员体本身没有平台条件。`TimeUtils`、`VLOG`、`WriteLogImpl` 的平台分支用于证明闭包，未在本 CString lane 重写。

## 最小探针

命令：

```text
bash test/parity/base/run_cstring_probe.sh
```

原始输出：

```text
CSTRING_CTOR PASS
CSTRING_LENGTH PASS
CSTRING_STR PASS
CSTRING_REMOVE_BLANK_SPACE PASS
CSTRING_NULL_CTOR PASS
CSTRING_PROBE PASS members=4 branches=nonempty,null,spaces
run_cstring_probe: PASS
```

探针验证非空构造、null 构造、长度、原始字符指针与终止零、去空格结果和源对象不变。析构所有权另由最终 archive 的 `~init → free` 重定位机械证明。

## 既有 runtime 回归门

W2 主门命令：

```text
REPO=/root/cj_build/cjcj DIFFTEST_JOBS=8 bash test/gate.sh
```

关键原始输出：

```text
RESTRICTED DIALECT PASS managed_edges=0
RESTRICTED DIALECT PASS rt.abi_managed_edges=0
SYMCHECK PASS reference=2692 candidate=2692 missing=0 extra=0
DEMANGLE_PARITY_BYTE_DIFF=0
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
W2 GATE PASS rt0=1 inject=3 symcheck=2692/2692 demangle=byte-identical difftest=114/114
```

W5 CString/LogFile ABI 门命令：

```text
REPO=/root/cj_build/cjcj bash test/w5_gate.sh
```

关键原始输出：

```text
CFUNC PROBE PASS so_c=1 obj_c=1 mangled=0
SYMCHECK PASS reference=2692 candidate=2692 missing=0 extra=0
ENV FORWARD PARITY PASS symbols=3 text_bytes=543 byte_diff=0
LOG FORWARD PARITY PASS symbols=3 text_bytes=339 byte_diff=0
ENV CALL PARITY PASS fixed_cases=5 official=0 hybrid=0
LOG CALL PARITY PASS leaves=3 official=0 hybrid=0
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
W5 GATE PASS cfunc=1 symcheck=2692/2692 base_text=32 difftest=114/114
```

验证前后根分区均为 `672G` 可用；W2/W5 输出共 63M，批量临时探针由 runner trap 清理，根目录生成的临时 `.bc` 已删除。

## FEATURE_DEBT 具名记账

全局总账已写：

```text
/root/cj_build/audit_persist/FEATURE_DEBT.md:23 CSTRING_VARIADIC_FORMAT
/root/cj_build/audit_persist/FEATURE_DEBT.md:24 CSTRING_SPLIT_VECTOR
SHA256=4475154d7df2610063cae25868295aadfb7950220029a983500155bfcd66e614
```

该全局目录不属于 Git 仓库，因此以绝对路径、行号和 SHA-256 机械绑定。

## 提交存在性

```text
7eba518 feat(rt.base): port reachable CString subset
be68a52 test(rt.base): probe reachable CString members
1dc9e35 test(rt.base): disambiguate CString probe type
a8becb7 test(rt.base): link CString probe atomic bridge
```

## 必要声明

1. 无任何 grep 不到 C++ 出处的新生产符号；`CString`、`Length`、`Str`、`RemoveBlankSpace`、构造与析构均有上表 C++ 锚。
2. 未改业务源码绕过、未加 band-aid 吞 bug。
3. 本轮未撞到系统根或缺失 named 依赖；没有自行造替代设施。
4. 除用户明确裁决的闭包外成员外，所移植成员内部无静默省略；`FormatString`/`Split` 已用债键和源码标记明示排除。

===END===
