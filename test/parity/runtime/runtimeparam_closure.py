#!/usr/bin/env python3
import argparse
import re
import sys
from collections import deque

import regionlist_fresh_closure as closure


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pre', required=True)
    parser.add_argument('--calls', required=True)
    parser.add_argument('--final', action='append', required=True)
    parser.add_argument('--object', action='append', required=True)
    args = parser.parse_args()
    try:
        pre = closure.parse_ir(args.pre)
        calls = closure.parse_calls(args.calls)
        operations = sorted(name for name in pre if 'RuntimeParamNoHeapRoot' in name)
        if len(operations) != 1:
            raise closure.ClosureError(f'operation roots={operations}')
        # `_CGP...` functions are generic package-initialization machinery, not
        # this package's static definitions. Actual Cangjie static accessors use
        # `_CGV`; this POD-only package emits none.
        static = sorted(name for name in pre if name.startswith('_CGV10rt.runtime'))
        reached = set(operations + static)
        queue = deque(reached)
        external = set()
        while queue:
            owner = queue.popleft()
            for target in calls.get(owner, ()):
                if target in pre:
                    if target not in reached:
                        reached.add(target)
                        queue.append(target)
                else:
                    external.add(target)
        allowed = (
            r'^external node$', r'^llvm\.', r'^CJ_MCC_C2NStub$',
            r'^CJ_MCC_HandleSafepoint$', r'^CJ_MCC_StackGrowStub$',
            r'^CJ_MRT_PreInitializePackage$', r'^__cangjie_', r'^__stack_chk_fail$',
            r'^_CNat', r'^_CGPat', r'^_Z', r'^memset$',
        )
        unknown = sorted(symbol for symbol in external
                         if not any(re.match(pattern, symbol) for pattern in allowed))
        if unknown:
            raise closure.ClosureError(f'unknown external edges={unknown[:20]}')
        closure.check_stage('pre', reached, pre)
        final = {}
        for path in args.final:
            for name, body in closure.parse_ir(path).items():
                final.setdefault(name, body)
        closure.check_stage('final', reached, final)
        objects = {}
        for path in args.object:
            for name, body in closure.parse_object(path).items():
                objects.setdefault(name, body)
        closure.check_stage('object', reached, objects)
        print(f'RUNTIMEPARAM_ROOTS operations={len(operations)} static_initializers={len(static)} status=PASS')
        print(f'RUNTIMEPARAM_NOHEAP_CLOSURE reachable_defs={len(reached)} '
              f'scanned_pre={len(reached)} scanned_final={len(reached)} '
              f'scanned_object={len(reached)} native_defs=0 missing=0 status=PASS')
        print(f'RUNTIMEPARAM_NOHEAP forbidden_alloc=0 forbidden_barrier=0 '
              f'external_edges={len(external)} status=PASS')
        return 0
    except (closure.ClosureError, OSError) as error:
        print(f'RUNTIMEPARAM_CLOSURE FAIL error={error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
