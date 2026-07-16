# Runtime RegionList 移植报告

## 结论

`RegionList` 与 `RegionCache` 的 Linux release 生产布局和链表行为已经移植到
`src/rt.heap.allocator/RegionList.cj`。RegionInfo 节点、RegionList 本体和临时
merge cache 均由 AS0 native 内存承载；业务路径没有托管字段取址，也没有
AS1→AS0 转换。

`std::function<void(RegionInfo*)>` 不能直接改成 Cangjie 函数值：selfhost 的
`@NoHeapAlloc` 检查证明，即便传入顶层非捕获函数也会生成
`llvm.cj.malloc.object`。最终接口保留原生 `std::function` 对象为 opaque
`CPointer<Unit>`，由 `rt0/RegionListVisitor.cpp` 的单一 leaf bridge 调用。
这保留了 visitor 删除当前节点的行为，并避免 GC 分配。

## C++ 锚点与逐符号核对

事实源：

- `runtime/src/Heap/Allocator/RegionList.h:14-212`：RegionList 全部 release 成员。
- `RegionList.h:214-244`：RegionCache。
- `runtime/src/Heap/Allocator/RegionManager.cpp:155-175`：MergeRegionList。
- `RegionManager.cpp:177-204`：PrependRegion/PrependRegionLocked。
- `RegionManager.cpp:206-243`：DeleteRegionLocked。
- `RegionManager.cpp:474-477`：RemoveRegionLocked。
- `runtime/src/Heap/Allocator/RegionInfo.h:622,886-932`：allocated size 与
  prev/next/ghost 索引依赖闭包。

release 语义入口逐项核对为 **33/33**：

| C++ 入口 | Cangjie 入口/实现 | 锚点 |
|---|---|---|
| RegionList ctor/dtor | `RegionList.Construct/Destroy` | RegionList.h:17,169-174 |
| PrependRegion/Locked | 同名 pointer extension | RegionList.h:19-20; RegionManager.cpp:177-204 |
| MergeRegionList | 同名 pointer extension | RegionList.h:22; RegionManager.cpp:155-175 |
| DeleteRegion/TryDeleteRegion | 同名 pointer extension | RegionList.h:24-48 |
| DecCounts/IncCounts | 同名 pointer extension | RegionList.h:54-70 |
| GetHeadRegion/ClearList/GetTailRegion | 同名 pointer extension | RegionList.h:72-82 |
| TakeHeadRegion 两个重载 | 同名两个重载 | RegionList.h:84-101 |
| GetUnitCount/GetRegionCount/GetAllocatedSize | 同名 pointer extension | RegionList.h:103-113 |
| VisitAllRegions/VisitAllGhostRegions | opaque native visitor + leaf bridge | RegionList.h:115-132 |
| SetElementType/ClearTraceRegionFlag | 同名 pointer extension | RegionList.h:134-148 |
| GetListMutex | 返回 inline native mutex 地址 | RegionList.h:150 |
| MoveTo/CopyListTo | 同名 pointer extension | RegionList.h:152-166 |
| DeleteRegionLocked | 同名 pointer extension | RegionList.h:176; RegionManager.cpp:206-243 |
| AssignWith/CountAllocatedSize | 同名 private pointer extension | RegionList.h:178-196 |
| RegionCache ctor/dtor | `RegionCache.Construct/Destroy` | RegionList.h:214-216,242-244 |
| TryPrependRegion/Activate/Deactivate | 同名 pointer extension | RegionList.h:218-241 |
| RemoveRegionLocked | 同名 package function | RegionManager.cpp:474-477 |

`MRT_DEBUG` 的 `DumpRegionList/VerifyRegion` 不属于当前 release 产物；release
下 DLOG 与 MRT_ASSERT 的分支分别保持 no-op。常开的 CHECK、计数溢出和
RTLOG_FATAL 路径仍然终止。RegionList 源文件没有 OS 条件分支；本次执行平台
为 Linux x86_64。

## 布局对拍

C++ 原版实际布局：

```text
REGIONLIST_LAYOUT sizeof=80 align=8 mutex=0 regionCount=40 unitCount=48 head=56 tail=64 name=72 cache_size=88 cache_align=8 active=80
```

Cangjie `@C` IR/执行布局逐字段相同：RegionList 为
`{ i64, i64, i64, i64, i64, i64, i64, i8*, i8*, i8* }`，RegionCache 为
`{ RegionList, i1 }`，执行 `sizeOf` 分别为 80 和 88。

## 行为逐字节对拍

原版 C++ 动态库与 Cangjie 实现使用相同 88-byte native RegionInfo contract，
完整覆盖 empty/prepend/null prepend/失败与成功 TryDelete/take/merge/copy/
visitor/ghost visitor/cache activate/deactivate。原始结果：

```text
REGIONLIST_NATIVE_VISITOR_TRANSCRIPT_CMP rc=0
18 628 cpp_native_visitor.txt
06df3dbf88b55014befbc6db3852e33608e4072013dc94057f11f34778ed6c55  cpp_native_visitor.txt
06df3dbf88b55014befbc6db3852e33608e4072013dc94057f11f34778ed6c55  cj_native_visitor.txt
```

## 受限方言/地址空间验收

隔离 package 使用 production `RegionList.cj`、具体 native RegionInfo contract
和两个 `@NoHeapAlloc` root（普通链表操作 root、visitor root）编译。原始结果：

```text
REGIONLIST_VISITOR_NATIVE_NOHEAP rc=0 illegal_as1_to_as0=0 managed_function_alloc=0
```

RegionList 源中没有 `String` 值、动态 Array/ArrayList/HashMap、捕获闭包或 GC
分配。仅使用静态 VArray 字节串、CPointer、native malloc/free 和 native mutex。

## 构建验收

任务指定的 `cjpm build`：

```text
cjpm clean success
Warning: there is no '.cj' file in directory '/root/cj_build/cjcj_runtime_wt/rt_regionlist/src', and its subdirectories will not be scanned as source code
cjpm build success
REGIONLIST_CJPM_BUILD rc=0
```

Layer0 实际编译及符号：

```text
[100%] Built target cjcj_rt0
0000000000000000 T CJRT_RegionListInvokeVisitor
REGIONLIST_RT0_BUILD rc=0
```

本机不存在任务说明中的
`/root/cj_build/cangjie_compiler_selfhost/target/release/bin/cangjie_compiler::cjc`。
仓内 parity 脚本指定的现存 selfhost
`/root/cj_build/cjcj/target/release/bin/cjcj::cjc` 编译完整 owning package 时，
只命中 HEAD 已记录的 RegionInfo 前置错误，RegionList 新错误数为 0：

```text
error: member variable 'fieldVal' of struct 'BitField' with @C must be instantiated with CType
  ==> src/rt.heap.allocator/RegionInfo.cj:246:16
1 error generated, 1 error printed.
REGIONLIST_OWNING_SELFHOST rc=1 regionlist_errors=0
```

因此完整 owning-package selfhost 编译仍受既有 RegionInfo 泛型 `@C` 缺口阻挡；
本任务没有修改 RegionInfo 或制造业务 workaround。RegionList 自身通过隔离
selfhost 编译、NoHeapAlloc、地址空间、布局、行为和 rt0 链接验收。
