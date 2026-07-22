#!/usr/bin/env python3

import argparse
import re
import subprocess
import sys
from collections import deque
from pathlib import Path

ROOTS = ("MemCommonRoundRoot", "MemCommonIndexRoot")
PREFIXES = ("_CN9rt.common",)
FORBIDDEN = re.compile(
    r"(?:CJ_)?MCC_New|RawArrayAllocate|StringBuilder|std[.:]core[.:](?:String|Array)|"
    r"ArrayList|HashMap|HashSet|LinkedList|mallocCString|lambda|closure|"
    r"llvm[.]cj[.]throw|Create[A-Za-z0-9_]*Exception|"
    r"(?:^|[^A-Za-z0-9_])(?:malloc|calloc|realloc|free)(?:$|[^A-Za-z0-9_])", re.IGNORECASE)
IR_DEF = re.compile(r'^define\b.*?@(?:"([^"]+)"|([^\s(]+))\(')
IR_REF = re.compile(r'@(?:"([^"]+)"|([A-Za-z0-9_.$:-]+))')
OBJ_DEF = re.compile(r'^([0-9a-fA-F]+) <(.+)>:$')

class Failure(RuntimeError): pass

def parse_ir(path):
    definitions, current, body = {}, None, []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        match = IR_DEF.match(line)
        if match:
            if current is not None: raise Failure(f"nested IR definition {current}")
            current, body = match.group(1) or match.group(2), [line]
        elif current is not None:
            body.append(line)
            if line == "}":
                if current in definitions: raise Failure(f"duplicate IR definition {current}")
                definitions[current], current = "\n".join(body), None
    if current is not None: raise Failure(f"unterminated IR definition {current}")
    return definitions

def ir_calls(symbol, body):
    result = []
    for line in body.splitlines():
        if not re.search(r'(?:^|=\s)(?:(?:tail|musttail|notail)\s+)?(?:call|invoke)\b', line): continue
        refs = [a or b for a, b in IR_REF.findall(line)]
        if "@llvm.cj.gc.statepoint" in line:
            if len(refs) < 2: raise Failure(f"unresolved statepoint {symbol}")
            target = refs[1]
        else:
            if not refs: raise Failure(f"unresolved final call {symbol}")
            target = refs[0]
        if not target.startswith("llvm."): result.append(target)
    return result

def parse_objects(paths):
    definitions = {}
    for path in paths:
        output = subprocess.run(["objdump", "-dr", path], check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
        current, body = None, []
        for line in output.splitlines():
            match = OBJ_DEF.match(line)
            if match:
                if current is not None:
                    if current in definitions: raise Failure(f"duplicate object {current}")
                    definitions[current] = "\n".join(body)
                current, body = match.group(2), [line]
            elif current is not None: body.append(line)
        if current is not None:
            if current in definitions: raise Failure(f"duplicate object {current}")
            definitions[current] = "\n".join(body)
    return definitions

def object_calls(symbol, body):
    calls, indirect = [], 0
    for line in body.splitlines():
        relocation = re.search(r'R_X86_64_PLT32\s+(.+?)\s*$', line)
        if relocation: calls.append(re.sub(r'-0x[0-9a-fA-F]+$', '', relocation.group(1)))
        instruction = re.search(r'\bcall\w*\s+(.+?)\s*$', line)
        if instruction and instruction.group(1).startswith('*'): indirect += 1
    if indirect: raise Failure(f"unresolved indirect object calls {symbol}:{indirect}")
    return calls

def traverse(definitions, calls, stage, inject):
    reached, queue, external = set(ROOTS), deque(ROOTS), set()
    while queue:
        symbol = queue.popleft()
        if symbol not in definitions: raise Failure(f"missing reached {stage} definition {symbol}")
        targets = calls(symbol, definitions[symbol])
        if inject and symbol == ROOTS[0]: targets.append("malloc")
        for target in targets:
            if target in definitions:
                if target not in reached: reached.add(target); queue.append(target)
            elif target.startswith(PREFIXES): raise Failure(f"missing project {stage} edge {symbol}->{target}")
            else: external.add(target)
    scanned = {name for name in reached if definitions.get(name, "").strip()}
    if reached != scanned: raise Failure(f"{stage} reachable/scanned mismatch")
    for name in scanned:
        hit = FORBIDDEN.search(definitions[name])
        if hit: raise Failure(f"{stage} forbidden body {name}:{hit.group(0)}")
    for name in external:
        if FORBIDDEN.search(name): raise Failure(f"{stage} forbidden external {name}")
    return reached, scanned, external

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pre", required=True); parser.add_argument("--final", required=True)
    parser.add_argument("--object", action="append", required=True); parser.add_argument("--inject-forbidden", action="store_true")
    args = parser.parse_args()
    try:
        pre, final, objects = parse_ir(args.pre), parse_ir(args.final), parse_objects(args.object)
        for root in ROOTS:
            if root not in pre or root not in final or root not in objects: raise Failure(f"root absent from pre/final/object {root}")
        final_result = traverse(final, ir_calls, "final", args.inject_forbidden)
        object_result = traverse(objects, object_calls, "object", args.inject_forbidden)
        if args.inject_forbidden: raise Failure("negative unexpectedly accepted")
        print(f"MEMCOMMON_FINAL_CLOSURE reachable_defs={len(final_result[0])} scanned_defs={len(final_result[1])} external={len(final_result[2])} status=PASS")
        print(f"MEMCOMMON_OBJECT_CLOSURE reachable_defs={len(object_result[0])} scanned_defs={len(object_result[1])} external={len(object_result[2])} status=PASS")
        print("MEMCOMMON_NOHEAP final_forbidden=0 object_forbidden=0 status=PASS")
        return 0
    except (Failure, OSError, subprocess.CalledProcessError) as error:
        print(f"MEMCOMMON_CLOSURE FAIL reason={error}", file=sys.stderr); return 1

if __name__ == "__main__": sys.exit(main())
