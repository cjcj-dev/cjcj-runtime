#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import re
import sys
from collections import defaultdict
from pathlib import Path


ENGINE_PATH = Path(__file__).parents[1] / "base" / "atomicspinlock_closure.py"
SPEC = importlib.util.spec_from_file_location("cjthread_spinlock_closure_engine", ENGINE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load closure engine: {ENGINE_PATH}")
ENGINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENGINE)

ENGINE.ROOTS = (
    "_CN23cjthreadspinlock.noheap4InitHPRN8rt.sched16CJthreadSpinLockE",
    "_CN23cjthreadspinlock.noheap4LockHPRN8rt.sched16CJthreadSpinLockE",
    "_CN23cjthreadspinlock.noheap6UnlockHPRN8rt.sched16CJthreadSpinLockE",
    "_CN23cjthreadspinlock.noheap7DestroyHPRN8rt.sched16CJthreadSpinLockE",
)
ENGINE.PRODUCTION = {
    "init": "_CN8rt.sched15PthreadSpinInitHPRNY_16CJthreadSpinLockE",
    "lock": "_CN8rt.sched15PthreadSpinLockHPRNY_16CJthreadSpinLockE",
    "unlock": "_CN8rt.sched17PthreadSpinUnlockHPRNY_16CJthreadSpinLockE",
    "destroy": "_CN8rt.sched18PthreadSpinDestroyHPRNY_16CJthreadSpinLockE",
}
ENGINE.NATIVE = (
    "cj_cjthread_pthread_spin_init",
    "cj_cjthread_pthread_spin_lock",
    "cj_cjthread_pthread_spin_unlock",
    "cj_cjthread_pthread_spin_destroy",
)
ENGINE.PROJECT_PREFIXES = (
    "_CN23cjthreadspinlock.noheap",
    "_CN8rt.sched",
    "_CGP23cjthreadspinlock.noheap",
    "_CGP8rt.sched",
)


def check_cjthread_spinlock_contract(pre_definitions, final_definitions, object_definitions):
    native_for_operation = {
        "init": "cj_cjthread_pthread_spin_init",
        "lock": "cj_cjthread_pthread_spin_lock",
        "unlock": "cj_cjthread_pthread_spin_unlock",
        "destroy": "cj_cjthread_pthread_spin_destroy",
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
        "cj_cjthread_pthread_spin_init": "pthread_spin_init",
        "cj_cjthread_pthread_spin_lock": "pthread_spin_lock",
        "cj_cjthread_pthread_spin_unlock": "pthread_spin_unlock",
        "cj_cjthread_pthread_spin_destroy": "pthread_spin_destroy",
    }
    for symbol, target in expected_calls.items():
        bodies = native_bodies[symbol]
        relocation = re.compile(
            rf"R_X86_64_(?:PLT32|PC32)\s+{re.escape(target)}(?:-0x[0-9a-fA-F]+)?$"
        )
        relocation_count = 0 if len(bodies) != 1 else sum(
            1 for line in bodies[0].splitlines() if relocation.search(line)
        )
        if len(bodies) != 1 or relocation_count != 1:
            raise ENGINE.ClosureError(f"native bridge multiplicity mismatch: {symbol} -> {target}")
    if not re.search(r"\bxor\s+%esi,%esi\b", native_bodies[ENGINE.NATIVE[0]][0]):
        raise ENGINE.ClosureError("PthreadSpinInit does not pass PTHREAD_PROCESS_PRIVATE zero")


ENGINE.check_atomic_contract = check_cjthread_spinlock_contract


def main():
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        result = ENGINE.main()
    sys.stdout.write(stdout.getvalue().replace("ATOMICSPINLOCK", "CJTHREAD_SPINLOCK"))
    sys.stderr.write(stderr.getvalue().replace("ATOMICSPINLOCK", "CJTHREAD_SPINLOCK"))
    return result


if __name__ == "__main__":
    sys.exit(main())
