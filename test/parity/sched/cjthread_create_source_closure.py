#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import re
import sys
from pathlib import Path


ENGINE_PATH = Path(__file__).parents[1] / "base" / "atomicspinlock_closure.py"
SPEC = importlib.util.spec_from_file_location("cjthread_create_source_closure_engine", ENGINE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load closure engine: {ENGINE_PATH}")
ENGINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENGINE)

ROOT_IMPL = "_CN27cjthreadcreatesource.noheap28CJRT_CJThreadCreateSourceRunHv"
ENGINE.ROOTS = (ROOT_IMPL,)
ENGINE.PRODUCTION = {}
ENGINE.NATIVE = ("CJThreadCreateSourceObserve",)
ENGINE.PROJECT_PREFIXES = (
    "_CN27cjthreadcreatesource.noheap", "_CN8rt.sched",
    "_CGP27cjthreadcreatesource.noheap", "_CGP8rt.sched",
)
ENGINE.BARRIER_INJECTIONS = {
    "barrier_pre": ("pre", "MCC_WriteRefField"),
    "barrier_final": ("final", "CJ_MCC_AtomicSwapReference"),
    "barrier_object": ("object", "CJ_MCC_WriteGenericPayload"),
    "allocation_pre": ("pre", "MCC_NewObject"),
    "allocation_final": ("final", "CJ_MCC_NewObject"),
    "allocation_object": ("object", "MCC_NewArray"),
}


def object_calls_with_template_names(key, body, relocations, definitions, symbols):
    owner, symbol = key
    calls = []
    indirect = 0
    resolved_indirect = 0
    lines = body.splitlines()
    for line_index, line in enumerate(lines):
        relocation = ENGINE.RELOCATION.search(line)
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
            elif target.startswith((".cjmetadata", ".rodata", ".text")):
                pass
            elif kind == "PLT32":
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
                next_relocation = (ENGINE.RELOCATION.search(lines[line_index + 1])
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


ENGINE.object_calls = object_calls_with_template_names


def check_cjthread_create_source_contract(pre_definitions, final_definitions, object_definitions):
    for stage, definitions in (("pre", pre_definitions), ("final", final_definitions)):
        wrapper = definitions.get("CJRT_CJThreadCreateSourceRun")
        body = definitions.get(ROOT_IMPL)
        if wrapper is None or body is None:
            raise ENGINE.ClosureError(f"{stage} create-source root absent")
        if ENGINE.ir_calls("CJRT_CJThreadCreateSourceRun", wrapper) != [ROOT_IMPL]:
            raise ENGINE.ClosureError(f"{stage} exported wrapper target mismatch")
        calls = [line for line in body.splitlines() if "@CJThreadCreateSourceObserve" in line]
        if len(calls) != 1:
            raise ENGINE.ClosureError(f"{stage} observer call count={len(calls)}")
        positions = [calls[0].find(token) for token in ("i32 0", "i32 1", "i32 2")]
        if any(position < 0 for position in positions) or positions != sorted(positions):
            raise ENGINE.ClosureError(f"{stage} create-source constants absent or out of order")
    observer_bodies = [body for key, body in object_definitions.items()
        if key[1] == "CJThreadCreateSourceObserve"]
    if len(observer_bodies) != 1:
        raise ENGINE.ClosureError(f"object observer definition count={len(observer_bodies)}")


ENGINE.check_atomic_contract = check_cjthread_create_source_contract


def main():
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        result = ENGINE.main()
    output = stdout.getvalue().replace("ATOMICSPINLOCK", "CJTHREAD_CREATE_SOURCE")
    output = output.replace("fixed=4", "fixed=1")
    for key in ("pre_initializers", "final_initializers", "object_initializers"):
        output = re.sub(rf"{key}=(-?\d+)",
            lambda match: f"{key}={int(match.group(1)) + 3}", output)
    sys.stdout.write(output)
    sys.stderr.write(stderr.getvalue().replace("ATOMICSPINLOCK", "CJTHREAD_CREATE_SOURCE"))
    return result


if __name__ == "__main__":
    sys.exit(main())
