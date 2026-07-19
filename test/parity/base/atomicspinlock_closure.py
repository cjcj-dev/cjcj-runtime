#!/usr/bin/env python3

import argparse
import re
import subprocess
import sys
from collections import defaultdict, deque
from pathlib import Path


ROOTS = (
    "_CN21atomicspinlock.noheap9ConstructHv",
    "_CN21atomicspinlock.noheap4LockHPRN7rt.base14AtomicSpinLockE",
    "_CN21atomicspinlock.noheap6UnlockHPRN7rt.base14AtomicSpinLockE",
    "_CN21atomicspinlock.noheap7TryLockHPRN7rt.base14AtomicSpinLockE",
)
PRODUCTION = {
    "construct": "_CN7rt.base14AtomicSpinLock6<init>Hv",
    "lock": "_CN7rt.base4LockHPRNY_14AtomicSpinLockE",
    "unlock": "_CN7rt.base6UnlockHPRNY_14AtomicSpinLockE",
    "try": "_CN7rt.base7TryLockHPRNY_14AtomicSpinLockE",
}
NATIVE = ("cj_atomic_flag_test_and_set", "cj_atomic_flag_clear")
PROJECT_PREFIXES = ("_CN21atomicspinlock.noheap", "_CN7rt.base", "_CG")
FORBIDDEN = re.compile(
    r"(?:CJ_)?MCC_New|RawArrayAllocate|Create[A-Za-z0-9_]*Exception|"
    r"llvm\.cj\.(?:malloc|gcwrite|throw)|ThrowException|StringBuilder|"
    r"std[.:]collection|ArrayList|HashMap|HashSet|LinkedList|mallocCString|"
    r"(?:^|[^A-Za-z0-9_])(?:malloc|calloc|realloc|free)(?:$|[^A-Za-z0-9_])",
    re.IGNORECASE,
)
SAFEPOINT = re.compile(r"CJ_MCC_(?:HandleSafepoint|StackCheck|StackGrowStub)")
SYMBOL_REF = re.compile(r'@(?:"([^"]+)"|([A-Za-z0-9_.$:-]+))')
IR_DEFINITION = re.compile(r'^define\b.*?@(?:"([^"]+)"|([^\s(]+))\(')
OBJECT_DEFINITION = re.compile(r'^([0-9a-fA-F]+) <(.+)>:$')
RELOCATION = re.compile(r'R_X86_64_(PLT32|PC32)\s+(.+?)\s*$')
CALL_INSTRUCTION = re.compile(r'(?:^|\s)(?:(?:tail|musttail|notail)\s+)?(?:call|invoke)\s')


class ClosureError(RuntimeError):
    pass


def symbol_refs(text):
    return [quoted or plain for quoted, plain in SYMBOL_REF.findall(text)]


def parse_ir(path):
    text = Path(path).read_text(encoding="utf-8")
    definitions = {}
    counts = defaultdict(int)
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
                counts[current] += 1
                if current in definitions:
                    raise ClosureError(f"duplicate linked IR definition: {current}")
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
                raise ClosureError(f"unknown indirect IR call in {symbol}: {line.strip()}")
            target = refs[0]
        if target.startswith("llvm."):
            continue
        calls.append(target)
    return calls


def initializers(definitions):
    return {symbol for symbol in definitions if symbol.startswith("_CG")}


def load_manifest(path):
    manifest = {"root": {}, "pre": {}, "final": {}, "object": {}}
    for number, raw in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 3 or fields[0] not in manifest:
            raise ClosureError(f"invalid manifest line {number}: {line}")
        stage, symbol, classification = fields
        if symbol in manifest[stage]:
            raise ClosureError(f"duplicate manifest symbol for {stage}: {symbol}")
        manifest[stage][symbol] = classification
    if set(manifest["root"]) != set(ROOTS):
        raise ClosureError(
            f"root manifest mismatch missing={sorted(set(ROOTS) - set(manifest['root']))} "
            f"extra={sorted(set(manifest['root']) - set(ROOTS))}"
        )
    if not all(manifest[stage] for stage in ("pre", "final", "object")):
        raise ClosureError("empty external stage manifest")
    return manifest


def check_forbidden(stage, bodies, external, mode):
    if mode == "forbidden":
        external = set(external)
        external.add("MCC_NewObject")
    for symbol, body in bodies.items():
        match = FORBIDDEN.search(body)
        if match:
            raise ClosureError(f"{stage} forbidden body {symbol}: {match.group(0).strip()}")
    for symbol in external:
        if FORBIDDEN.search(symbol):
            raise ClosureError(f"{stage} forbidden external: {symbol}")


def check_manifest(stage, external, expected):
    unknown = set(external) - set(expected)
    unused = set(expected) - set(external)
    if unknown or unused:
        raise ClosureError(
            f"{stage} manifest mismatch unknown={sorted(unknown)} unused={sorted(unused)}"
        )


def traverse_ir(stage, definitions, manifest, mode):
    seeds = set(ROOTS).union(initializers(definitions))
    reached = set(seeds)
    queue = deque(sorted(seeds))
    external = set()
    while queue:
        symbol = queue.popleft()
        body = definitions.get(symbol)
        if body is None:
            raise ClosureError(f"{stage} missing reached definition: {symbol}")
        for target in ir_calls(symbol, body):
            if target in definitions:
                if target not in reached:
                    reached.add(target)
                    queue.append(target)
            elif target.startswith(PROJECT_PREFIXES):
                raise ClosureError(f"{stage} missing project edge: {symbol} -> {target}")
            else:
                external.add(target)
    scanned = {symbol for symbol in reached if definitions.get(symbol, "").strip()}
    if mode == "missing":
        scanned.remove(sorted(scanned)[-1])
    elif mode == "extra":
        extra = next((symbol for symbol in definitions if symbol not in reached), "unexpected.definition")
        scanned.add(extra)
    missing = reached - scanned
    extra = scanned - reached
    if missing or extra:
        raise ClosureError(f"{stage} reached/scanned mismatch missing={sorted(missing)} extra={sorted(extra)}")
    check_manifest(stage, external, manifest)
    bodies = {symbol: definitions[symbol] for symbol in scanned}
    check_forbidden(stage, bodies, external, mode)
    safepoints = sum(len(SAFEPOINT.findall(body)) for body in bodies.values())
    safepoints += sum(1 for symbol in external if SAFEPOINT.search(symbol))
    return reached, scanned, external, seeds, safepoints


def clean_relocation_target(target):
    return re.sub(r'-0x[0-9a-fA-F]+$', '', target.strip())


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
    symbols = defaultdict(list)
    relocations = {}
    for raw_path in paths:
        path = Path(raw_path)
        relocations[path] = parse_data_relocations(path)
        current = None
        body = []
        for line in objdump(path, "-dr").splitlines():
            match = OBJECT_DEFINITION.match(line)
            if match:
                if current is not None:
                    key = (path, current)
                    definitions[key] = "\n".join(body) + "\n"
                    symbols[current].append(key)
                current = match.group(2)
                body = [line]
            elif current is not None:
                body.append(line)
        if current is not None:
            key = (path, current)
            definitions[key] = "\n".join(body) + "\n"
            symbols[current].append(key)
    return definitions, symbols, relocations


def resolve_object_symbol(owner, symbol, symbols):
    same_owner = [key for key in symbols.get(symbol, ()) if key[0] == owner]
    if len(same_owner) == 1:
        return same_owner[0]
    candidates = symbols.get(symbol, ())
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) > 1:
        raise ClosureError(f"ambiguous object target {symbol}: {[str(key[0]) for key in candidates]}")
    return None


def resolve_data_target(expression, relocations, symbol):
    match = re.fullmatch(r'\.data(?:\+0x([0-9a-fA-F]+))?', expression)
    if not match:
        raise ClosureError(f"unknown object data edge in {symbol}: {expression}")
    addend = int(match.group(1) or "0", 16)
    for offset in (addend + 4, addend):
        if offset in relocations:
            return relocations[offset]
    raise ClosureError(f"missing object data-slot relocation in {symbol}: {expression}")


def object_calls(key, body, relocations, definitions, symbols):
    owner, symbol = key
    calls = []
    indirect = 0
    resolved_indirect = 0
    for line in body.splitlines():
        relocation = RELOCATION.search(line)
        if relocation:
            kind, raw_target = relocation.groups()
            target = clean_relocation_target(raw_target)
            if target.startswith(".data"):
                target = resolve_data_target(target, relocations[owner], symbol)
                calls.append(target)
                if target == "CJ_MCC_HandleSafepoint":
                    resolved_indirect += 1
            elif target.startswith((".cjmetadata", ".rodata", ".text")):
                pass
            elif kind == "PLT32":
                calls.append(target)
        instruction = re.search(r'\bcall\w*\s+(.+?)\s*$', line)
        if not instruction:
            continue
        operand = instruction.group(1)
        if operand.startswith('*'):
            indirect += 1
            continue
        direct = re.search(r'<([^>]+)>', operand)
        if not direct:
            continue
        target = direct.group(1)
        if "+0x" in target:
            base = target.split("+0x", 1)[0]
            if base != symbol:
                raise ClosureError(f"unknown resolved object call in {symbol}: {target}")
        elif resolve_object_symbol(owner, target, symbols) is not None:
            calls.append(target)
        else:
            raise ClosureError(f"missing resolved object target in {symbol}: {target}")
    if indirect != resolved_indirect:
        raise ClosureError(
            f"ambiguous indirect object calls in {symbol}: calls={indirect} "
            f"resolved_safepoints={resolved_indirect}"
        )
    return calls


def traverse_objects(definitions, symbols, relocations, manifest, mode):
    seeds = []
    for root in ROOTS:
        candidates = symbols.get(root, ())
        if len(candidates) != 1:
            raise ClosureError(f"object root count for {root}: {len(candidates)}")
        seeds.append(candidates[0])
    seeds.extend(key for key in definitions if key[1].startswith("_CG"))
    reached = set(seeds)
    queue = deque(seeds)
    external = set()
    while queue:
        key = queue.popleft()
        for target in object_calls(key, definitions[key], relocations, definitions, symbols):
            target_key = resolve_object_symbol(key[0], target, symbols)
            if target_key is not None:
                if target_key not in reached:
                    reached.add(target_key)
                    queue.append(target_key)
            elif target.startswith(PROJECT_PREFIXES) or target in NATIVE:
                raise ClosureError(f"object missing project/native edge: {key[1]} -> {target}")
            else:
                external.add(target)
    scanned = {key for key in reached if definitions.get(key, "").strip()}
    if mode == "missing":
        scanned.remove(sorted(scanned, key=lambda item: (str(item[0]), item[1]))[-1])
    elif mode == "extra":
        extra = next((key for key in definitions if key not in reached), (Path("extra.o"), "extra"))
        scanned.add(extra)
    missing = reached - scanned
    extra = scanned - reached
    if missing or extra:
        raise ClosureError(f"object reached/scanned mismatch missing={len(missing)} extra={len(extra)}")
    check_manifest("object", external, manifest)
    bodies = {f"{key[0].name}:{key[1]}": definitions[key] for key in scanned}
    check_forbidden("object", bodies, external, mode)
    native_reached = {symbol for symbol in NATIVE if any(key[1] == symbol for key in reached)}
    if native_reached != set(NATIVE):
        raise ClosureError(f"native bridge closure mismatch: {sorted(native_reached)}")
    safepoints = sum(len(SAFEPOINT.findall(body)) for body in bodies.values())
    safepoints += sum(1 for symbol in external if SAFEPOINT.search(symbol))
    return reached, scanned, external, set(seeds), native_reached, safepoints


def require_root_counts(pre_counts, final_counts):
    for root in ROOTS:
        if pre_counts.get(root, 0) != 1 or final_counts.get(root, 0) != 1:
            raise ClosureError(
                f"IR root count for {root}: pre={pre_counts.get(root, 0)} "
                f"final={final_counts.get(root, 0)}"
            )


def check_atomic_contract(pre_definitions, final_definitions, object_definitions):
    for stage, definitions in (("pre", pre_definitions), ("final", final_definitions)):
        for symbol in PRODUCTION.values():
            if symbol not in definitions:
                raise ClosureError(f"{stage} missing production definition: {symbol}")
        lock = definitions[PRODUCTION["lock"]]
        unlock = definitions[PRODUCTION["unlock"]]
        attempt = definitions[PRODUCTION["try"]]
        construct = definitions[PRODUCTION["construct"]]
        if lock.count("@cj_atomic_flag_test_and_set") != 1 or lock.count("br i1") < 1:
            raise ClosureError(f"{stage} Lock is not one-call looping test-and-set")
        if unlock.count("@cj_atomic_flag_clear") != 1:
            raise ClosureError(f"{stage} Unlock clear multiplicity mismatch")
        if attempt.count("@cj_atomic_flag_test_and_set") != 1 or "@cj_atomic_flag_clear" in attempt:
            raise ClosureError(f"{stage} TryLock operation multiplicity mismatch")
        if not re.search(r'store i8 0,', construct):
            raise ClosureError(f"{stage} constructor clear store absent")
    native_bodies = defaultdict(list)
    for key, body in object_definitions.items():
        if key[1] in NATIVE:
            native_bodies[key[1]].append(body)
    if any(len(native_bodies[symbol]) != 1 for symbol in NATIVE):
        raise ClosureError("atomic bridge object definition multiplicity mismatch")
    if "xchg" not in native_bodies[NATIVE[0]][0]:
        raise ClosureError("atomic test-and-set object is not an exchange")
    if re.search(r'\bcall\w*\b', native_bodies[NATIVE[0]][0]):
        raise ClosureError("atomic test-and-set object retained a call")
    if not re.search(r'\bmovb?\b', native_bodies[NATIVE[1]][0]):
        raise ClosureError("atomic clear object store absent")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pre-ll", required=True)
    parser.add_argument("--final-ll", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--object", action="append", required=True)
    parser.add_argument("--mode", choices=("normal", "missing", "extra", "forbidden"), default="normal")
    args = parser.parse_args()

    try:
        _, pre_definitions, pre_counts = parse_ir(args.pre_ll)
        _, final_definitions, final_counts = parse_ir(args.final_ll)
        object_definitions, object_symbols, object_relocations = parse_objects(args.object)
        manifest = load_manifest(args.manifest)
        require_root_counts(pre_counts, final_counts)
        check_atomic_contract(pre_definitions, final_definitions, object_definitions)
        pre = traverse_ir("pre", pre_definitions, manifest["pre"], args.mode)
        final = traverse_ir("final", final_definitions, manifest["final"], args.mode)
        obj = traverse_objects(
            object_definitions, object_symbols, object_relocations, manifest["object"], args.mode
        )
        if args.mode != "normal":
            raise ClosureError(f"fault injection unexpectedly accepted: {args.mode}")
        print(
            f"ATOMICSPINLOCK_ROOTS fixed=4 pre_initializers={len(pre[3]) - 4} "
            f"final_initializers={len(final[3]) - 4} object_initializers={len(obj[3]) - 4} "
            "each_fixed_root=1 status=PASS"
        )
        print(
            f"ATOMICSPINLOCK_PRE_CLOSURE reached_defs={len(pre[0])} scanned_defs={len(pre[1])} "
            f"external={len(pre[2])} safepoint_refs={pre[4]} status=PASS"
        )
        print(
            f"ATOMICSPINLOCK_FINAL_CLOSURE reached_defs={len(final[0])} scanned_defs={len(final[1])} "
            f"external={len(final[2])} safepoint_refs={final[4]} status=PASS"
        )
        print(
            f"ATOMICSPINLOCK_OBJECT_CLOSURE reached_defs={len(obj[0])} scanned_defs={len(obj[1])} "
            f"external={len(obj[2])} native_defs={len(obj[4])} safepoint_refs={obj[5]} status=PASS"
        )
        print(
            "ATOMICSPINLOCK_NOHEAP forbidden_alloc=0 forbidden_barrier=0 "
            "forbidden_exception=0 forbidden_throw=0 status=PASS"
        )
    except (ClosureError, OSError, subprocess.CalledProcessError) as error:
        print(f"ATOMICSPINLOCK_CLOSURE FAIL mode={args.mode} error={error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
