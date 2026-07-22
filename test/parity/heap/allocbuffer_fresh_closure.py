#!/usr/bin/env python3
import argparse
import re
import sys
from collections import deque

import regionlist_fresh_closure as closure


NATIVE = {
    'CJRT_AllocBufferNullRegion',
    'CJRT_AllocBufferPreparedConstruct',
    'CJRT_AllocBufferPreparedLoadRelaxed',
    'CJRT_AllocBufferPreparedCompareExchangeRelease',
    'CJRT_AllocBufferStackRootsConstruct',
    'CJRT_AllocBufferStackRootsDestroy',
    'CJRT_AllocBufferPushRoot',
    'CJRT_AllocBufferMergeRoots',
    'CJRT_PagePoolMutexConstruct',
    'CJRT_PagePoolMutexDestroy',
    'CJRT_PagePoolMutexLock',
    'CJRT_PagePoolMutexUnlock',
}


def traverse(pre, calls, debug):
    operations = sorted(name for name in pre if 'FreshAllocBufferDataPlane' in name)
    if len(operations) != 1:
        raise closure.ClosureError(f'operation roots={operations}')
    static = sorted(name for name in pre if '_CGV' in name)
    if not static:
        raise closure.ClosureError('no emitted static initializer/accessor roots')
    roots = operations + static
    reached = set(roots)
    queue = deque(roots)
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
    unknown = sorted(symbol for symbol in external
                     if symbol not in NATIVE and not closure.allowed_external(symbol, debug))
    if unknown:
        raise closure.ClosureError(f'unknown external edges={unknown[:20]}')
    return operations, static, reached, external


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pre', required=True)
    parser.add_argument('--calls', required=True)
    parser.add_argument('--final', action='append', required=True)
    parser.add_argument('--object', action='append', required=True)
    parser.add_argument('--native', action='append', required=True)
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args()
    try:
        pre = closure.parse_ir(args.pre)
        calls = closure.parse_calls(args.calls)
        operations, static, reached, external = traverse(pre, calls, args.debug)
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

        native = {}
        for path in args.native:
            native.update(closure.parse_object(path))
        native_defs = NATIVE.intersection(native)
        if native_defs != NATIVE:
            raise closure.ClosureError(f'native definitions={sorted(native_defs)}')
        native_bad = [(name, closure.FORBIDDEN.search(native[name]).group(0))
                      for name in native_defs if closure.FORBIDDEN.search(native[name])]
        if native_bad:
            raise closure.ClosureError(f'native forbidden={native_bad}')

        runtime_defs = set()
        if args.debug:
            runtime_defs, _ = closure.runtime_closure(args.runtime)
        total = len(reached) + len(native_defs) + len(runtime_defs)
        prefix = 'ALLOC_BUFFER_DEBUG_' if args.debug else 'ALLOC_BUFFER_'
        print(f'{prefix}ROOTS operations={len(operations)} static_initializers={len(static)} status=PASS')
        print(f'{prefix}NOHEAP_CLOSURE reachable_defs={total} scanned_pre={len(reached)} '
              f'scanned_final={len(reached)} scanned_object={len(reached)} '
              f'native_defs={len(native_defs)} runtime_target_defs={len(runtime_defs)} '
              'missing=0 status=PASS')
        print(f'{prefix}NOHEAP forbidden_alloc=0 forbidden_barrier=0 '
              f'external_edges={len(external)} status=PASS')
        return 0
    except (closure.ClosureError, OSError) as error:
        print(f'ALLOC_BUFFER_CLOSURE FAIL debug={int(args.debug)} error={error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
