#!/usr/bin/env python3

import argparse
import re
import subprocess
import sys
from collections import deque
from pathlib import Path


ROOTS = (
    "_CN13rwlock.noheap10UnlockReadHv",
    "_CN13rwlock.noheap11UnlockWriteHv",
)
PROJECT_PREFIXES = ("_CN13rwlock.noheap", "_CN7rt.base")
FORBIDDEN = re.compile(
    r"(?:CJ_)?MCC_New|RawArrayAllocate|StringBuilder|std\.core[:.]String|"
    r"std\.core[:.]Array|ArrayList|HashMap|HashSet|LinkedList|mallocCString|"
    r"std[.:]collection|lambda|closure|llvm\.cj\.throw|Create[A-Za-z0-9_]*Exception|"
    r"(?:^|[^A-Za-z0-9_])"
    r"(?:malloc|calloc|realloc|free)(?:$|[^A-Za-z0-9_])",
    re.IGNORECASE,
)
SYMBOL_REF = re.compile(r'@(?:"([^"]+)"|([A-Za-z0-9_.$:-]+))')
IR_DEFINITION = re.compile(r'^define\b.*?@(?:"([^"]+)"|([^\s(]+))\(')
OBJECT_DEFINITION = re.compile(r'^([0-9a-fA-F]+) <(.+)>:$')
RELOCATION = re.compile(r'R_X86_64_(PLT32|PC32)\s+(.+?)\s*$')
CALL_INSTRUCTION = re.compile(
    r'(?:^|\s)(?:(?:tail|musttail|notail)\s+)?(?:call|invoke)\s'
)


class ClosureError(RuntimeError):
    pass


def symbol_refs(text):
    return [quoted or plain for quoted, plain in SYMBOL_REF.findall(text)]


def parse_ir(path):
    text = Path(path).read_text(encoding="utf-8")
    definitions = {}
    counts = {}
    current = None
    body = []
    for line in text.splitlines():
        match = IR_DEFINITION.match(line)
        if match:
            if current is not None:
                raise ClosureError(f"nested IR definition before end of {current}")
            current = match.group(1) or match.group(2)
            body = [line]
            continue
        if current is not None:
            body.append(line)
            if line == "}":
                counts[current] = counts.get(current, 0) + 1
                if current in definitions:
                    raise ClosureError(f"ambiguous duplicate IR definition: {current}")
                definitions[current] = "\n".join(body) + "\n"
                current = None
                body = []
    if current is not None:
        raise ClosureError(f"unterminated IR definition: {current}")
    return text, definitions, counts


def ir_calls(symbol, body):
    calls = []
    for line in body.splitlines():
        if not CALL_INSTRUCTION.search(line):
            continue
        refs = symbol_refs(line)
        if "@llvm.cj.gc.statepoint" in line:
            if len(refs) < 2:
                raise ClosureError(f"unknown statepoint target in {symbol}: {line.strip()}")
            target = refs[1]
        else:
            if not refs:
                raise ClosureError(f"unknown indirect final-BC call in {symbol}: {line.strip()}")
            target = refs[0]
        if target.startswith("llvm."):
            continue
        calls.append(target)
    return calls


def clean_relocation_target(target):
    target = target.strip()
    return re.sub(r'-0x[0-9a-fA-F]+$', '', target)


def objdump(path, option):
    result = subprocess.run(
        ["objdump", option, str(path)], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout


def parse_data_relocations(path):
    data = {}
    section = None
    for line in objdump(path, "-r").splitlines():
        header = re.match(r'^RELOCATION RECORDS FOR \[(.+)\]:$', line)
        if header:
            section = header.group(1)
            continue
        if not line.strip():
            section = None
            continue
        if section != ".data":
            continue
        match = re.match(r'^([0-9a-fA-F]+)\s+R_X86_64_[A-Z0-9_]+\s+(.+?)\s*$', line)
        if match:
            data[int(match.group(1), 16)] = clean_relocation_target(match.group(2))
    return data


def parse_objects(paths):
    definitions = {}
    owners = {}
    data_relocations = {}
    for path in paths:
        path = Path(path)
        data_relocations[path] = parse_data_relocations(path)
        current = None
        body = []
        for line in objdump(path, "-dr").splitlines():
            match = OBJECT_DEFINITION.match(line)
            if match:
                if current is not None:
                    if current in definitions:
                        raise ClosureError(f"ambiguous duplicate object definition: {current}")
                    definitions[current] = "\n".join(body) + "\n"
                    owners[current] = path
                current = match.group(2)
                body = [line]
            elif current is not None:
                body.append(line)
        if current is not None:
            if current in definitions:
                raise ClosureError(f"ambiguous duplicate object definition: {current}")
            definitions[current] = "\n".join(body) + "\n"
            owners[current] = path
    return definitions, owners, data_relocations


def resolve_data_target(expression, relocations, symbol):
    match = re.fullmatch(r'\.data(?:\+0x([0-9a-fA-F]+))?', expression)
    if not match:
        raise ClosureError(f"unknown object data edge in {symbol}: {expression}")
    addend = int(match.group(1) or "0", 16)
    for offset in (addend + 4, addend):
        if offset in relocations:
            target = relocations[offset]
            if target.startswith(".text"):
                raise ClosureError(f"ambiguous object text-slot edge in {symbol}: {target}")
            return target
    raise ClosureError(f"missing object data-slot relocation in {symbol}: {expression}")


def object_calls(symbol, body, relocations, definitions):
    calls = []
    indirect_calls = 0
    resolved_indirect = 0
    lines = body.splitlines()
    for line in lines:
        relocation = RELOCATION.search(line)
        if relocation:
            kind, raw_target = relocation.groups()
            target = clean_relocation_target(raw_target)
            if target.startswith(".data"):
                resolved = resolve_data_target(target, relocations, symbol)
                calls.append(resolved)
                if resolved == "CJ_MCC_HandleSafepoint":
                    resolved_indirect += 1
            elif target.startswith(".cjmetadata") or target.startswith(".rodata"):
                continue
            elif kind == "PLT32":
                calls.append(target)
        instruction = re.search(r'\bcall\w*\s+(.+?)\s*$', line)
        if not instruction:
            continue
        operand = instruction.group(1)
        if operand.startswith('*'):
            indirect_calls += 1
            continue
        direct = re.search(r'<([^>]+)>', operand)
        if not direct:
            continue
        target = direct.group(1)
        if "+0x" in target:
            base = target.split("+0x", 1)[0]
            if base != symbol:
                raise ClosureError(f"unknown resolved object call in {symbol}: {target}")
        elif target in definitions:
            calls.append(target)
        else:
            raise ClosureError(f"missing resolved object target in {symbol}: {target}")
    if indirect_calls != resolved_indirect:
        raise ClosureError(
            f"ambiguous indirect object calls in {symbol}: calls={indirect_calls} "
            f"resolved_safepoints={resolved_indirect}"
        )
    return calls


def load_manifest(path):
    manifest = {"final": {}, "object": {}}
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 3 or fields[0] not in manifest:
            raise ClosureError(f"invalid manifest line {number}: {line}")
        stage, symbol, classification = fields
        if symbol in manifest[stage]:
            raise ClosureError(f"duplicate manifest symbol for {stage}: {symbol}")
        manifest[stage][symbol] = classification
    if not manifest["final"] or not manifest["object"]:
        raise ClosureError("empty stage manifest")
    return manifest


def check_forbidden(stage, bodies, external):
    hits = []
    for symbol, body in bodies.items():
        for match in FORBIDDEN.finditer(body):
            hits.append(f"{symbol}:{match.group(0).strip()}")
    for symbol in external:
        if FORBIDDEN.search(symbol):
            hits.append(f"external:{symbol}")
    if hits:
        raise ClosureError(f"{stage} forbidden edge/body: {hits[0]}")


def call_target(line):
    refs = symbol_refs(line)
    if "@llvm.cj.gc.statepoint" in line:
        return refs[1] if len(refs) > 1 else None
    return refs[0] if refs else None


def check_as1_escapes(bodies):
    allowed_consumers = {
        "cj_atomic_i32_cas", "cj_atomic_i32_load", "cj_atomic_i32_store",
        "cj_atomic_i32_fetch_sub",
    }
    escape_count = 0
    variable = re.compile(r'%[A-Za-z0-9_.$-]+')
    for symbol, body in bodies.items():
        lines = body.splitlines()
        tainted = set()
        for line in lines:
            if "addrspacecast" not in line or "addrspace(1)" not in line:
                continue
            if not re.search(r'addrspacecast.*addrspace\(1\).*\bto\b(?![^\n]*addrspace\(1\))', line):
                continue
            match = re.match(r'\s*(%[A-Za-z0-9_.$-]+)\s*=', line)
            if not match:
                raise ClosureError(f"unbound AS1-to-AS0 cast in {symbol}: {line.strip()}")
            tainted.add(match.group(1))
            escape_count += 1
        changed = True
        while changed:
            changed = False
            for line in lines:
                match = re.match(r'\s*(%[A-Za-z0-9_.$-]+)\s*=\s*(.*)$', line)
                if not match or match.group(1) in tainted:
                    continue
                rhs = match.group(2)
                if any(name in variable.findall(rhs) for name in tainted) and re.match(
                    r'(?:bitcast|getelementptr|phi|select)\b', rhs
                ):
                    tainted.add(match.group(1))
                    changed = True
        for line in lines:
            used = tainted.intersection(variable.findall(line))
            if not used:
                continue
            lhs = re.match(r'\s*(%[A-Za-z0-9_.$-]+)\s*=', line)
            if lhs and lhs.group(1) in tainted:
                continue
            if CALL_INSTRUCTION.search(line):
                target = call_target(line)
                if target in allowed_consumers or (target and target.startswith("llvm.lifetime.")):
                    continue
            raise ClosureError(f"illegal AS1-to-AS0 use in {symbol}: {line.strip()}")
    return escape_count


def split_ir_blocks(body):
    blocks = {"entry": []}
    current = "entry"
    for line in body.splitlines()[1:-1]:
        label = re.match(r'^([A-Za-z$._][A-Za-z0-9$._-]*):', line)
        if label:
            current = label.group(1)
            blocks.setdefault(current, [])
        else:
            blocks[current].append(line)
    successors = {name: set() for name in blocks}
    for name, lines in blocks.items():
        for line in lines:
            for quoted, plain in re.findall(r'label %(?:"([^"]+)"|([A-Za-z0-9$._-]+))', line):
                successors[name].add(quoted or plain)
    return blocks, successors


def check_unlock_order(definitions):
    read_symbol = "_CN7rt.base6RwLock10UnlockReadHv"
    write_symbol = "_CN7rt.base6RwLock11UnlockWriteHv"
    if read_symbol not in definitions or write_symbol not in definitions:
        raise ClosureError("missing production unlock definition")
    read_body = definitions[read_symbol]
    if read_body.count("@cj_atomic_i32_fetch_sub") != 1 or read_body.count("@abort") != 1:
        raise ClosureError("invalid UnlockRead fetch-sub/abort multiplicity")
    if read_body.index("@cj_atomic_i32_fetch_sub") > read_body.index("@abort"):
        raise ClosureError("UnlockRead abort precedes fetch-sub")
    write_body = definitions[write_symbol]
    if write_body.count("@RtFatal") != 1 or write_body.count("@cj_atomic_i32_store") != 1:
        raise ClosureError("invalid UnlockWrite fatal/store multiplicity")
    blocks, successors = split_ir_blocks(write_body)
    fatal_blocks = [name for name, lines in blocks.items() if any("@RtFatal" in line for line in lines)]
    store_blocks = {name for name, lines in blocks.items() if any("@cj_atomic_i32_store" in line for line in lines)}
    if len(fatal_blocks) != 1 or len(store_blocks) != 1:
        raise ClosureError("ambiguous UnlockWrite failure/success blocks")
    queue = deque(fatal_blocks)
    seen = set(fatal_blocks)
    while queue:
        block = queue.popleft()
        for successor in successors.get(block, ()):
            if successor not in seen:
                seen.add(successor)
                queue.append(successor)
    if seen.intersection(store_blocks):
        raise ClosureError("UnlockWrite release-store reachable from failure block")


def traverse_final(definitions, manifest, mode):
    reached = set(ROOTS)
    queue = deque(ROOTS)
    external = set()
    while queue:
        symbol = queue.popleft()
        body = definitions.get(symbol)
        if body is None:
            raise ClosureError(f"missing reached final definition: {symbol}")
        calls = ir_calls(symbol, body)
        if mode == "forbidden" and symbol == ROOTS[0]:
            calls.append("malloc")
        for target in calls:
            if target in definitions:
                if target not in reached:
                    reached.add(target)
                    queue.append(target)
            elif target.startswith(PROJECT_PREFIXES):
                raise ClosureError(f"missing project final edge: {symbol} -> {target}")
            else:
                external.add(target)
    scanned = {symbol for symbol in reached if symbol in definitions and definitions[symbol].strip()}
    if mode == "missing":
        scanned.remove(sorted(scanned)[-1])
    if mode == "extra":
        extra = next((name for name in definitions if name not in reached), "_CN7rt.baseUnexpectedBody")
        scanned.add(extra)
    missing = reached - scanned
    extra = scanned - reached
    if missing or extra:
        raise ClosureError(f"final reached/scanned mismatch missing={sorted(missing)} extra={sorted(extra)}")
    unknown = external - set(manifest)
    unused = set(manifest) - external
    if unknown or unused:
        raise ClosureError(f"final manifest mismatch unknown={sorted(unknown)} unused={sorted(unused)}")
    bodies = {symbol: definitions[symbol] for symbol in scanned}
    check_forbidden("final", bodies, external)
    escapes = check_as1_escapes(bodies)
    return reached, scanned, external, escapes


def traverse_object(definitions, owners, data_relocations, manifest, mode):
    native_definitions = {symbol for symbol in manifest if symbol in definitions}
    project_definitions = {
        symbol for symbol in definitions
        if symbol.startswith(PROJECT_PREFIXES) or symbol in native_definitions
    }
    reached = set(ROOTS)
    queue = deque(ROOTS)
    external = set()
    while queue:
        symbol = queue.popleft()
        if symbol not in project_definitions:
            raise ClosureError(f"missing reached object definition: {symbol}")
        calls = object_calls(symbol, definitions[symbol], data_relocations[owners[symbol]], definitions)
        if mode == "forbidden" and symbol == ROOTS[0]:
            calls.append("malloc")
        for target in calls:
            if target in project_definitions:
                if target not in reached:
                    reached.add(target)
                    queue.append(target)
            elif target.startswith(PROJECT_PREFIXES):
                raise ClosureError(f"missing project object edge: {symbol} -> {target}")
            else:
                external.add(target)
    scanned = {symbol for symbol in reached if definitions.get(symbol, "").strip()}
    if mode == "missing":
        scanned.remove(sorted(scanned)[-1])
    if mode == "extra":
        extra = next((name for name in project_definitions if name not in reached), "_CN7rt.baseUnexpectedBody")
        scanned.add(extra)
    missing = reached - scanned
    extra = scanned - reached
    if missing or extra:
        raise ClosureError(f"object reached/scanned mismatch missing={sorted(missing)} extra={sorted(extra)}")
    exercised = external.union(native_definitions.intersection(reached))
    unknown = external - set(manifest)
    unused = set(manifest) - exercised
    if unknown or unused:
        raise ClosureError(f"object manifest mismatch unknown={sorted(unknown)} unused={sorted(unused)}")
    bodies = {symbol: definitions[symbol] for symbol in scanned}
    check_forbidden("object", bodies, external)
    return reached, scanned, external, exercised


def require_root_counts(pre_counts, final_counts, linked_counts, object_definitions):
    for root in ROOTS:
        if pre_counts.get(root, 0) != 1:
            raise ClosureError(f"pre-opt root count for {root}: {pre_counts.get(root, 0)}")
        if final_counts.get(root, 0) != 1 or linked_counts.get(root, 0) != 1:
            raise ClosureError(
                f"final root count for {root}: file={final_counts.get(root, 0)} "
                f"linked={linked_counts.get(root, 0)}"
            )
        if int(root in object_definitions) != 1:
            raise ClosureError(f"object root count for {root}: {int(root in object_definitions)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pre-ll", required=True)
    parser.add_argument("--root-final-ll", required=True)
    parser.add_argument("--linked-final-ll", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--object", action="append", required=True)
    parser.add_argument("--mode", choices=("normal", "missing", "extra", "forbidden"), default="normal")
    args = parser.parse_args()

    try:
        _, _, pre_counts = parse_ir(args.pre_ll)
        _, _, root_final_counts = parse_ir(args.root_final_ll)
        linked_text, final_definitions, linked_counts = parse_ir(args.linked_final_ll)
        object_definitions, owners, data_relocations = parse_objects(args.object)
        manifest = load_manifest(args.manifest)
        require_root_counts(pre_counts, root_final_counts, linked_counts, object_definitions)
        if '[47 x i8] c"Check failed: lockCount.load() == WRITE_LOCKED\\00"' not in linked_text:
            raise ClosureError("exact static UnlockWrite CHECK diagnostic absent from linked final BC")
        check_unlock_order(final_definitions)
        final = traverse_final(final_definitions, manifest["final"], args.mode)
        obj = traverse_object(
            object_definitions, owners, data_relocations, manifest["object"], args.mode
        )
        if args.mode != "normal":
            raise ClosureError(f"fault injection unexpectedly accepted: {args.mode}")
        print("RWLOCK_ROOTS pre=2 final=2 object=2 each=1 status=PASS")
        print(
            f"RWLOCK_FINAL_CLOSURE reached={len(final[0])} scanned={len(final[1])} "
            f"external={len(final[2])} as1_to_as0={final[3]} missing=0 extra=0 status=PASS"
        )
        print(
            f"RWLOCK_OBJECT_CLOSURE reached={len(obj[0])} scanned={len(obj[1])} "
            f"external={len(obj[2])} missing=0 extra=0 status=PASS"
        )
        print(
            f"RWLOCK_MANIFEST final={len(final[2])}/{len(manifest['final'])} "
            f"object={len(obj[3])}/{len(manifest['object'])} unused=0 status=PASS"
        )
        print("RWLOCK_UNLOCK_ORDER fetch_sub_before_abort=PASS failure_to_store=UNREACHABLE status=PASS")
        print("RWLOCK_NOHEAP final_forbidden=0 object_forbidden=0 status=PASS")
        return 0
    except (ClosureError, OSError, subprocess.CalledProcessError) as error:
        print(f"RWLOCK_CLOSURE FAIL mode={args.mode} reason={error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
