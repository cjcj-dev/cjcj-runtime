#!/usr/bin/env python3

import argparse
import re
import subprocess
import sys
from collections import deque
from pathlib import Path

ROOT = "CalleeSavedSetValueRoot"
PROJECT_PREFIX = "_CN12rt.exception"
FORBIDDEN = re.compile(
    r"(?:CJ_)?MCC_New|RawArrayAllocate|StringBuilder|std[.:]core[.:](?:String|Array)|"
    r"ArrayList|HashMap|HashSet|LinkedList|mallocCString|lambda|closure|"
    r"llvm[.]cj[.]throw|Create[A-Za-z0-9_]*Exception|"
    r"(?:^|[^A-Za-z0-9_])(?:malloc|calloc|realloc|free)(?:$|[^A-Za-z0-9_])",
    re.IGNORECASE,
)
IR_DEF = re.compile(r'^define\b.*?@(?:"([^"]+)"|([^\s(]+))\(')
IR_REF = re.compile(r'@(?:"([^"]+)"|([A-Za-z0-9_.$:-]+))')
OBJ_DEF = re.compile(r'^([0-9a-fA-F]+) <(.+)>:$')


class Failure(RuntimeError):
    pass


def parse_ir(path):
    definitions = {}
    current = None
    body = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        match = IR_DEF.match(line)
        if match:
            if current is not None:
                raise Failure(f"nested definition before {current} ended")
            current = match.group(1) or match.group(2)
            body = [line]
        elif current is not None:
            body.append(line)
            if line == "}":
                if current in definitions:
                    raise Failure(f"duplicate IR definition {current}")
                definitions[current] = "\n".join(body)
                current = None
    if current is not None:
        raise Failure(f"unterminated IR definition {current}")
    return definitions


def ir_calls(symbol, body):
    calls = []
    for line in body.splitlines():
        if not re.search(r'\b(?:call|invoke)\b', line):
            continue
        refs = [a or b for a, b in IR_REF.findall(line)]
        if "@llvm.cj.gc.statepoint" in line:
            if len(refs) < 2:
                raise Failure(f"unresolved statepoint in {symbol}")
            target = refs[1]
        else:
            if not refs:
                raise Failure(f"unresolved indirect final call in {symbol}")
            target = refs[0]
        if not target.startswith("llvm."):
            calls.append(target)
    return calls


def objdump(path):
    return subprocess.run(
        ["objdump", "-dr", str(path)], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout


def parse_objects(paths):
    definitions = {}
    for path in paths:
        current = None
        body = []
        for line in objdump(path).splitlines():
            match = OBJ_DEF.match(line)
            if match:
                if current is not None:
                    if current in definitions:
                        raise Failure(f"duplicate object definition {current}")
                    definitions[current] = "\n".join(body)
                current = match.group(2)
                body = [line]
            elif current is not None:
                body.append(line)
        if current is not None:
            if current in definitions:
                raise Failure(f"duplicate object definition {current}")
            definitions[current] = "\n".join(body)
    return definitions


def object_calls(symbol, body):
    calls = []
    indirect = 0
    for line in body.splitlines():
        relocation = re.search(r'R_X86_64_PLT32\s+(.+?)\s*$', line)
        if relocation:
            calls.append(re.sub(r'-0x[0-9a-fA-F]+$', '', relocation.group(1)))
        instruction = re.search(r'\bcall\w*\s+(.+?)\s*$', line)
        if instruction and instruction.group(1).startswith('*'):
            indirect += 1
    if indirect:
        raise Failure(f"unresolved indirect object calls in {symbol}: {indirect}")
    return calls


def traverse(definitions, calls, stage, inject):
    reached = {ROOT}
    queue = deque([ROOT])
    external = set()
    while queue:
        symbol = queue.popleft()
        if symbol not in definitions:
            raise Failure(f"missing reached {stage} definition {symbol}")
        targets = calls(symbol, definitions[symbol])
        if inject and symbol == ROOT:
            targets.append("malloc")
        for target in targets:
            if target in definitions:
                if target not in reached:
                    reached.add(target)
                    queue.append(target)
            elif target.startswith(PROJECT_PREFIX):
                raise Failure(f"missing project {stage} edge {symbol} -> {target}")
            else:
                external.add(target)
    scanned = {name for name in reached if definitions.get(name, "").strip()}
    if reached != scanned:
        raise Failure(f"{stage} reachable/scanned mismatch reached={reached} scanned={scanned}")
    for name in scanned:
        match = FORBIDDEN.search(definitions[name])
        if match:
            raise Failure(f"{stage} forbidden body {name}:{match.group(0)}")
    for name in external:
        if FORBIDDEN.search(name):
            raise Failure(f"{stage} forbidden external {name}")
    return reached, scanned, external


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pre", required=True)
    parser.add_argument("--final", required=True)
    parser.add_argument("--object", action="append", required=True)
    parser.add_argument("--inject-forbidden", action="store_true")
    args = parser.parse_args()
    try:
        pre = parse_ir(args.pre)
        final = parse_ir(args.final)
        objects = parse_objects(args.object)
        if ROOT not in pre or ROOT not in final or ROOT not in objects:
            raise Failure("root missing from pre/final/object stage")
        final_result = traverse(final, ir_calls, "final", args.inject_forbidden)
        object_result = traverse(objects, object_calls, "object", args.inject_forbidden)
        if args.inject_forbidden:
            raise Failure("forbidden injection unexpectedly accepted")
        print(f"CALLEE_FINAL_CLOSURE reachable_defs={len(final_result[0])} scanned_defs={len(final_result[1])} external={len(final_result[2])} status=PASS")
        print(f"CALLEE_OBJECT_CLOSURE reachable_defs={len(object_result[0])} scanned_defs={len(object_result[1])} external={len(object_result[2])} status=PASS")
        print("CALLEE_NOHEAP final_forbidden=0 object_forbidden=0 status=PASS")
        return 0
    except (Failure, OSError, subprocess.CalledProcessError) as error:
        print(f"CALLEE_CLOSURE FAIL reason={error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
