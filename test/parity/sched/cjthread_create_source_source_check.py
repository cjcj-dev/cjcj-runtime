#!/usr/bin/env python3

import argparse
import re
import sys
from collections import Counter
from pathlib import Path


EXPECTED = """public type CJThreadCreateSource = UInt32
public const CJTHREAD_CREATE_SOURCE_DEFAULT: CJThreadCreateSource = 0u32
public const CJTHREAD_CREATE_SOURCE_SIGNAL: CJThreadCreateSource = 1u32
public const CJTHREAD_CREATE_SOURCE_FINALIZER: CJThreadCreateSource = 2u32"""
TOKEN = re.compile(
    r"\b(?:createSource|CJThreadCreateSource|CJTHREAD_CREATE_SOURCE_(?:DEFAULT|SIGNAL|FINALIZER))\b"
)
EXPECTED_CLASSES = Counter({
    "parameter": 7,
    "forwarding_call": 4,
    "enumerator_definition": 3,
    "parameter_with_default": 3,
    "comparison": 2,
    "finalizer_early_return_use": 1,
    "type_definition": 1,
})


def inject(text, mode):
    replacements = {
        "value_default": ("CJTHREAD_CREATE_SOURCE_DEFAULT: CJThreadCreateSource = 0u32",
            "CJTHREAD_CREATE_SOURCE_DEFAULT: CJThreadCreateSource = 9u32"),
        "value_signal": ("CJTHREAD_CREATE_SOURCE_SIGNAL: CJThreadCreateSource = 1u32",
            "CJTHREAD_CREATE_SOURCE_SIGNAL: CJThreadCreateSource = 9u32"),
        "value_finalizer": ("CJTHREAD_CREATE_SOURCE_FINALIZER: CJThreadCreateSource = 2u32",
            "CJTHREAD_CREATE_SOURCE_FINALIZER: CJThreadCreateSource = 9u32"),
        "omitted": ("public const CJTHREAD_CREATE_SOURCE_SIGNAL: CJThreadCreateSource = 1u32\n", ""),
        "alias64": ("public type CJThreadCreateSource = UInt32",
            "public type CJThreadCreateSource = UInt64"),
        "alias_signed": ("public type CJThreadCreateSource = UInt32",
            "public type CJThreadCreateSource = Int32"),
        "initializer": ("public const CJTHREAD_CREATE_SOURCE_FINALIZER: CJThreadCreateSource = 2u32",
            "public const CJTHREAD_CREATE_SOURCE_FINALIZER: CJThreadCreateSource = 2u32\n"
            "public let CJTHREAD_CREATE_SOURCE_RUNTIME = RuntimeInitializer()"),
    }
    if mode == "normal":
        return text
    if mode == "swapped":
        first = "public const CJTHREAD_CREATE_SOURCE_DEFAULT: CJThreadCreateSource = 0u32"
        last = "public const CJTHREAD_CREATE_SOURCE_FINALIZER: CJThreadCreateSource = 2u32"
        if text.count(first) != 1 or text.count(last) != 1:
            raise ValueError("swap injection anchors absent")
        return text.replace(first, "__CJTHREAD_CREATE_SOURCE_SWAP__").replace(
            last, first).replace("__CJTHREAD_CREATE_SOURCE_SWAP__", last)
    old, new = replacements[mode]
    if text.count(old) != 1:
        raise ValueError(f"injection anchor count for {mode}: {text.count(old)}")
    return text.replace(old, new)


def check_source(text):
    errors = []
    if text.count(EXPECTED) != 1:
        errors.append("exact alias/constants block mismatch")
    if len(re.findall(r"^public type CJThreadCreateSource\s*=", text, re.MULTILINE)) != 1:
        errors.append("alias count mismatch")
    definitions = re.findall(
        r"^public const (CJTHREAD_CREATE_SOURCE_[A-Z_]+): CJThreadCreateSource = (\d+u32)$",
        text, re.MULTILINE,
    )
    expected_definitions = [
        ("CJTHREAD_CREATE_SOURCE_DEFAULT", "0u32"),
        ("CJTHREAD_CREATE_SOURCE_SIGNAL", "1u32"),
        ("CJTHREAD_CREATE_SOURCE_FINALIZER", "2u32"),
    ]
    if definitions != expected_definitions:
        errors.append(f"constant inventory/order mismatch: {definitions}")
    start = text.find("public type CJThreadCreateSource")
    end = text.find("// CJThread schedule/include/schedule.h:415-420", start)
    if start < 0 or end < 0:
        errors.append("create-source vocabulary slice absent")
    else:
        target = text[start:end]
        if re.search(r"\b(?:func|class|enum|let|var)\b", target):
            errors.append("helper, enum object, or runtime initializer in target slice")
    return errors


def load_inventory(path):
    rows = []
    for number, raw in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t", 5)
        if len(fields) != 6:
            raise ValueError(f"inventory field count at line {number}")
        classification, platform, source, line, occurrences, exact = fields
        rows.append((classification, platform, source, int(line), int(occurrences), exact))
    return rows


def check_inventory(runtime_root, inventory):
    errors = []
    rows = load_inventory(inventory)
    expected = {(source, line): (classification, platform, occurrences, exact)
        for classification, platform, source, line, occurrences, exact in rows}
    if len(expected) != len(rows):
        errors.append("duplicate inventory path/line")
    actual = {}
    root = Path(runtime_root)
    for absolute in sorted(path for path in root.rglob("*") if path.is_file()):
        path = absolute.relative_to(root).as_posix()
        for line_number, exact in enumerate(
                absolute.read_text(encoding="utf-8").splitlines(), 1):
            occurrences = len(TOKEN.findall(exact))
            if occurrences:
                actual[(path, line_number)] = (occurrences, exact)
    if set(actual) != set(expected):
        errors.append(f"reference set drift missing={sorted(set(expected) - set(actual))} "
            f"extra={sorted(set(actual) - set(expected))}")
    for key in sorted(set(actual) & set(expected)):
        occurrences, exact = actual[key]
        expected_occurrences, expected_exact = expected[key][2], expected[key][3]
        if occurrences != expected_occurrences or exact != expected_exact:
            errors.append(f"reference line drift {key[0]}:{key[1]}")
    classes = Counter(row[0] for row in rows)
    if classes != EXPECTED_CLASSES:
        errors.append(f"classification drift: {dict(classes)}")
    if len(rows) != 21 or sum(row[4] for row in rows) != 37:
        errors.append("inventory row/token count drift")
    platforms = Counter(row[1] for row in rows)
    if platforms != Counter({"all_targets": 21}):
        errors.append(f"platform classification drift: {dict(platforms)}")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--runtime-root")
    parser.add_argument("--inventory")
    parser.add_argument("--mode", choices=("normal", "value_default", "value_signal",
        "value_finalizer", "swapped", "omitted", "alias64", "alias_signed", "initializer"),
        default="normal")
    args = parser.parse_args()
    try:
        text = inject(Path(args.source).read_text(encoding="utf-8"), args.mode)
        errors = check_source(text)
        if args.mode == "normal":
            if not args.runtime_root or not args.inventory:
                errors.append("normal mode requires runtime root and inventory")
            else:
                errors.extend(check_inventory(args.runtime_root, args.inventory))
    except (OSError, ValueError) as error:
        errors = [str(error)]
    if errors:
        print(f"CJTHREAD_CREATE_SOURCE_SOURCE FAIL mode={args.mode} "
            f"error={' ; '.join(errors)}", file=sys.stderr)
        return 1
    print("CJTHREAD_CREATE_SOURCE_SOURCE alias=1 constants=3 "
        "order=DEFAULT,SIGNAL,FINALIZER typed_u32=3 helpers=0 runtime_initializers=0 "
        "inventory_lines=21 inventory_tokens=37 classifications=7 status=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
