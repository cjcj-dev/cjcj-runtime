#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import re
import sys
from collections import defaultdict
from pathlib import Path


ENGINE_PATH = Path(__file__).with_name("atomicspinlock_closure.py")
SPEC = importlib.util.spec_from_file_location("spinlock_closure_engine", ENGINE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load closure engine: {ENGINE_PATH}")
ENGINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENGINE)

ENGINE.ROOTS = (
    "_CN15spinlock.noheap9ConstructHv",
    "_CN15spinlock.noheap4LockHPRN7rt.base8SpinLockE",
    "_CN15spinlock.noheap6UnlockHPRN7rt.base8SpinLockE",
    "_CN15spinlock.noheap7TryLockHPRN7rt.base8SpinLockE",
)
ENGINE.PRODUCTION = {
    "construct": "_CN7rt.base8SpinLock6<init>Hv",
    "lock": "_CN7rt.base4LockHPRNY_8SpinLockE",
    "unlock": "_CN7rt.base6UnlockHPRNY_8SpinLockE",
    "try": "_CN7rt.base7TryLockHPRNY_8SpinLockE",
}
ENGINE.NATIVE = (
    "cj_pthread_spin_init",
    "cj_pthread_spin_lock",
    "cj_pthread_spin_unlock",
    "cj_pthread_spin_trylock",
)
ENGINE.PROJECT_PREFIXES = (
    "_CN15spinlock.noheap",
    "_CN7rt.base",
    "_CGP15spinlock.noheap",
    "_CGP7rt.base",
)


def check_spinlock_contract(pre_definitions, final_definitions, object_definitions):
    for stage, definitions in (("pre", pre_definitions), ("final", final_definitions)):
        for symbol in ENGINE.PRODUCTION.values():
            if symbol not in definitions:
                raise ENGINE.ClosureError(f"{stage} missing production definition: {symbol}")
        construct = definitions[ENGINE.PRODUCTION["construct"]]
        lock = definitions[ENGINE.PRODUCTION["lock"]]
        unlock = definitions[ENGINE.PRODUCTION["unlock"]]
        attempt = definitions[ENGINE.PRODUCTION["try"]]
        if construct.count("@cj_pthread_spin_init") != 1 or not re.search(r"store i32 0,", construct):
            raise ENGINE.ClosureError(f"{stage} constructor/init multiplicity mismatch")
        if lock.count("@cj_pthread_spin_lock") != 1:
            raise ENGINE.ClosureError(f"{stage} Lock multiplicity mismatch")
        if unlock.count("@cj_pthread_spin_unlock") != 1:
            raise ENGINE.ClosureError(f"{stage} Unlock multiplicity mismatch")
        if attempt.count("@cj_pthread_spin_trylock") != 1 or not re.search(r"icmp eq i32 .*0", attempt):
            raise ENGINE.ClosureError(f"{stage} TryLock native-code test mismatch")
        production = construct + lock + unlock + attempt
        if "cj_pthread_spin_destroy" in production:
            raise ENGINE.ClosureError(f"{stage} invented explicit destroy edge")

    native_bodies = defaultdict(list)
    for key, body in object_definitions.items():
        if key[1] in ENGINE.NATIVE:
            native_bodies[key[1]].append(body)
    expected_calls = {
        "cj_pthread_spin_init": "pthread_spin_init",
        "cj_pthread_spin_lock": "pthread_spin_lock",
        "cj_pthread_spin_unlock": "pthread_spin_unlock",
        "cj_pthread_spin_trylock": "pthread_spin_trylock",
    }
    for symbol, target in expected_calls.items():
        bodies = native_bodies[symbol]
        if len(bodies) != 1 or bodies[0].count(target) != 1:
            raise ENGINE.ClosureError(f"native bridge multiplicity mismatch: {symbol} -> {target}")


ENGINE.check_atomic_contract = check_spinlock_contract


def main():
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        result = ENGINE.main()
    sys.stdout.write(stdout.getvalue().replace("ATOMICSPINLOCK", "SPINLOCK"))
    sys.stderr.write(stderr.getvalue().replace("ATOMICSPINLOCK", "SPINLOCK"))
    return result


if __name__ == "__main__":
    sys.exit(main())
