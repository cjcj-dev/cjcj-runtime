# Layer0 frozen platform surface

This directory vendors the Layer0 platform sources byte-for-byte from the
read-only `cangjie_runtime` oracle at commit
`f56e60bfb05121f138f39dec46d7e0b38eb3165a`.

The frozen architecture surface is the complete official eight-variant set:

- `aarch64_ios`, `aarch64_linux`, `aarch64_macos`, and `arm_linux`;
- `x86_64_ios`, `x86_64_linux`, `x86_64_macos`, and `x86_64_windows`.

The common `Signal` sources and the complete sibling `os` platform surface
(`Linux`, `Windows`, `Macos`, plus `Loader.h` and `Path.h`) are also vendored.
Oracle whitespace, final-newline state, and line endings are preserved. The
only non-oracle source in those groups is `SignalVectorCompat.cpp`, retained to
preserve a weak `std::vector<SignalAction>` symbol emitted by older libstdc++
headers.

`libcjcj_rt0.a` selects the official architecture directory for
`CMAKE_SYSTEM_NAME`, processor, `OHOS_FLAG` 1/2/3, MinGW, and Apple targets.
macOS and iOS use the oracle's Linux Loader/Path implementation; Windows uses
its Loader/Path/UnwindWin/WinModuleManager implementation. `Cjstart.S`,
`Cjpgo.S`, platform Section sources, and other archive members remain available
for their official start-object roles; the hybrid linker still extracts only
its explicit shared-runtime member allowlist.

## Verification matrix

| Variant | Verification in this worktree |
| --- | --- |
| `x86_64_linux` | Release archive build, hybrid link, symcheck, byte parity, and difftest 114/114 |
| `aarch64_linux`, `arm_linux` | byte-identical vendor plus configure-only source selection |
| `x86_64_macos`, `aarch64_macos` | byte-identical vendor plus configure-only source selection |
| `x86_64_windows` | byte-identical vendor plus configure-only source selection |
| `x86_64_ios`, `aarch64_ios` | byte-identical vendor plus `IOS_FLAG`/simulator configure-only source selection |

Configure-only mode validates the selected source set without claiming a cross
compile:

```sh
cmake -S . -B out/config-aarch64-linux \
  -DCJCJ_RT0_CONFIGURE_ONLY=ON \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64
```

Native `-DCMAKE_SYSTEM_NAME=iOS` configuration requires an Apple host SDK and
an iOS toolchain. The oracle supplies the required target setup in
`build/cmake/toolchain/ios_cangjie.cmake` and the two
`ios_simulator_*_cangjie.cmake` files; this Linux host therefore validates iOS
selection through the matching official flags only.

The target continues to consume common ABI headers from
`CANGJIE_RUNTIME_SOURCE`; those headers are not forked here and the oracle tree
is never written.
