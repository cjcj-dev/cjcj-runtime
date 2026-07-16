# BLOCKED-REPORT — AllocUtil + RouteInfo + SlotList

## 结论

三个目标叶子文件已经按原 C++ 头文件移植，并由 selfhost cjc 独立编译、原头行为对拍通过。完整
`rt.heap.allocator` 包的编译门被任务开始前已经存在的 `RegionInfo.cj:245-246` 泛型 `@C`
结构阻塞；删除本次三个新文件后仍以相同诊断复现，因此不是本次改动引入。

命名缺口：`G10-C-STRUCT-GENERIC-TYPEPARAM`。

- 官方 cjc 取证：`@C struct BitField<T> where T <: CType` 报
  `struct with @C cannot have type parameters` 和
  `member variable ... must be instantiated with CType`。
- selfhost cjc 取证：同一最小探针报
  `member variable 'fieldVal' ... must be instantiated with CType`。
- 生产触发点：`src/rt.heap.allocator/RegionInfo.cj:245-246`，不属于本任务三个头文件。
- 未制作绕过：没有改写、删除或降级 `RegionInfo` 的 `@C BitField<T>`；应由其所有者按 spec §8 R1
  采用具体布局或 C accessor 薄层解决。

仓根 `cjpm build` 的原文为：

```text
Warning: there is no '.cj' file in directory '.../src', and its subdirectories will not be scanned as source code
cjpm build success
```

该命令没有扫描点号命名的包目录，不能作为三个新文件已编译的证据。实际编译使用工程既有 gate 的
`cjc --package src/rt.heap.allocator` 路径；完整包在上述既有缺口处失败。

## C++ ↔ Cangjie 对表

| C++ 锚点 | C++ 符号/行为 | Cangjie 锚点 | 等价映射 |
|---|---|---|---|
| `AllocUtil.h:15` | `ALLOC_UTIL_PAGE_SIZE = 4096` | `AllocUtil.cj:3-4` | `UInt32` 常量 4096 |
| `AllocUtil.h:16-17` | `ALLOCUTIL_PAGE_RND_UP(x)` | `AllocUtil.cj:6-11` | 先加 4095，再与 `-4096`；`-4096 == ~(4096-1)` 的无符号逐位等价式 |
| `AllocUtil.h:19-23` | Win64 `VirtualFree(address, 0, MEM_RELEASE)`，失败 fatal | `AllocUtil.cj:13-24,34-42` | `@When[os == "Windows"]`，参数与失败条件逐项相同 |
| `AllocUtil.h:24-28` | 非 Win64 `munmap(address, size)`，非 EOK fatal | `AllocUtil.cj:26-32,44-51` | `@When[os != "Windows"]` 覆盖 Linux/Apple，失败条件逐项相同 |
| `AllocUtil.h:31-35` | `AllocUtilRndDown<T>` | `AllocUtil.cj:53-57` | 仓内实际实例 `T=size_t` 映射为 `UIntNative` |
| `AllocUtil.h:37-41` | `AllocUtilRndUp<T>` | `AllocUtil.cj:59-63` | 同一 `x+n-1` 后调用 RndDown |
| `RouteInfo.h:10-11` | 空 `MapleRuntime` namespace | `RouteInfo.cj:1-4` | 空包文件；没有发明结构或符号 |
| `SlotList.h:14-17` | `ObjectSlot { StateWord; ObjectSlot* next; }` | `SlotList.cj:25-36` | `StateWord.h:179` 保证完整字为 8 字节；因 `rt.common -> rt.heap.allocator` 包依赖，使用不读取位的 `UInt64` 原位覆盖；`next` 紧随其后 |
| `SlotList.h:21-27` | `PushFront` | `SlotList.cj:48-58` | 先清尾部，再写旧 head，最后更新 head |
| `SlotList.h:29-38` | `PopFront(size)` | `SlotList.cj:60-73` | 空链/尺寸不符返回 0；成功摘头、清 next、返回原地址 |
| `SlotList.h:40` | `Clear` | `SlotList.cj:75-79` | head 置空 |
| `SlotList.h:42-50` | `ClearExtraContent` | `SlotList.cj:81-95` | `GetSize-sizeof(ObjectSlot)`；正数时同参数调用 `memset_s`；失败按 `CHECK_E` 的 ERROR 级别记录 |
| `SlotList.h:53` | `head = nullptr` | `SlotList.cj:41-46` | `@C SlotList` 单指针字段，构造置空 |

`BaseObject::GetSize()` 尚未移植；`SlotList.cj:3-5` 保留原实现
`Common/BaseObject.cpp:139-150` 的 Itanium/MinGW C++ ABI 入口。Linux、Apple clang 和 Win64 MinGW
均使用该 ABI；没有复制 ObjectModel 布局。`CHECK_E` 的非 fatal 语义通过原
`Logger::FormatLog(RTLOG_ERROR, true, ...)` 保留。

三个头文件都没有 C ABI 导出符号，因此无 `Cangjie.h/CompilerCalls.h` 导出签名项。

## 平台分支核对

| 平台 | 原 C++ | Cangjie | 状态 |
|---|---|---|---|
| Linux | `munmap(address, sizeInBytes) != EOK` | `os != Windows` 同参数、返回值非 0 | 对齐 |
| Apple (macOS/iOS) | 同非 Win64 分支 | `os != Windows` 同参数、返回值非 0 | 对齐 |
| Win64 | `VirtualFree(address, 0, MEM_RELEASE) == FALSE` | `os == Windows`，size 固定 0，flag `0x8000`，返回 0 失败 | 对齐 |

## 对拍与编译原文

命令：

```text
test/parity/heap/run_allocutil_slotlist_probe.sh
```

原 C++ 头与 Cangjie 叶子输出逐行 `diff -u`，结果：

```text
ALLOCUTIL page=4096 page_up_0=0 page_up_1=4096 page_up_4096=4096 rnd_down_4097=4096 rnd_up_4097=8192
LAYOUT object_size=16 object_align=8 list_size=8 list_align=8
PUSH_A next_null=true tail_zero=true
PUSH_B next_a=true tail_zero=true
POP_WRONG zero=true
POP_B match=true next_null=true
POP_A match=true next_null=true
POP_EMPTY zero=true
CLEAR empty=true
ALLOCUTIL_SLOTLIST_PARITY lines=9 mismatches=0 status=PASS
ALLOCUTIL_SLOTLIST_COMPILER path=/root/cj_build/cjcj/target/release/bin/cjcj::cjc status=PASS
```

该 gate 直接包含只读原头 `AllocUtil.h`、`SlotList.h`，并让两边的
`BaseObject::GetSize()` 测试桩读取相同原位 size；覆盖 0/1/页边界舍入、布局、两节点 LIFO、错误
size 不摘链、摘链后 next 清空、对象 16 字节之后清零和 `Clear`。Cangjie 侧编译的正是三个生产
文件副本，`@NoHeapAlloc` 校验在同次 selfhost 编译中生效。

完整包（含/不含本次文件均相同）的阻塞原文：

```text
error: member variable 'fieldVal' of struct 'BitField' with @C must be instantiated with CType
  ==> src/rt.heap.allocator/RegionInfo.cj:246:16
```
