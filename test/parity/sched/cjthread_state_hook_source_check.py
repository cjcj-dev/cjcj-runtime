#!/usr/bin/env python3

import argparse
import re
import sys
from collections import Counter
from pathlib import Path


EXPECTED = """public type CJThreadStateHook = UInt32
public const CJTHREAD_BEFORE_PARK: CJThreadStateHook = 0u32
public const CJTHREAD_AFTER_PARK: CJThreadStateHook = 1u32
public const CJTHREAD_BEFORE_RESCHED: CJThreadStateHook = 2u32
public const CJTHREAD_AFTER_RESCHED: CJThreadStateHook = 3u32
public const CJTHREAD_STATE_HOOK_BUTT: CJThreadStateHook = 4u32"""
ADJACENCY = """public const SCHD_HOOK_BUTT: CJThreadSchdHook = 5u32

// CJThread schedule/include/schedule.h:344-353. The target enum has no #if
// branches. The Linux x86_64 oracle proves a 4-byte unsigned representation.
public type CJThreadStateHook = UInt32
public const CJTHREAD_BEFORE_PARK: CJThreadStateHook = 0u32
public const CJTHREAD_AFTER_PARK: CJThreadStateHook = 1u32
public const CJTHREAD_BEFORE_RESCHED: CJThreadStateHook = 2u32
public const CJTHREAD_AFTER_RESCHED: CJThreadStateHook = 3u32
public const CJTHREAD_STATE_HOOK_BUTT: CJThreadStateHook = 4u32

// CJThread schedule/include/schedule.h:403-410. The target enum has no #if"""
TOKEN = re.compile(
    r"\b(?:CJThreadStateHookRegister|CJThreadeStateHookRegister|CJThreadStateHook|"
    r"SchdCJThreadStateHookFunc|schdCJThreadStateHook|CJTHREAD_BEFORE_PARK|"
    r"CJTHREAD_AFTER_PARK|CJTHREAD_BEFORE_RESCHED|CJTHREAD_AFTER_RESCHED|"
    r"CJTHREAD_STATE_HOOK_BUTT)\b"
)
EXPECTED_CLASSES = Counter({
    "enumerator_definition": 5,
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
POSITION_ENUMERATORS = (
    "CJTHREAD_BEFORE_PARK",
    "CJTHREAD_AFTER_PARK",
    "CJTHREAD_BEFORE_RESCHED",
    "CJTHREAD_AFTER_RESCHED",
)


def inject(text, mode):
    replacements = {
        "value_before_park": ("CJTHREAD_BEFORE_PARK: CJThreadStateHook = 0u32",
            "CJTHREAD_BEFORE_PARK: CJThreadStateHook = 9u32"),
        "value_after_park": ("CJTHREAD_AFTER_PARK: CJThreadStateHook = 1u32",
            "CJTHREAD_AFTER_PARK: CJThreadStateHook = 9u32"),
        "value_before_resched": ("CJTHREAD_BEFORE_RESCHED: CJThreadStateHook = 2u32",
            "CJTHREAD_BEFORE_RESCHED: CJThreadStateHook = 9u32"),
        "value_after_resched": ("CJTHREAD_AFTER_RESCHED: CJThreadStateHook = 3u32",
            "CJTHREAD_AFTER_RESCHED: CJThreadStateHook = 9u32"),
        "value_butt": ("CJTHREAD_STATE_HOOK_BUTT: CJThreadStateHook = 4u32",
            "CJTHREAD_STATE_HOOK_BUTT: CJThreadStateHook = 9u32"),
        "omitted": ("public const CJTHREAD_BEFORE_RESCHED: CJThreadStateHook = 2u32\n", ""),
        "alias64": ("public type CJThreadStateHook = UInt32",
            "public type CJThreadStateHook = UInt64"),
        "alias_signed": ("public type CJThreadStateHook = UInt32",
            "public type CJThreadStateHook = Int32"),
        "initializer": ("public const CJTHREAD_STATE_HOOK_BUTT: CJThreadStateHook = 4u32",
            "public const CJTHREAD_STATE_HOOK_BUTT: CJThreadStateHook = 4u32\n"
            "public let CJTHREAD_STATE_HOOK_RUNTIME = RuntimeInitializer()"),
    }
    if mode == "normal":
        return text
    if mode == "swapped":
        first = "public const CJTHREAD_BEFORE_PARK: CJThreadStateHook = 0u32"
        last = "public const CJTHREAD_STATE_HOOK_BUTT: CJThreadStateHook = 4u32"
        if text.count(first) != 1 or text.count(last) != 1:
            raise ValueError("swap injection anchors absent")
        return text.replace(first, "__STATE_HOOK_SWAP__").replace(last, first).replace(
            "__STATE_HOOK_SWAP__", last)
    old, new = replacements[mode]
    if text.count(old) != 1:
        raise ValueError(f"injection anchor count for {mode}: {text.count(old)}")
    return text.replace(old, new)


def check_source(text):
    errors = []
    if text.count(EXPECTED) != 1:
        errors.append("exact alias/constants block mismatch")
    if text.count(ADJACENCY) != 1:
        errors.append("SchdHook/StateHook/CreateSource adjacency mismatch")
    if len(re.findall(r"^public type CJThreadStateHook\s*=", text, re.MULTILINE)) != 1:
        errors.append("alias count mismatch")
    definitions = re.findall(
        r"^public const (CJTHREAD_(?:BEFORE|AFTER|STATE)[A-Z_]*): "
        r"CJThreadStateHook = (\d+u32)$", text, re.MULTILINE
    )
    expected_definitions = [
        ("CJTHREAD_BEFORE_PARK", "0u32"),
        ("CJTHREAD_AFTER_PARK", "1u32"),
        ("CJTHREAD_BEFORE_RESCHED", "2u32"),
        ("CJTHREAD_AFTER_RESCHED", "3u32"),
        ("CJTHREAD_STATE_HOOK_BUTT", "4u32"),
    ]
    if definitions != expected_definitions:
        errors.append(f"constant inventory/order mismatch: {definitions}")
    start = text.find("public type CJThreadStateHook")
    end = text.find("// CJThread schedule/include/schedule.h:403-410", start)
    if start < 0 or end < 0:
        errors.append("state-hook vocabulary slice absent")
    else:
        target = text[start:end]
        if target != EXPECTED + "\n\n":
            errors.append("state-hook slice contains non-vocabulary production code")
        forbidden = re.compile(
            r"\b(?:func|class|enum|let|var|init|foreign|CFunc|CPointer|VArray|Array|"
            r"HashMap|CJThreadStateHookRegister|SchdCJThreadStateHookFunc|"
            r"schdCJThreadStateHook)\b|@C"
        )
        if forbidden.search(target):
            errors.append("helper, initializer, export, owner, or hook container in target slice")
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
    registration_key = ("CJThread/src/runtime/schedule/src/cjthread.cpp", 1136)
    owner_key = ("CJThread/src/runtime/schedule/include/inner/schedule_impl.h", 212)
    rename_key = ("CJThread/src/base/mid/include/schedule_rename.h", 194)
    store_key = ("CJThread/src/runtime/schedule/src/cjthread.cpp", 1151)
    if inventory_mode == "extra_registration":
        actual[("CJThread/src/runtime/schedule/src/cjthread.cpp", 1129)] = (
            3, "int CJThreadStateHookRegister(SchdCJThreadStateHookFunc, CJThreadStateHook);")
    elif inventory_mode == "missing_registration":
        actual.pop(registration_key, None)
    elif inventory_mode == "missing_owner_bound":
        actual.pop(owner_key, None)
    elif inventory_mode == "rename_spelling":
        occurrences, exact = actual[rename_key]
        actual[rename_key] = (occurrences, exact.replace(
            "CJThreadeStateHookRegister", "CJThreadStateHookRegister"))
    elif inventory_mode == "missing_generic_store":
        actual.pop(store_key, None)
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
    if len(rows) != 15 or sum(row[4] for row in rows) != 21:
        errors.append("inventory row/token count drift")
    platforms = Counter(row[1] for row in rows)
    if platforms != Counter({"all_targets": 14, "cangjie_build_mode": 1}):
        errors.append(f"platform classification drift: {dict(platforms)}")
    for enumerator in POSITION_ENUMERATORS:
        enum_rows = [row for row in rows if enumerator in TOKEN.findall(row[5])]
        if len(enum_rows) != 1 or enum_rows[0][0] != "enumerator_definition":
            errors.append(f"enumerator acquired consumer: {enumerator}")
    sentinel_rows = [row for row in rows if "CJTHREAD_STATE_HOOK_BUTT" in TOKEN.findall(row[5])]
    sentinel_classes = Counter(row[0] for row in sentinel_rows)
    if sentinel_classes != Counter({"enumerator_definition": 1, "owner_array": 1,
            "upper_bound_validation": 1}):
        errors.append(f"sentinel use drift: {dict(sentinel_classes)}")
    for absent_class in ("array_read", "callback_dispatch", "gc_registration", "switch_consumer"):
        if classes.get(absent_class, 0) != 0:
            errors.append(f"unexpected consumer class: {absent_class}")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--runtime-root")
    parser.add_argument("--inventory")
    parser.add_argument("--mode", choices=("normal", "value_before_park", "value_after_park",
        "value_before_resched", "value_after_resched", "value_butt", "swapped", "omitted",
        "alias64", "alias_signed", "initializer"), default="normal")
    parser.add_argument("--inventory-mode", choices=("normal", "extra_registration",
        "missing_registration", "missing_owner_bound", "rename_spelling",
        "missing_generic_store"), default="normal")
    args = parser.parse_args()
    try:
        text = inject(Path(args.source).read_text(encoding="utf-8"), args.mode)
        errors = check_source(text)
        if args.mode == "normal":
            if not args.runtime_root or not args.inventory:
                errors.append("normal mode requires runtime root and inventory")
            else:
                errors.extend(check_inventory(args.runtime_root, args.inventory, args.inventory_mode))
    except (KeyError, OSError, ValueError) as error:
        errors = [str(error)]
    if errors:
        print(f"CJTHREAD_STATE_HOOK_SOURCE FAIL mode={args.mode} "
            f"inventory_mode={args.inventory_mode} error={' ; '.join(errors)}", file=sys.stderr)
        return 1
    print("CJTHREAD_STATE_HOOK_SOURCE alias=1 constants=5 "
        "order=BEFORE_PARK,AFTER_PARK,BEFORE_RESCHED,AFTER_RESCHED,STATE_HOOK_BUTT "
        "typed_u32=5 helpers=0 runtime_initializers=0 inventory_lines=15 "
        "inventory_tokens=21 classifications=11 array_reads=0 callback_dispatches=0 "
        "gc_registrations=0 switch_consumers=0 position_enumerator_consumers=0 "
        "sentinel_bound_uses=2 adjacency=PASS status=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
