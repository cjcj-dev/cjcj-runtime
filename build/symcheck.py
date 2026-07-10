#!/usr/bin/env python3
"""Compare the complete defined dynamic-symbol sets of two ELF shared objects."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def dynamic_symbols(nm: str, image: Path) -> set[str]:
    try:
        result = subprocess.run(
            [nm, "-D", "--defined-only", str(image)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        raise RuntimeError(f"nm failed for {image}: {detail.strip()}") from error

    symbols: set[str] = set()
    for line in result.stdout.splitlines():
        fields = line.split(maxsplit=2)
        if len(fields) == 3:
            symbols.add(fields[2])
    return symbols


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Require two ELF images to have identical nm -D defined symbol sets."
    )
    parser.add_argument("reference", type=Path, help="official libcangjie-runtime.so")
    parser.add_argument("candidate", type=Path, help="hybrid libcangjie-runtime.so")
    parser.add_argument("--nm", default="nm", help="nm-compatible executable")
    parser.add_argument(
        "--ignore-regex",
        action="append",
        default=[],
        help="ignore matching decorated symbol names (repeatable)",
    )
    parser.add_argument("--max-diff", type=int, default=50, help="maximum names printed per side")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    for image in (args.reference, args.candidate):
        if not image.is_file():
            print(f"SYMCHECK ERROR missing image: {image}", file=sys.stderr)
            return 2

    try:
        reference = dynamic_symbols(args.nm, args.reference)
        candidate = dynamic_symbols(args.nm, args.candidate)
        ignored = [re.compile(pattern) for pattern in args.ignore_regex]
    except (RuntimeError, re.error) as error:
        print(f"SYMCHECK ERROR {error}", file=sys.stderr)
        return 2

    if ignored:
        reference = {name for name in reference if not any(regex.search(name) for regex in ignored)}
        candidate = {name for name in candidate if not any(regex.search(name) for regex in ignored)}

    missing = sorted(reference - candidate)
    extra = sorted(candidate - reference)
    status = "PASS" if not missing and not extra else "FAIL"
    print(
        f"SYMCHECK {status} reference={len(reference)} candidate={len(candidate)} "
        f"missing={len(missing)} extra={len(extra)}"
    )
    if missing:
        for name in missing[: args.max_diff]:
            print(f"missing {name}")
    if extra:
        for name in extra[: args.max_diff]:
            print(f"extra {name}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
