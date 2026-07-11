#!/usr/bin/env python3
"""Inventory @NoHeapAlloc roots and inspect their ELF references."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ANNOTATION_RE = re.compile(r"^\s*@(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*$")
FUNCTION_RE = re.compile(
    r"^\s*(?:(?:public|private|protected|internal|open|static|operator|unsafe)\s+)*"
    r"func\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\("
)
LABEL_RE = re.compile(r"^[0-9a-fA-F]+\s+<(?P<name>[^>]+)>:$")
TARGET_RE = re.compile(r"\b(?:callq?|jmpq?)\b.*<(?P<target>[^>]+)>")
RELOCATION_RE = re.compile(r"\bR_[A-Z0-9_]+\s+(?P<target>\S+)")
MANAGED_ALLOC_RE = re.compile(r"^(?:CJ_)?MCC_New[A-Za-z0-9_]*$")
TLS_NAMES = frozenset(("MRT_GetThreadLocalData", "CJ_MRT_GetThreadLocalData"))


@dataclass(frozen=True)
class Root:
    source: Path
    line: int
    function: str
    symbol: str


def run(command: list[str]) -> str:
    try:
        return subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"A4_GATE_ERROR command failed: {' '.join(command)}: {error}", file=sys.stderr)
        raise SystemExit(2) from error


def normalized_symbol(name: str) -> str:
    name = name.split("@", 1)[0]
    return re.split(r"[+-](?:0x)?[0-9a-fA-F]+$", name, maxsplit=1)[0]


def inventory(paths: list[Path]) -> list[Root]:
    roots: list[Root] = []
    files: list[Path] = []
    for path in paths:
        files.extend(sorted(path.rglob("*.cj")) if path.is_dir() else [path])
    for source in sorted(set(files)):
        annotations: list[str] = []
        for line_number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
            annotation = ANNOTATION_RE.match(line)
            if annotation:
                annotations.append(annotation.group("name"))
                continue
            function = FUNCTION_RE.match(line)
            if function:
                if "NoHeapAlloc" in annotations:
                    name = function.group("name")
                    roots.append(Root(source.resolve(), line_number, name, name if "C" in annotations else "-"))
                annotations.clear()
                continue
            stripped = line.strip()
            if stripped and not stripped.startswith("//"):
                annotations.clear()
    return roots


def write_manifest(roots: list[Root], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    lines = ["source\tline\tfunction\tlink_symbol"]
    lines.extend(f"{root.source}\t{root.line}\t{root.function}\t{root.symbol}" for root in roots)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_manifest(path: Path) -> list[Root]:
    roots: list[Root] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "source\tline\tfunction\tlink_symbol":
        raise SystemExit(f"A4_GATE_ERROR invalid manifest header: {path}")
    for line in lines[1:]:
        source, number, function, symbol = line.split("\t")
        roots.append(Root(Path(source), int(number), function, symbol))
    return roots


def object_edges(objdump: str, image: Path) -> tuple[dict[str, set[str]], set[str]]:
    output = run([objdump, "-dr", str(image)]) + "\n" + run([objdump, "-r", str(image)])
    edges: dict[str, set[str]] = {}
    references: set[str] = set()
    current: str | None = None
    for line in output.splitlines():
        if line.startswith("RELOCATION RECORDS FOR"):
            current = None
        label = LABEL_RE.match(line.strip())
        if label:
            current = normalized_symbol(label.group("name"))
            edges.setdefault(current, set())
            continue
        target = TARGET_RE.search(line) or RELOCATION_RE.search(line)
        if target:
            normalized = normalized_symbol(target.group("target"))
            references.add(normalized)
            if current is not None:
                edges[current].add(normalized)
    return edges, references


def inspect_object(objdump: str, image: Path, roots: list[Root]) -> int:
    edges, references = object_edges(objdump, image)
    failures = 0
    managed_object = sorted(name for name in references if MANAGED_ALLOC_RE.match(name))
    tls_object = sorted(name for name in references if name in TLS_NAMES)
    for root in roots:
        if root.symbol == "-":
            print(f"STATIC root={root.function} status=FAIL reason=no-C-link-symbol")
            failures += 1
            continue
        if root.symbol not in edges:
            print(f"STATIC root={root.function} symbol={root.symbol} status=FAIL reason=symbol-not-found")
            failures += 1
            continue
        pending = [root.symbol]
        visited: set[str] = set()
        managed: set[str] = set()
        tls: set[str] = set()
        while pending:
            function = pending.pop()
            if function in visited:
                continue
            visited.add(function)
            for target in edges.get(function, ()):
                if MANAGED_ALLOC_RE.match(target):
                    managed.add(target)
                if target in TLS_NAMES:
                    tls.add(target)
                if target in edges:
                    pending.append(target)
        status = "PASS" if not managed else "FAIL"
        failures += 1 if managed else 0
        print(
            f"STATIC root={root.function} symbol={root.symbol} reachable_functions={len(visited)} "
            f"managed_alloc_refs={len(managed)} tls_refs={len(tls)} status={status}"
        )
    print(
        f"STATIC_SUMMARY roots={len(roots)} object_managed_alloc_refs={len(managed_object)} "
        f"object_tls_refs={len(tls_object)} failures={failures}"
    )
    return 1 if failures or managed_object or not tls_object else 0


def inspect_runtime(nm: str, image: Path) -> int:
    output = run([nm, "-D", "--defined-only", str(image)])
    names = {
        normalized_symbol(fields[-1])
        for line in output.splitlines()
        if len(fields := line.split()) >= 3
    }
    allocation = sorted(name for name in names if MANAGED_ALLOC_RE.match(name))
    tls = sorted(name for name in names if name in TLS_NAMES)
    offset_check = sorted(name for name in names if name.endswith("CheckThreadLocalDataOffset"))
    status = "PASS" if allocation and tls and offset_check else "FAIL"
    print(
        f"RUNTIME image={image} allocation_exports={len(allocation)} tls_exports={len(tls)} "
        f"tls_offset_check_exports={len(offset_check)} status={status}"
    )
    return 0 if status == "PASS" else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    inventory_parser = subparsers.add_parser("inventory")
    inventory_parser.add_argument("--source", type=Path, action="append", required=True)
    inventory_parser.add_argument("--output", type=Path, required=True)
    inventory_parser.add_argument("--allow-empty", action="store_true")
    object_parser = subparsers.add_parser("inspect-object")
    object_parser.add_argument("--manifest", type=Path, required=True)
    object_parser.add_argument("--image", type=Path, required=True)
    object_parser.add_argument("--objdump", default="llvm-objdump")
    runtime_parser = subparsers.add_parser("inspect-runtime")
    runtime_parser.add_argument("--image", type=Path, required=True)
    runtime_parser.add_argument("--nm", default="nm")
    args = parser.parse_args()
    if args.command == "inventory":
        roots = inventory(args.source)
        write_manifest(roots, args.output)
        c_symbols = sum(root.symbol != "-" for root in roots)
        print(f"ANNOTATION_INVENTORY roots={len(roots)} c_symbols={c_symbols} output={args.output}")
        return 0 if (roots or args.allow_empty) and roots == read_manifest(args.output) else 1
    if args.command == "inspect-object":
        return inspect_object(args.objdump, args.image, read_manifest(args.manifest))
    return inspect_runtime(args.nm, args.image)


if __name__ == "__main__":
    raise SystemExit(main())
