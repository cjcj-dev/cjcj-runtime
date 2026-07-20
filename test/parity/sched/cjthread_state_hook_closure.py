#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import re
import sys
from collections import deque
from pathlib import Path


ENGINE_PATH = Path(__file__).parents[1] / "base" / "atomicspinlock_closure.py"
SPEC = importlib.util.spec_from_file_location("cjthread_state_hook_closure_engine", ENGINE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load closure engine: {ENGINE_PATH}")
ENGINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENGINE)

ROOT_IMPL = "_CN24cjthreadstatehook.noheap25CJRT_CJThreadStateHookRunHv"
ENGINE.ROOTS = (ROOT_IMPL,)
ENGINE.PRODUCTION = {}
ENGINE.NATIVE = (
    "CJThreadStateHookObserve",
    "CJThreadStateHookCallback0",
    "CJThreadStateHookCallback1",
    "CJThreadStateHookCallback2",
    "CJThreadStateHookCallback3",
)
ENGINE.PROJECT_PREFIXES = (
    "_CN24cjthreadstatehook.noheap", "_CN8rt.sched",
    "_CGP24cjthreadstatehook.noheap", "_CGP8rt.sched",
)
ENGINE.BARRIER_INJECTIONS = {
    "barrier_pre": ("pre", "MCC_WriteRefField"),
    "barrier_final": ("final", "CJ_MCC_AtomicSwapReference"),
    "barrier_object": ("object", "CJ_MCC_WriteGenericPayload"),
    "allocation_pre": ("pre", "MCC_NewObject"),
    "allocation_final": ("final", "CJ_MCC_NewObject"),
    "allocation_object": ("object", "MCC_NewArray"),
}
OBJECT_RELOCATION = re.compile(
    r"R_X86_64_(PLT32|PC32|GOTPCREL|REX_GOTPCRELX)\s+(.+?)\s*$"
)


def traverse_ir_complete(stage, definitions, emitted_initializers, manifest, mode):
    seeds = set(ENGINE.ROOTS).union(emitted_initializers)
    reached = set(seeds)
    queue = deque(sorted(seeds))
    external = set()
    while queue:
        symbol = queue.popleft()
        body = definitions.get(symbol)
        if body is None:
            raise ENGINE.ClosureError(f"{stage} missing reached definition: {symbol}")
        for target in ENGINE.ir_calls(symbol, body):
            if target in definitions:
                if target not in reached:
                    reached.add(target)
                    queue.append(target)
            elif target.startswith(ENGINE.PROJECT_PREFIXES):
                raise ENGINE.ClosureError(f"{stage} missing project edge: {symbol} -> {target}")
            else:
                external.add(target)
    scanned = {symbol for symbol in reached if definitions.get(symbol, "").strip()}
    if mode == "missing":
        scanned.remove(sorted(scanned)[-1])
    elif mode == "extra":
        extra = next((symbol for symbol in definitions if symbol not in reached),
            "unexpected.definition")
        scanned.add(extra)
    missing = reached - scanned
    extra = scanned - reached
    if missing or extra:
        raise ENGINE.ClosureError(
            f"{stage} reached/scanned mismatch missing={sorted(missing)} extra={sorted(extra)}"
        )
    ENGINE.check_manifest(stage, external, manifest)
    bodies = {symbol: definitions[symbol] for symbol in scanned}
    ENGINE.check_forbidden(stage, bodies, external, mode)
    safepoints = sum(len(ENGINE.SAFEPOINT.findall(body)) for body in bodies.values())
    safepoints += sum(1 for symbol in external if ENGINE.SAFEPOINT.search(symbol))
    return reached, scanned, external, seeds, safepoints


ENGINE.traverse_ir = traverse_ir_complete


def object_calls_with_address_taken_callbacks(key, body, relocations, definitions, symbols):
    owner, symbol = key
    calls = []
    indirect = 0
    resolved_indirect = 0
    lines = body.splitlines()
    for line_index, line in enumerate(lines):
        relocation = OBJECT_RELOCATION.search(line)
        if relocation:
            kind, raw_target = relocation.groups()
            target = ENGINE.clean_relocation_target(raw_target)
            if target.startswith(".data.rel.ro"):
                pass
            elif target.startswith(".data"):
                target = ENGINE.resolve_data_target(target, relocations[owner], symbol)
                calls.append(target)
                if target == "CJ_MCC_HandleSafepoint":
                    resolved_indirect += 1
            elif target.startswith((".cjmetadata", ".rodata", ".text", ".LC")):
                pass
            elif kind == "PLT32":
                calls.append(target)
            elif (ENGINE.resolve_object_symbol(owner, target, symbols) is not None or
                    target in ENGINE.NATIVE):
                calls.append(target)
        instruction = re.search(r"\bcall\w*\s+(.+?)\s*$", line)
        if not instruction:
            continue
        operand = instruction.group(1)
        if operand.startswith("*"):
            indirect += 1
            continue
        direct = re.search(r"<(.+)>", operand)
        if not direct:
            continue
        target = direct.group(1)
        if "+0x" in target:
            base = target.split("+0x", 1)[0]
            if base != symbol:
                next_relocation = (OBJECT_RELOCATION.search(lines[line_index + 1])
                    if line_index + 1 < len(lines) else None)
                if next_relocation is None or next_relocation.group(1) != "PLT32":
                    raise ENGINE.ClosureError(f"unknown resolved object call in {symbol}: {target}")
        elif ENGINE.resolve_object_symbol(owner, target, symbols) is not None:
            calls.append(target)
        else:
            raise ENGINE.ClosureError(f"missing resolved object target in {symbol}: {target}")
    if indirect != resolved_indirect:
        raise ENGINE.ClosureError(
            f"ambiguous indirect object calls in {symbol}: calls={indirect} "
            f"resolved_safepoints={resolved_indirect}"
        )
    return calls


ENGINE.object_calls = object_calls_with_address_taken_callbacks


def check_cjthread_state_hook_contract(pre_definitions, final_definitions, object_definitions):
    for stage, definitions in (("pre", pre_definitions), ("final", final_definitions)):
        wrapper = definitions.get("CJRT_CJThreadStateHookRun")
        body = definitions.get(ROOT_IMPL)
        if wrapper is None or body is None:
            raise ENGINE.ClosureError(f"{stage} state-hook root absent")
        if ENGINE.ir_calls("CJRT_CJThreadStateHookRun", wrapper) != [ROOT_IMPL]:
            raise ENGINE.ClosureError(f"{stage} exported wrapper target mismatch")
        calls = [line for line in body.splitlines() if "@CJThreadStateHookObserve" in line]
        if len(calls) != 1:
            raise ENGINE.ClosureError(f"{stage} observer call count={len(calls)}")
        positions = [calls[0].find(token) for token in
            ("i32 0", "i32 1", "i32 2", "i32 3", "i32 4")]
        if any(position < 0 for position in positions) or positions != sorted(positions):
            raise ENGINE.ClosureError(f"{stage} state-hook constants absent or out of order")
    for symbol in ENGINE.NATIVE:
        bodies = [body for key, body in object_definitions.items() if key[1] == symbol]
        if len(bodies) != 1:
            raise ENGINE.ClosureError(f"object native definition count {symbol}={len(bodies)}")


ENGINE.check_atomic_contract = check_cjthread_state_hook_contract


def main():
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        result = ENGINE.main()
    output = stdout.getvalue().replace("ATOMICSPINLOCK", "CJTHREAD_STATE_HOOK")
    output = output.replace("fixed=4", "fixed=1")
    for key in ("pre_initializers", "final_initializers", "object_initializers"):
        output = re.sub(rf"{key}=(-?\d+)",
            lambda match: f"{key}={int(match.group(1)) + 3}", output)
    sys.stdout.write(output)
    sys.stderr.write(stderr.getvalue().replace("ATOMICSPINLOCK", "CJTHREAD_STATE_HOOK"))
    return result


if __name__ == "__main__":
    sys.exit(main())
