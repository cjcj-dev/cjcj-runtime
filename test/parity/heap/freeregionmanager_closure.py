#!/usr/bin/env python3
import argparse
import sys
from collections import deque

import regionlist_fresh_closure as closure


NATIVE = {
    'CJRT_FreeRegionManagerVTableAddressPoint',
    'CJRT_PagePoolMutexConstruct', 'CJRT_PagePoolMutexDestroy',
    'CJRT_PagePoolMutexLock', 'CJRT_PagePoolMutexUnlock',
    'CJRT_PagePoolMutexTryLock',
    'CJRT_ScopedEnterSaferegionOnlyMutatorBegin',
    'CJRT_ScopedEnterSaferegionEnd',
    'CJRT_FreeRegionReleaseNoneLog', 'CJRT_FreeRegionReleaseLog',
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pre', required=True)
    parser.add_argument('--calls', required=True)
    parser.add_argument('--final', action='append', required=True)
    parser.add_argument('--object', action='append', required=True)
    parser.add_argument('--native', action='append', required=True)
    args = parser.parse_args()
    try:
        pre = closure.parse_ir(args.pre)
        calls = closure.parse_calls(args.calls)
        operations = sorted(name for name in pre if 'FreshFreeRegionManagerPolicy' in name)
        if len(operations) != 1:
            raise closure.ClosureError(f'operation roots={operations}')
        static = sorted(name for name in pre if '_CGV' in name)
        if not static:
            raise closure.ClosureError('no emitted static initializer/accessor roots')
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
        unknown = sorted(symbol for symbol in external
                         if symbol not in NATIVE and not closure.allowed_external(symbol, False))
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
        native = {}
        for path in args.native:
            native.update(closure.parse_object(path))
        native_defs = NATIVE.intersection(native)
        if native_defs != NATIVE:
            raise closure.ClosureError(f'native definitions={sorted(native_defs)}')
        for name in native_defs:
            match = closure.FORBIDDEN.search(native[name])
            if match:
                raise closure.ClosureError(f'native forbidden={name}:{match.group(0)}')
        print(f'FREE_REGION_ROOTS operations={len(operations)} static_initializers={len(static)} status=PASS')
        print(f'FREE_REGION_NOHEAP_CLOSURE reachable_defs={len(reached) + len(native_defs)} '
              f'scanned_pre={len(reached)} scanned_final={len(reached)} '
              f'scanned_object={len(reached)} native_defs={len(native_defs)} missing=0 status=PASS')
        print(f'FREE_REGION_NOHEAP forbidden_alloc=0 forbidden_barrier=0 '
              f'external_edges={len(external)} status=PASS')
        return 0
    except (closure.ClosureError, OSError) as error:
        print(f'FREE_REGION_CLOSURE FAIL error={error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
