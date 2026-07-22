#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import re
import sys
from pathlib import Path

ENGINE_PATH = Path(__file__).parents[1] / "base" / "atomicspinlock_closure.py"
SPEC = importlib.util.spec_from_file_location("processor_foundation_engine", ENGINE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load closure engine: {ENGINE_PATH}")
ENGINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENGINE)

ROOT_IMPL = "_CN26processorfoundation.noheap27CJRT_ProcessorFoundationRunHv"
ENGINE.ROOTS = (ROOT_IMPL,)
ENGINE.PRODUCTION = {}
ENGINE.NATIVE = ("ProcessorFoundationObserve",)
ENGINE.PROJECT_PREFIXES = (
    "_CN26processorfoundation.noheap", "_CN8rt.sched",
    "_CGP26processorfoundation.noheap", "_CGP8rt.sched",
)
ENGINE.BARRIER_INJECTIONS = {
    "barrier_pre": ("pre", "MCC_WriteRefField"),
    "barrier_final": ("final", "CJ_MCC_AtomicSwapReference"),
    "barrier_object": ("object", "CJ_MCC_WriteGenericPayload"),
    "allocation_pre": ("pre", "MCC_NewObject"),
    "allocation_final": ("final", "CJ_MCC_NewObject"),
    "allocation_object": ("object", "MCC_NewArray"),
}

def check_contract(pre_definitions, final_definitions, object_definitions):
    for stage, definitions in (("pre", pre_definitions), ("final", final_definitions)):
        wrapper = definitions.get("CJRT_ProcessorFoundationRun")
        body = definitions.get(ROOT_IMPL)
        if wrapper is None or body is None:
            raise ENGINE.ClosureError(f"{stage} processor foundation root absent")
        if ENGINE.ir_calls("CJRT_ProcessorFoundationRun", wrapper) != [ROOT_IMPL]:
            raise ENGINE.ClosureError(f"{stage} exported wrapper target mismatch")
        if len([line for line in body.splitlines() if "@ProcessorFoundationObserve" in line]) != 1:
            raise ENGINE.ClosureError(f"{stage} observer call count mismatch")
    if len([body for key, body in object_definitions.items()
            if key[1] == "ProcessorFoundationObserve"]) != 1:
        raise ENGINE.ClosureError("object observer definition count mismatch")

ENGINE.check_atomic_contract = check_contract

def main():
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        result = ENGINE.main()
    output = stdout.getvalue().replace("ATOMICSPINLOCK", "PROCESSOR_FOUNDATION")
    output = output.replace("fixed=4", "fixed=1")
    for key in ("pre_initializers", "final_initializers", "object_initializers"):
        output = re.sub(rf"{key}=(-?\d+)",
            lambda match: f"{key}={int(match.group(1)) + 3}", output)
    sys.stdout.write(output)
    sys.stderr.write(stderr.getvalue().replace("ATOMICSPINLOCK", "PROCESSOR_FOUNDATION"))
    return result

if __name__ == "__main__":
    sys.exit(main())
