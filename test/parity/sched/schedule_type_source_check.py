#!/usr/bin/env python3

import argparse
import re
import sys
from collections import Counter
from pathlib import Path


EXPECTED = """public type ScheduleType = UInt32
public const SCHEDULE_DEFAULT: ScheduleType = 0u32
public const SCHEDULE_UI_THREAD: ScheduleType = 1u32
public const SCHEDULE_FOREIGN_THREAD: ScheduleType = 2u32
public const SCHEDULE_EXCLUSIVE: ScheduleType = 3u32"""
TOKEN = re.compile(
    r"\b(?:scheduleType|ScheduleType|SCHEDULE_(?:DEFAULT|UI_THREAD|FOREIGN_THREAD|EXCLUSIVE))\b"
)
EXPECTED_CLASSES = Counter({
    "comparison": 66,
    "enumerator_definition": 4,
    "parameter": 3,
    "switch_label": 3,
    "comment": 2,
    "forwarding_call": 2,
    "local_copy": 2,
    "diagnostic_use": 1,
    "owner_field": 1,
    "parameter_documentation": 1,
    "return": 1,
    "store": 1,
    "type_definition": 1,
})


def inject(text, mode):
    replacements = {
        "value_default": ("SCHEDULE_DEFAULT: ScheduleType = 0u32", "SCHEDULE_DEFAULT: ScheduleType = 9u32"),
        "value_ui": ("SCHEDULE_UI_THREAD: ScheduleType = 1u32", "SCHEDULE_UI_THREAD: ScheduleType = 9u32"),
        "value_foreign": ("SCHEDULE_FOREIGN_THREAD: ScheduleType = 2u32", "SCHEDULE_FOREIGN_THREAD: ScheduleType = 9u32"),
        "value_exclusive": ("SCHEDULE_EXCLUSIVE: ScheduleType = 3u32", "SCHEDULE_EXCLUSIVE: ScheduleType = 9u32"),
        "omitted": ("public const SCHEDULE_FOREIGN_THREAD: ScheduleType = 2u32\n", ""),
        "alias64": ("public type ScheduleType = UInt32", "public type ScheduleType = UInt64"),
        "alias_signed": ("public type ScheduleType = UInt32", "public type ScheduleType = Int32"),
        "initializer": ("public const SCHEDULE_EXCLUSIVE: ScheduleType = 3u32",
            "public const SCHEDULE_EXCLUSIVE: ScheduleType = 3u32\npublic let SCHEDULE_TYPE_RUNTIME = RuntimeInitializer()"),
    }
    if mode == "normal":
        return text
    if mode == "swapped":
        first = "public const SCHEDULE_DEFAULT: ScheduleType = 0u32"
        last = "public const SCHEDULE_EXCLUSIVE: ScheduleType = 3u32"
        if text.count(first) != 1 or text.count(last) != 1:
            raise ValueError("swap injection anchors absent")
        return text.replace(first, "__SCHEDULE_TYPE_SWAP__").replace(last, first).replace(
            "__SCHEDULE_TYPE_SWAP__", last
        )
    old, new = replacements[mode]
    if text.count(old) != 1:
        raise ValueError(f"injection anchor count for {mode}: {text.count(old)}")
    return text.replace(old, new)


def check_source(text):
    errors = []
    if text.count(EXPECTED) != 1:
        errors.append("exact alias/constants block mismatch")
    if len(re.findall(r"^public type ScheduleType\s*=", text, re.MULTILINE)) != 1:
        errors.append("alias count mismatch")
    definitions = re.findall(
        r"^public const (SCHEDULE_[A-Z_]+): ScheduleType = (\d+u32)$", text, re.MULTILINE
    )
    expected_definitions = [
        ("SCHEDULE_DEFAULT", "0u32"),
        ("SCHEDULE_UI_THREAD", "1u32"),
        ("SCHEDULE_FOREIGN_THREAD", "2u32"),
        ("SCHEDULE_EXCLUSIVE", "3u32"),
    ]
    if definitions != expected_definitions:
        errors.append(f"constant inventory/order mismatch: {definitions}")
    start = text.find("public type ScheduleType")
    end = text.find("// CJThread schedule/include/inner/gas", start)
    if start < 0 or end < 0:
        errors.append("schedule vocabulary slice absent")
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
        lines = absolute.read_text(encoding="utf-8").splitlines()
        for line_number, exact in enumerate(lines, 1):
            occurrences = len(TOKEN.findall(exact))
            if occurrences:
                actual[(path, line_number)] = (occurrences, exact)
    if set(actual) != set(expected):
        errors.append(
            f"reference set drift missing={sorted(set(expected) - set(actual))} "
            f"extra={sorted(set(actual) - set(expected))}"
        )
    for key in sorted(set(actual) & set(expected)):
        occurrences, exact = actual[key]
        expected_occurrences, expected_exact = expected[key][2], expected[key][3]
        if occurrences != expected_occurrences or exact != expected_exact:
            errors.append(f"reference line drift {key[0]}:{key[1]}")
    classes = Counter(row[0] for row in rows)
    if classes != EXPECTED_CLASSES:
        errors.append(f"classification drift: {dict(classes)}")
    if len(rows) != 88 or sum(row[4] for row in rows) != 169:
        errors.append("inventory row/token count drift")
    platforms = Counter(row[1] for row in rows)
    expected_platforms = Counter({
        "all_targets": 71, "ohos": 12, "non_win64": 3, "arm32": 1, "win64": 1,
    })
    if platforms != expected_platforms:
        errors.append(f"platform classification drift: {dict(platforms)}")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--runtime-root")
    parser.add_argument("--inventory")
    parser.add_argument("--mode", choices=("normal", "value_default", "value_ui",
        "value_foreign", "value_exclusive", "swapped", "omitted", "alias64",
        "alias_signed", "initializer"), default="normal")
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
        print(f"SCHEDULE_TYPE_SOURCE FAIL mode={args.mode} error={' ; '.join(errors)}", file=sys.stderr)
        return 1
    print("SCHEDULE_TYPE_SOURCE alias=1 constants=4 order=DEFAULT,UI_THREAD,FOREIGN_THREAD,EXCLUSIVE "
        "typed_u32=4 helpers=0 runtime_initializers=0 inventory_lines=88 inventory_tokens=169 "
        "classifications=13 status=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
