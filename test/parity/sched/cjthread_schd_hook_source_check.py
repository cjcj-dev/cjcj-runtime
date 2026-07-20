#!/usr/bin/env python3

import argparse
import re
import sys
from collections import Counter
from pathlib import Path


EXPECTED = """public type CJThreadSchdHook = UInt32
public const SCHD_STOP: CJThreadSchdHook = 0u32
public const SCHD_CREATE_MUTATOR: CJThreadSchdHook = 1u32
public const SCHD_DESTROY_MUTATOR: CJThreadSchdHook = 2u32
public const SCHD_PREEMPT_REQ: CJThreadSchdHook = 3u32
public const SCHD_NEW_MUTATOR: CJThreadSchdHook = 4u32
public const SCHD_HOOK_BUTT: CJThreadSchdHook = 5u32"""
TOKEN = re.compile(
    r"\b(?:CJThreadSchdHookRegister|CJThreadSchdHook|SchdCJThreadHookFunc|"
    r"schdCJThreadHook|SCHD_CREATE_MUTATOR|SCHD_DESTROY_MUTATOR|"
    r"SCHD_PREEMPT_REQ|SCHD_NEW_MUTATOR|SCHD_HOOK_BUTT|SCHD_STOP)\b"
)
EXPECTED_CLASSES = Counter({
    "enumerator_definition": 6,
    "array_read": 4,
    "gc_registration": 4,
    "local_callback": 3,
    "api_declaration": 1,
    "api_documentation": 1,
    "callback_documentation": 1,
    "callback_typedef": 1,
    "generic_array_store": 1,
    "owner_array": 1,
    "registration_definition": 1,
    "rename_macro": 1,
    "type_definition": 1,
    "upper_bound_validation": 1,
})


def inject(text, mode):
    replacements = {
        "value_stop": ("SCHD_STOP: CJThreadSchdHook = 0u32", "SCHD_STOP: CJThreadSchdHook = 9u32"),
        "value_create": ("SCHD_CREATE_MUTATOR: CJThreadSchdHook = 1u32", "SCHD_CREATE_MUTATOR: CJThreadSchdHook = 9u32"),
        "value_destroy": ("SCHD_DESTROY_MUTATOR: CJThreadSchdHook = 2u32", "SCHD_DESTROY_MUTATOR: CJThreadSchdHook = 9u32"),
        "value_preempt": ("SCHD_PREEMPT_REQ: CJThreadSchdHook = 3u32", "SCHD_PREEMPT_REQ: CJThreadSchdHook = 9u32"),
        "value_new": ("SCHD_NEW_MUTATOR: CJThreadSchdHook = 4u32", "SCHD_NEW_MUTATOR: CJThreadSchdHook = 9u32"),
        "value_butt": ("SCHD_HOOK_BUTT: CJThreadSchdHook = 5u32", "SCHD_HOOK_BUTT: CJThreadSchdHook = 9u32"),
        "omitted": ("public const SCHD_NEW_MUTATOR: CJThreadSchdHook = 4u32\n", ""),
        "alias64": ("public type CJThreadSchdHook = UInt32", "public type CJThreadSchdHook = UInt64"),
        "alias_signed": ("public type CJThreadSchdHook = UInt32", "public type CJThreadSchdHook = Int32"),
        "initializer": ("public const SCHD_HOOK_BUTT: CJThreadSchdHook = 5u32",
            "public const SCHD_HOOK_BUTT: CJThreadSchdHook = 5u32\npublic let SCHD_HOOK_RUNTIME = RuntimeInitializer()"),
    }
    if mode == "normal":
        return text
    if mode == "swapped":
        first = "public const SCHD_STOP: CJThreadSchdHook = 0u32"
        last = "public const SCHD_HOOK_BUTT: CJThreadSchdHook = 5u32"
        if text.count(first) != 1 or text.count(last) != 1:
            raise ValueError("swap injection anchors absent")
        return text.replace(first, "__SCHD_HOOK_SWAP__").replace(last, first).replace(
            "__SCHD_HOOK_SWAP__", last)
    old, new = replacements[mode]
    if text.count(old) != 1:
        raise ValueError(f"injection anchor count for {mode}: {text.count(old)}")
    return text.replace(old, new)


def check_source(text):
    errors = []
    if text.count(EXPECTED) != 1:
        errors.append("exact alias/constants block mismatch")
    if len(re.findall(r"^public type CJThreadSchdHook\s*=", text, re.MULTILINE)) != 1:
        errors.append("alias count mismatch")
    definitions = re.findall(
        r"^public const (SCHD_[A-Z_]+): CJThreadSchdHook = (\d+u32)$", text, re.MULTILINE
    )
    expected_definitions = [
        ("SCHD_STOP", "0u32"),
        ("SCHD_CREATE_MUTATOR", "1u32"),
        ("SCHD_DESTROY_MUTATOR", "2u32"),
        ("SCHD_PREEMPT_REQ", "3u32"),
        ("SCHD_NEW_MUTATOR", "4u32"),
        ("SCHD_HOOK_BUTT", "5u32"),
    ]
    if definitions != expected_definitions:
        errors.append(f"constant inventory/order mismatch: {definitions}")
    start = text.find("public type CJThreadSchdHook")
    end = text.find("// CJThread schedule/include/schedule.h:415-420", start)
    if start < 0 or end < 0:
        errors.append("schedule-hook vocabulary slice absent")
    else:
        target = text[start:end]
        forbidden = re.compile(
            r"\b(?:func|class|enum|let|var|CPointer|CJThreadSchdHookRegister|"
            r"SchdCJThreadHookFunc|schdCJThreadHook)\b|@C"
        )
        if forbidden.search(target):
            errors.append("helper, enum object, export, owner, hook container, or initializer in target slice")
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


def check_inventory(runtime_root, inventory, inventory_mode):
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
        for line_number, exact in enumerate(absolute.read_text(encoding="utf-8").splitlines(), 1):
            occurrences = len(TOKEN.findall(exact))
            if occurrences:
                actual[(path, line_number)] = (occurrences, exact)
    if inventory_mode == "extra_registration":
        actual[("Concurrency/CJThreadModel/CJThreadModel.cpp", 77)] = (
            2, "    (void)CJThreadSchdHookRegister(Injected, SCHD_NEW_MUTATOR);")
    elif inventory_mode == "missing_registration":
        actual.pop(("Concurrency/CJThreadModel/CJThreadModel.cpp", 73), None)
    elif inventory_mode == "missing_array_index":
        actual.pop(("CJThread/src/runtime/schedule/src/cjthread.cpp", 637), None)
    elif inventory_mode == "missing_owner":
        actual.pop(("CJThread/src/runtime/schedule/include/inner/schedule_impl.h", 211), None)
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
    if len(rows) != 27 or sum(row[4] for row in rows) != 41:
        errors.append("inventory row/token count drift")
    platforms = Counter(row[1] for row in rows)
    if platforms != Counter({"all_targets": 26, "cangjie_build_mode": 1}):
        errors.append(f"platform classification drift: {dict(platforms)}")
    new_mutator_rows = [row for row in rows if "SCHD_NEW_MUTATOR" in row[5]]
    if len(new_mutator_rows) != 1 or new_mutator_rows[0][0] != "enumerator_definition":
        errors.append("SCHD_NEW_MUTATOR acquired a consumer")
    if classes.get("switch_label", 0) != 0:
        errors.append("switch consumer acquired")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--runtime-root")
    parser.add_argument("--inventory")
    parser.add_argument("--mode", choices=("normal", "value_stop", "value_create",
        "value_destroy", "value_preempt", "value_new", "value_butt", "swapped",
        "omitted", "alias64", "alias_signed", "initializer"), default="normal")
    parser.add_argument("--inventory-mode", choices=("normal", "extra_registration",
        "missing_registration", "missing_array_index", "missing_owner"), default="normal")
    args = parser.parse_args()
    try:
        text = inject(Path(args.source).read_text(encoding="utf-8"), args.mode)
        errors = check_source(text)
        if args.mode == "normal":
            if not args.runtime_root or not args.inventory:
                errors.append("normal mode requires runtime root and inventory")
            else:
                errors.extend(check_inventory(args.runtime_root, args.inventory, args.inventory_mode))
    except (OSError, ValueError) as error:
        errors = [str(error)]
    if errors:
        print(f"CJTHREAD_SCHD_HOOK_SOURCE FAIL mode={args.mode} "
            f"inventory_mode={args.inventory_mode} error={' ; '.join(errors)}", file=sys.stderr)
        return 1
    print("CJTHREAD_SCHD_HOOK_SOURCE alias=1 constants=6 "
        "order=STOP,CREATE_MUTATOR,DESTROY_MUTATOR,PREEMPT_REQ,NEW_MUTATOR,HOOK_BUTT "
        "typed_u32=6 helpers=0 runtime_initializers=0 inventory_lines=27 "
        "inventory_tokens=41 classifications=14 switch_consumers=0 "
        "new_mutator_consumers=0 status=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
