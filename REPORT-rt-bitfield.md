# REPORT: RegionInfo BitField 单态化

## 修复范围

上游 Cangjie 禁止 `@C struct` 带类型参数，因此将 C++ `RegionInfo.h:35-62`
的模板仅按 runtime 实际使用的两个实例单态化为：

- `BitFieldU8`：唯一字段 `fieldVal: UInt8`
- `BitFieldU16`：唯一字段 `fieldVal: UInt16`

`UnitMetadata` 字段、所有 `CPointer` 接收者、静态调用点，以及 RegionInfo
布局/行为探针均改用对应具体类型。未增加第三种实例或抽象层。

## C++ 模板与具体结构对表

| C++ 锚点 | C++ 语义/实例 | Cangjie 具体实现 | 对拍要点 |
|---|---|---|---|
| `/root/cj_build/cangjie_runtime/runtime/src/Heap/Allocator/RegionInfo.h:35-36` | `BitField` 模板定义 | `@C struct BitFieldU8`、`@C struct BitFieldU16` | 泛型 `@C` 完全消除，仅保留两个实际实例 |
| `RegionInfo.h:40-45` | acquire load，构造位掩码，返回掩码后的原值 | 两结构各自的 `GetAtomicValue` | 分别调用 `cj_atomic_u8_load` / `cj_atomic_u16_load`；掩码及返回顺序相同 |
| `RegionInfo.h:46-58` | 读取旧值，计算 changed/unchanged bits，strong CAS，失败重试 | 两结构各自的 `SetAtomicValue` | 分别调用 u8/u16 CAS；成功为 acq_rel、失败为 acquire；CAS 失败更新 expected 后继续循环 |
| `RegionInfo.h:61` | 模板字段 `T fieldVal` | `UInt8 fieldVal` / `UInt16 fieldVal` | `size/align/field offset` 分别为 `1/1/0`、`2/2/0` |
| `RegionInfo.h:1022-1028` | `BitField<uint8_t> unitRoleBitField` | `BitFieldU8 unitRoleBitField` | `UnitMetadata` 偏移保持 `76` |
| `RegionInfo.h:1030-1051` | `BitField<uint16_t> regionStateBitField` | `BitFieldU16 regionStateBitField` | `UnitMetadata` 偏移保持 `78` |
| `RegionInfo.h:759-797,1103-1139` | role/state 原子 setter 与 getter | 所有 RegionInfo/UnitInfo 调用点改用 U8/U16 具体接收者 | 位位置、位宽、入参转换均未改变 |

原子桥的内存序继续由 `rt0/os/Linux/Atomic.cpp:20-34` 保证：load 为
acquire，CAS 成功为 acq_rel、失败为 acquire，与 C++ 模板体一致。

## 验收

泛型扫描：

```text
$ rg -n 'BitField<(UInt8|UInt16|T)>|struct BitField<' src test --glob '*.cj' --glob '*.sh'
<empty; matches=0>
```

worktree 根目录构建：

```text
$ cjpm build
Warning: there is no '.cj' file in directory '/root/cj_build/cjcj_runtime_wt/rt_bitfield/src', and its subdirectories will not be scanned as source code
cjpm build success
```

因为根 `cjpm` 不扫描点号命名的包目录，另用可用 selfhost 编译器
`/root/cj_build/cjcj/target/release/bin/cjcj::cjc` 显式编译完整依赖链：

```text
rt.base -> rt.sync -> rt.heap.allocator
SELFHOST_PACKAGE_CHAIN PASS
```

完整 C++/Cangjie RegionInfo 门：

```text
REGIONINFO_DEFERRED_ABORT PASS rc=134 message=RegionInfo::MarkObject not yet ported (Collector-deferred)
REGIONINFO_LAYOUT sizeof=88 allocPtr=0 regionEnd=8 nextRegionIdx=16 prevRegionIdx=20 liveByteCount=24 rawPointerObjectCount=28 liveInfo=32 liveInfo0=40 regionEnd0=48 routeInfo=56 nextRegionIdx0=72 unitRoleBitField=76 regionStateBitField=78 routeState=80 rwLock=84
REGIONINFO_LAYOUT sizeof=88 allocPtr=0 regionEnd=8 nextRegionIdx=16 prevRegionIdx=20 liveByteCount=24 rawPointerObjectCount=28 liveInfo=32 liveInfo0=40 regionEnd0=48 routeInfo=56 nextRegionIdx0=72 unitRoleBitField=76 regionStateBitField=78 routeState=80 rwLock=84
REGIONINFO_PROBE PASS
REGIONINFO_LAYOUT ASSERT PASS REGIONINFO_LAYOUT sizeof=88 allocPtr=0 regionEnd=8 nextRegionIdx=16 prevRegionIdx=20 liveByteCount=24 rawPointerObjectCount=28 liveInfo=32 liveInfo0=40 regionEnd0=48 routeInfo=56 nextRegionIdx0=72 unitRoleBitField=76 regionStateBitField=78 routeState=80 rwLock=84
REGIONINFO_ABI bit8_size=1 bit8_align=1 bit8_fieldVal=0 bit8_value=0 bit16_size=2 bit16_align=2 bit16_fieldVal=0 bit16_value=0 rwlock_size=4 rwlock_align=4 rwlock_value=0 route_size=16 route_align=8 route_to1=0 route_used=8 route_to2=12 unitinfo_size=88 unitinfo_align=8 unitinfo_metadata=0 regioninfo_size=88 regioninfo_align=8 regioninfo_metadata=0
REGIONINFO_INIT_PARITY cases=3 fields=41 untouched=478 subordinate=1 cmp=PASS
REGIONINFO_NOHEAP roots=1 objects=19 final_bc=20 executables=1 mcc_new_refs=0 status=PASS
REGIONINFO_PLATFORM os=Linux executable=1 status=PASS
run_regioninfo_probe: PASS
```

最终静态检查：

```text
git diff --check: rc=0
```
