#!/usr/bin/env python3
"""Relink libcangjie-runtime.so from official archives plus replacement objects."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RUNTIME_ROOT = Path("/root/cj_build/cangjie_runtime/runtime")
DEFAULT_TOOLCHAIN = Path("/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029")
ARCHIVE_SUBDIR = Path("target/common/linux_release_x86_64/lib/linux_x86_64_cjnative")
SO_SUBDIR = Path("target/common/linux_release_x86_64/runtime/lib/linux_x86_64_cjnative")
TOOLCHAIN_RUNTIME_SUBDIR = Path("runtime/lib/linux_x86_64_cjnative")
TOOLCHAIN_STATIC_SUBDIR = Path("lib/linux_x86_64_cjnative")

RT0_SHARED_MEMBERS = (
    "C2NStub.S.o",
    "CalleeSavedStub.S.o",
    "CjNativeRuntimeStartAndEnd.S.o",
    "ExclusiveScope.S.o",
    "HandleSafepointStub.S.o",
    "Loader.cpp.o",
    "N2CStub.S.o",
    "Path.cpp.o",
    "RestoreContextForEH.S.o",
    "SignalStack.cpp.o",
    "SignalUtils.cpp.o",
    "SignalVectorCompat.cpp.o",
    "StackGrowStub.S.o",
)
RT0_REPLACED_RUNTIME_MEMBERS = frozenset(RT0_SHARED_MEMBERS) - {
    "CjNativeRuntimeStartAndEnd.S.o",
    "SignalVectorCompat.cpp.o",
}
STRONG_NM_TYPES = frozenset("ABCDGIRST")
VERSION_SYMBOL_RE = re.compile(r"^(?P<name>[A-Za-z_.$][A-Za-z0-9_.$]*)(?:@@(?P<version>[A-Za-z0-9_.$]+))?$")


class HybridLinkError(RuntimeError):
    pass


def run(command: list[str], *, cwd: Path | None = None, capture: bool = False) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            check=True,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
        )
    except OSError as error:
        raise HybridLinkError(f"cannot execute {command[0]}: {error}") from error
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or "").strip()
        suffix = f": {detail}" if detail else ""
        raise HybridLinkError(f"command failed ({error.returncode}): {' '.join(command)}{suffix}") from error
    return result.stdout if capture else ""


def require_file(path: Path, label: str) -> Path:
    path = path.expanduser().resolve()
    if not path.is_file():
        raise HybridLinkError(f"missing {label}: {path}")
    return path


def extract_archive(ar: str, archive: Path, destination: Path) -> dict[str, Path]:
    members = [line for line in run([ar, "t", str(archive)], capture=True).splitlines() if line]
    duplicates = sorted({member for member in members if members.count(member) > 1})
    if duplicates:
        raise HybridLinkError(f"archive has duplicate member names ({archive}): {', '.join(duplicates)}")
    destination.mkdir(parents=True, exist_ok=True)
    run([ar, "x", str(archive)], cwd=destination)
    extracted = {member: destination / member for member in members}
    missing = [member for member, path in extracted.items() if not path.is_file()]
    if missing:
        raise HybridLinkError(f"failed to extract from {archive}: {', '.join(missing)}")
    return extracted


def strong_definitions(nm: str, image: Path) -> set[str]:
    output = run([nm, "--format=posix", "-g", "--defined-only", str(image)], capture=True)
    definitions: set[str] = set()
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1] in STRONG_NM_TYPES:
            definitions.add(fields[0])
    return definitions


def reference_exports(nm: str, reference_so: Path) -> tuple[list[str], str]:
    output = run([nm, "-D", "--defined-only", str(reference_so)], capture=True)
    names: set[str] = set()
    versions: set[str] = set()
    for line in output.splitlines():
        fields = line.split(maxsplit=2)
        if len(fields) != 3:
            continue
        match = VERSION_SYMBOL_RE.fullmatch(fields[2])
        if not match:
            raise HybridLinkError(f"unsupported exported symbol spelling: {fields[2]}")
        name = match.group("name")
        version = match.group("version")
        if version:
            versions.add(version)
        if name != "CANGJIE":
            names.add(name)
    if not names:
        raise HybridLinkError(f"no dynamic exports found in {reference_so}")
    if len(versions) > 1:
        raise HybridLinkError(f"multiple symbol versions are not supported: {sorted(versions)}")
    return sorted(names), next(iter(versions), "CANGJIE")


def write_export_map(path: Path, names: Iterable[str], version: str) -> None:
    lines = [f"{version} {{", "  global:"]
    lines.extend(f"    {name};" for name in names)
    lines.extend(("  local: *;", "};", ""))
    path.write_text("\n".join(lines), encoding="utf-8")


def write_hybrid_linker_script(path: Path, runtime_script: Path, shared_script: Path) -> None:
    """Insert the authoritative Cangjie metadata layout into the runtime script."""
    source = shared_script.read_text(encoding="utf-8")
    start_marker = "  /* Cangjie Metadata sections start */"
    end_marker = "  /* Cangjie Metadata sections end */"
    start = source.find(start_marker)
    end = source.find(end_marker, start)
    if start < 0 or end < 0:
        raise HybridLinkError(f"metadata layout not found in {shared_script}")
    body = source[start + len(start_marker) : end]
    runtime = runtime_script.read_text(encoding="utf-8")
    insertion = "  .bss            :"
    position = runtime.find(insertion)
    if position < 0:
        raise HybridLinkError(f".bss layout not found in {runtime_script}")
    path.write_text(runtime[:position] + body + runtime[position:], encoding="utf-8")


def replacement_members(
    nm: str,
    objcopy: str,
    injections: list[Path],
    archives: dict[str, dict[str, Path]],
    preserve_collisions: dict[str, str],
) -> tuple[dict[str, set[str]], dict[str, list[str]], dict[str, list[str]]]:
    owners: dict[str, list[tuple[str, str]]] = defaultdict(list)
    member_definitions: dict[tuple[str, str], set[str]] = {}
    for archive_name, members in archives.items():
        for member_name, object_path in members.items():
            definitions = strong_definitions(nm, object_path)
            member_definitions[(archive_name, member_name)] = definitions
            for symbol in definitions:
                owners[symbol].append((archive_name, member_name))

    removed = {name: set() for name in archives}
    reasons: dict[str, list[str]] = defaultdict(list)
    collisions: dict[tuple[str, str], set[str]] = defaultdict(set)
    injection_owners: dict[str, Path] = {}
    for injection in injections:
        for symbol in strong_definitions(nm, injection):
            previous = injection_owners.get(symbol)
            if previous is not None:
                raise HybridLinkError(
                    f"injected objects both define strong symbol {symbol}: {previous}, {injection}"
                )
            injection_owners[symbol] = injection
            for archive_name, member_name in owners.get(symbol, []):
                reasons[f"{archive_name}:{member_name}"].append(symbol)
                collisions[(archive_name, member_name)].add(symbol)

    localized: dict[str, list[str]] = {}
    for (archive_name, member_name), symbols in collisions.items():
        definitions = member_definitions[(archive_name, member_name)]
        preserved = symbols.intersection(preserve_collisions)
        if definitions <= injection_owners.keys() and not preserved:
            removed[archive_name].add(member_name)
            continue
        object_path = archives[archive_name][member_name]
        command = [objcopy]
        for symbol in sorted(symbols):
            alias = preserve_collisions.get(symbol)
            if alias:
                command.append(f"--redefine-sym={symbol}={alias}")
            else:
                command.append(f"--localize-symbol={symbol}")
        command.append(str(object_path))
        run(command)
        localized[f"{archive_name}:{member_name}"] = [
            f"{symbol}->{preserve_collisions[symbol]}"
            if symbol in preserve_collisions else symbol
            for symbol in sorted(symbols)
        ]
    return removed, reasons, localized


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a hybrid C++/Cangjie libcangjie-runtime.so without modifying the oracle tree."
    )
    parser.add_argument("--runtime-root", type=Path, default=DEFAULT_RUNTIME_ROOT)
    parser.add_argument("--toolchain", type=Path, default=DEFAULT_TOOLCHAIN)
    parser.add_argument("--runtime-archive", type=Path)
    parser.add_argument("--thread-archive", type=Path)
    parser.add_argument("--reference-so", type=Path)
    parser.add_argument(
        "--rt0-archive",
        type=Path,
        default=REPO_ROOT / "out/build/lib/libcjcj_rt0.a",
        help="libcjcj_rt0.a built by this repository",
    )
    parser.add_argument("--inject", type=Path, action="append", default=[], help="PIC Cangjie .o")
    parser.add_argument(
        "--preserve-collision",
        action="append",
        default=[],
        metavar="SYMBOL=INTERNAL_ALIAS",
        help="rename a replaced oracle definition so an injected wrapper can call it",
    )
    parser.add_argument(
        "--replace-member",
        action="append",
        default=[],
        metavar="[runtime|thread:]MEMBER",
        help="explicitly omit an oracle archive member (repeatable)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "out/hybrid/libcangjie-runtime.so",
    )
    parser.add_argument("--map-file", type=Path, help="link map output (default: OUTPUT.map)")
    parser.add_argument("--work-dir", type=Path, help="retain extraction and generated files here")
    parser.add_argument("--linker", default="clang++")
    parser.add_argument("--ar", default="llvm-ar")
    parser.add_argument("--nm", default="nm")
    parser.add_argument("--objcopy", default="llvm-objcopy")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        runtime_root = args.runtime_root.expanduser().resolve()
        toolchain = args.toolchain.expanduser().resolve()
        runtime_archive = require_file(
            args.runtime_archive or runtime_root / ARCHIVE_SUBDIR / "libcangjie-runtime.a",
            "official runtime archive",
        )
        thread_archive = require_file(
            args.thread_archive or runtime_root / ARCHIVE_SUBDIR / "libcangjie-thread.a",
            "official thread archive",
        )
        reference_so = require_file(
            args.reference_so or runtime_root / SO_SUBDIR / "libcangjie-runtime.so",
            "official shared runtime",
        )
        rt0_archive = require_file(args.rt0_archive, "rt0 archive")
        linker_script = require_file(
            runtime_root / "build/lds/x86_64_linux/cjnative_runtime.lds", "runtime linker script"
        )
        shared_linker_script = require_file(
            runtime_root / "build/lds/x86_64_linux/cjld.shared.lds",
            "Cangjie shared linker script",
        )
        boundscheck = require_file(
            toolchain / TOOLCHAIN_RUNTIME_SUBDIR / "libboundscheck.so", "libboundscheck.so"
        )
        std_core = require_file(
            toolchain / TOOLCHAIN_STATIC_SUBDIR / "libcangjie-std-core.a",
            "static std.core support archive",
        )
        injections = [require_file(path, "injected object") for path in args.inject]
        preserve_collisions: dict[str, str] = {}
        for specification in args.preserve_collision:
            if "=" not in specification:
                raise HybridLinkError(
                    f"invalid --preserve-collision (expected SYMBOL=ALIAS): {specification}"
                )
            symbol, alias = specification.split("=", 1)
            if not symbol or not alias or symbol in preserve_collisions:
                raise HybridLinkError(f"invalid --preserve-collision: {specification}")
            preserve_collisions[symbol] = alias
        output = args.output.expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        map_file = (args.map_file or Path(f"{output}.map")).expanduser().resolve()
        map_file.parent.mkdir(parents=True, exist_ok=True)

        temporary: tempfile.TemporaryDirectory[str] | None = None
        if args.work_dir:
            work_dir = args.work_dir.expanduser().resolve()
            if work_dir.exists():
                shutil.rmtree(work_dir)
            work_dir.mkdir(parents=True)
        else:
            temporary = tempfile.TemporaryDirectory(prefix="cjcj-hybrid-")
            work_dir = Path(temporary.name)

        runtime_members = extract_archive(args.ar, runtime_archive, work_dir / "runtime")
        thread_members = extract_archive(args.ar, thread_archive, work_dir / "thread")
        rt0_members = extract_archive(args.ar, rt0_archive, work_dir / "rt0")
        missing_rt0 = sorted(set(RT0_SHARED_MEMBERS) - set(rt0_members))
        if missing_rt0:
            raise HybridLinkError(f"rt0 archive is incomplete: {', '.join(missing_rt0)}")

        archives = {"runtime": runtime_members, "thread": thread_members}
        removed, reasons, localized = replacement_members(
            args.nm, args.objcopy, injections, archives, preserve_collisions
        )
        removed["runtime"].update(RT0_REPLACED_RUNTIME_MEMBERS)

        for specification in args.replace_member:
            if ":" in specification:
                archive_name, member_name = specification.split(":", 1)
                if archive_name not in archives:
                    raise HybridLinkError(f"unknown archive in --replace-member: {archive_name}")
                targets = (archive_name,)
            else:
                member_name = specification
                targets = tuple(name for name, members in archives.items() if member_name in members)
                if not targets:
                    raise HybridLinkError(f"unknown --replace-member: {member_name}")
            for archive_name in targets:
                if member_name not in archives[archive_name]:
                    raise HybridLinkError(f"missing member {archive_name}:{member_name}")
                removed[archive_name].add(member_name)

        exports, version = reference_exports(args.nm, reference_so)
        export_map = work_dir / "hybrid-export.map"
        write_export_map(export_map, exports, version)
        hybrid_linker_script = work_dir / "cjnative-runtime-with-metadata.lds"
        write_hybrid_linker_script(hybrid_linker_script, linker_script, shared_linker_script)

        selected_rt0 = [rt0_members[name] for name in RT0_SHARED_MEMBERS]
        selected_runtime = [
            path for name, path in runtime_members.items() if name not in removed["runtime"]
        ]
        selected_thread = [
            path for name, path in thread_members.items() if name not in removed["thread"]
        ]
        command = [
            args.linker,
            "-shared",
            "-o",
            str(output),
            "-Wl,-z,relro",
            "-Wl,-z,now",
            "-Wl,-z,noexecstack",
            "-Wl,--gc-sections",
            "-Wl,-Bsymbolic",
            "-Wl,--no-undefined",
            "-Wl,-soname,libcangjie-runtime.so",
            "-Wl,--defsym,g_runtimeStaticStart=g_runtimeDynamicStart",
            "-Wl,--defsym,g_runtimeStaticEnd=g_runtimeDynamicEnd",
            f"-Wl,-T{hybrid_linker_script}",
            f"-Wl,--version-script={export_map}",
            f"-Wl,-Map,{map_file}",
            *[str(path) for path in injections],
            *[str(path) for path in selected_rt0],
            *[str(path) for path in selected_runtime],
            *[str(path) for path in selected_thread],
            str(std_core),
            f"-L{boundscheck.parent}",
            "-lboundscheck",
            "-lstdc++",
            "-lm",
            "-lc",
            "-lgcc_s",
            "-lpthread",
            "-ldl",
        ]
        if args.verbose:
            print("LINK COMMAND " + " ".join(command))
            for member, symbols in sorted(reasons.items()):
                print(f"AUTO REPLACE {member} symbols={','.join(sorted(symbols))}")
            for member, symbols in sorted(localized.items()):
                print(f"LOCALIZE ORIGINAL {member} symbols={','.join(symbols)}")
        run(command)

        replaced_count = len(removed["runtime"]) + len(removed["thread"])
        print(
            f"HYBRID LINK PASS output={output} exports={len(exports) + 1} "
            f"runtime_objects={len(selected_runtime)} thread_objects={len(selected_thread)} "
            f"rt0_objects={len(selected_rt0)} injected={len(injections)} replaced={replaced_count} "
            f"localized={len(localized)}"
        )
        if temporary is not None:
            temporary.cleanup()
        return 0
    except HybridLinkError as error:
        print(f"HYBRID LINK ERROR {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
