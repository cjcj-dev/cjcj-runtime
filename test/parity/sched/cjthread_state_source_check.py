#!/usr/bin/env python3

import argparse
import re
import sys
from pathlib import Path


EXPECTED = """public type LuaCJThreadState = Int32
public const LUA_CJTHREAD_INIT: LuaCJThreadState = 0
public const LUA_CJTHREAD_SUSPENDING: LuaCJThreadState = 1
public const LUA_CJTHREAD_RUNNING: LuaCJThreadState = 2
public const LUA_CJTHREAD_DONE: LuaCJThreadState = 3"""


def inject(text, mode):
    replacements = {
        "value_init": ("LUA_CJTHREAD_INIT: LuaCJThreadState = 0", "LUA_CJTHREAD_INIT: LuaCJThreadState = 9"),
        "value_suspending": ("LUA_CJTHREAD_SUSPENDING: LuaCJThreadState = 1", "LUA_CJTHREAD_SUSPENDING: LuaCJThreadState = 9"),
        "value_running": ("LUA_CJTHREAD_RUNNING: LuaCJThreadState = 2", "LUA_CJTHREAD_RUNNING: LuaCJThreadState = 9"),
        "value_done": ("LUA_CJTHREAD_DONE: LuaCJThreadState = 3", "LUA_CJTHREAD_DONE: LuaCJThreadState = 9"),
        "alias64": ("public type LuaCJThreadState = Int32", "public type LuaCJThreadState = Int64"),
        "omitted": ("public const LUA_CJTHREAD_RUNNING: LuaCJThreadState = 2\n", ""),
        "initializer": ("public const LUA_CJTHREAD_DONE: LuaCJThreadState = 3",
            "public const LUA_CJTHREAD_DONE: LuaCJThreadState = 3\npublic let LUA_CJTHREAD_STATE_RUNTIME = RuntimeInitializer()"),
    }
    if mode == "normal":
        return text
    if mode == "swapped":
        first = "public const LUA_CJTHREAD_INIT: LuaCJThreadState = 0"
        last = "public const LUA_CJTHREAD_DONE: LuaCJThreadState = 3"
        if text.count(first) != 1 or text.count(last) != 1:
            raise ValueError("swap injection anchors absent")
        return text.replace(first, "__STATE_SWAP__").replace(last, first).replace("__STATE_SWAP__", last)
    old, new = replacements[mode]
    if text.count(old) != 1:
        raise ValueError(f"injection anchor count for {mode}: {text.count(old)}")
    return text.replace(old, new)


def check(text):
    errors = []
    if text.count(EXPECTED) != 1:
        errors.append("exact alias/constants block mismatch")
    if len(re.findall(r"^public type LuaCJThreadState\s*=", text, re.MULTILINE)) != 1:
        errors.append("alias count mismatch")
    definitions = re.findall(r"^public const (LUA_CJTHREAD_[A-Z]+): LuaCJThreadState = (-?\d+)$", text, re.MULTILINE)
    expected_definitions = [
        ("LUA_CJTHREAD_INIT", "0"),
        ("LUA_CJTHREAD_SUSPENDING", "1"),
        ("LUA_CJTHREAD_RUNNING", "2"),
        ("LUA_CJTHREAD_DONE", "3"),
    ]
    if definitions != expected_definitions:
        errors.append(f"constant inventory/order mismatch: {definitions}")
    if text.count("public var state: LuaCJThreadState") != 1:
        errors.append("LuaCJThread state alias use mismatch")
    if text.count("state = LUA_CJTHREAD_INIT") != 1:
        errors.append("LuaCJThread initial state mismatch")
    start = text.find("public type LuaCJThreadState")
    end = text.find("// CJThread schedule/include/inner/gas", start)
    if start < 0 or end < 0:
        errors.append("state vocabulary slice absent")
    else:
        target = text[start:end]
        if re.search(r"\b(?:func|class|enum|let|var)\b", target):
            errors.append("helper, enum object, or runtime initializer in target slice")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--mode", choices=("normal", "value_init", "value_suspending",
        "value_running", "value_done", "swapped", "omitted", "alias64", "initializer"),
        default="normal")
    args = parser.parse_args()
    try:
        text = inject(Path(args.source).read_text(encoding="utf-8"), args.mode)
        errors = check(text)
    except (OSError, ValueError) as error:
        errors = [str(error)]
    if errors:
        print(f"CJTHREAD_STATE_SOURCE FAIL mode={args.mode} error={' ; '.join(errors)}", file=sys.stderr)
        return 1
    print("CJTHREAD_STATE_SOURCE alias=1 constants=4 order=INIT,SUSPENDING,RUNNING,DONE "
        "helpers=0 runtime_initializers=0 field_alias=1 initializer=INIT status=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
