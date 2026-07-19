#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import re
import sys
from collections import defaultdict
from pathlib import Path


# Reuse the accepted whole-graph engine and exact 22-symbol barrier matcher.
ENGINE_PATH = Path(__file__).parents[1] / "base" / "atomicspinlock_closure.py"
SPEC = importlib.util.spec_from_file_location("thread_semaphore_closure_engine", ENGINE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load closure engine: {ENGINE_PATH}")
ENGINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENGINE)

ENGINE.ROOTS = ("CJRT_ThreadOwnerRun",)
ENGINE.PRODUCTION = {
    "init": "_CN8rt.sched13SemaphoreInitHPRNY_9SemaphoreEij",
    "wait": "_CN8rt.sched13SemaphoreWaitHPRNY_9SemaphoreE",
    "wait_no_intr": "_CN8rt.sched19SemaphoreWaitNoIntrHPRNY_9SemaphoreE",
    "post": "_CN8rt.sched13SemaphorePostHPRNY_9SemaphoreE",
    "destroy": "_CN8rt.sched16SemaphoreDestroyHPRNY_9SemaphoreE",
}
ENGINE.NATIVE = (
    "cj_cjthread_semaphore_init",
    "cj_cjthread_semaphore_wait",
    "cj_cjthread_semaphore_wait_no_intr",
    "cj_cjthread_semaphore_post",
    "cj_cjthread_semaphore_destroy",
)
ENGINE.PROJECT_PREFIXES = (
    "CJRT_ThreadOwnerRun",
    "_CN22threadsemaphore.noheap",
    "_CN8rt.sched",
    "_CGP22threadsemaphore.noheap",
    "_CGP8rt.sched",
)


# @C object stubs keep their Cangjie body address in a .data slot. The shared
# engine already follows that relocation but normally receives a symbol name;
# this compiler spells the target as .text+0xNN. Resolve it only when the same
# object has exactly one definition at that address, otherwise fail closed.
ORIGINAL_OBJECT_CALLS = ENGINE.object_calls


def object_calls_with_text_offsets(key, body, relocations, definitions, symbols):
    calls = ORIGINAL_OBJECT_CALLS(key, body, relocations, definitions, symbols)
    resolved = []
    for target in calls:
        match = re.fullmatch(r"\.text\+0x([0-9a-fA-F]+)", target)
        if match is None:
            resolved.append(target)
            continue
        address = int(match.group(1), 16)
        candidates = []
        for candidate, candidate_body in definitions.items():
            if candidate[0] != key[0]:
                continue
            first = candidate_body.splitlines()[0]
            definition = re.match(r"^([0-9a-fA-F]+) <", first)
            if definition is not None and int(definition.group(1), 16) == address:
                candidates.append(candidate[1])
        if len(candidates) != 1:
            raise ENGINE.ClosureError(
                f"object text-offset target count {target} in {key[1]}: {len(candidates)}"
            )
        resolved.append(candidates[0])
    return resolved


ENGINE.object_calls = object_calls_with_text_offsets


def check_thread_semaphore_contract(pre_definitions, final_definitions, object_definitions):
    native_for_operation = {
        "init": "cj_cjthread_semaphore_init",
        "wait": "cj_cjthread_semaphore_wait",
        "wait_no_intr": "cj_cjthread_semaphore_wait_no_intr",
        "post": "cj_cjthread_semaphore_post",
        "destroy": "cj_cjthread_semaphore_destroy",
    }
    for stage, definitions in (("pre", pre_definitions), ("final", final_definitions)):
        for operation, symbol in ENGINE.PRODUCTION.items():
            if symbol not in definitions:
                raise ENGINE.ClosureError(f"{stage} missing production definition: {symbol}")
            body = definitions[symbol]
            native = native_for_operation[operation]
            if body.count(f"@{native}") != 1 or not re.search(r"\bret i32\b", body):
                raise ENGINE.ClosureError(
                    f"{stage} {operation} native-call/return multiplicity mismatch"
                )

    native_bodies = defaultdict(list)
    for key, body in object_definitions.items():
        if key[1] in ENGINE.NATIVE:
            native_bodies[key[1]].append(body)
    expected_calls = {
        "cj_cjthread_semaphore_init": ("sem_init",),
        "cj_cjthread_semaphore_wait": ("sem_wait",),
        "cj_cjthread_semaphore_wait_no_intr": ("sem_wait", "__errno_location"),
        "cj_cjthread_semaphore_post": ("sem_post",),
        "cj_cjthread_semaphore_destroy": ("sem_destroy",),
    }
    for symbol, targets in expected_calls.items():
        bodies = native_bodies[symbol]
        if len(bodies) != 1:
            raise ENGINE.ClosureError(f"native bridge definition count mismatch: {symbol}")
        body = bodies[0]
        for target in targets:
            relocation = re.compile(
                rf"R_X86_64_(?:PLT32|PC32)\s+{re.escape(target)}(?:-0x[0-9a-fA-F]+)?$"
            )
            count = sum(1 for line in body.splitlines() if relocation.search(line))
            if count != 1:
                raise ENGINE.ClosureError(
                    f"native bridge relocation mismatch: {symbol} -> {target} count={count}"
                )
    no_intr = native_bodies["cj_cjthread_semaphore_wait_no_intr"][0]
    if not re.search(r"\btest\s+%eax,%eax\b", no_intr) or not re.search(
        r"\bcmpl\s+\$0x4,", no_intr
    ) or len(re.findall(r"\bjne\b", no_intr)) < 2:
        raise ENGINE.ClosureError("WaitNoIntr object lost result/EINTR retry conditions")


ENGINE.check_atomic_contract = check_thread_semaphore_contract


def main():
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        result = ENGINE.main()
    output = stdout.getvalue().replace("ATOMICSPINLOCK", "THREAD_SEMAPHORE")
    output = output.replace("fixed=4", "fixed=1")
    for key in ("pre_initializers", "final_initializers", "object_initializers"):
        output = re.sub(
            rf"{key}=(-?\d+)",
            lambda match: f"{key}={int(match.group(1)) + 3}",
            output,
        )
    sys.stdout.write(output)
    sys.stderr.write(stderr.getvalue().replace("ATOMICSPINLOCK", "THREAD_SEMAPHORE"))
    return result


if __name__ == "__main__":
    sys.exit(main())
