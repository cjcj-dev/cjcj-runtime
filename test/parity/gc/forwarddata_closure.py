#!/usr/bin/env python3
import argparse, re, sys
from collections import deque
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'heap'))
import regionlist_fresh_closure as closure

NATIVE = {
    'cj_atomic_uintptr_fetch_add_seq_cst', 'cj_atomic_uintptr_load_seq_cst',
    'cj_atomic_uintptr_store_seq_cst', 'cj_atomic_u32_store_release',
}

parser = argparse.ArgumentParser()
parser.add_argument('--pre', required=True); parser.add_argument('--calls', required=True)
parser.add_argument('--final', action='append', required=True); parser.add_argument('--object', action='append', required=True)
parser.add_argument('--native', action='append', required=True)
args = parser.parse_args()
try:
    pre = closure.parse_ir(args.pre); calls = closure.parse_calls(args.calls)
    operations = sorted(n for n in pre if 'ForwardDataNoHeapRoot' in n)
    if len(operations) != 1: raise closure.ClosureError(f'operation roots={operations}')
    static = sorted(n for n in pre if '_CGV' in n)
    if not static: raise closure.ClosureError('no static initializer roots')
    reached = set(operations + static); queue = deque(reached); external = set()
    while queue:
        owner = queue.popleft()
        for target in calls.get(owner, ()):
            if target in pre and target not in reached: reached.add(target); queue.append(target)
            elif target not in pre: external.add(target)
    os_leaves = {'mmap', 'munmap', 'madvise', 'prctl', 'memset', 'write'}
    unknown = sorted(s for s in external if s not in NATIVE and s not in os_leaves and
                     not closure.allowed_external(s, False))
    if unknown: raise closure.ClosureError(f'unknown external edges={unknown[:20]}')
    closure.check_stage('pre', reached, pre)
    final = {}
    for p in args.final:
        for n, b in closure.parse_ir(p).items(): final.setdefault(n, b)
    closure.check_stage('final', reached, final)
    objects = {}
    for p in args.object:
        for n, b in closure.parse_object(p).items(): objects.setdefault(n, b)
    closure.check_stage('object', reached, objects)
    native = {}
    for p in args.native: native.update(closure.parse_object(p))
    found = NATIVE.intersection(native)
    if found != NATIVE: raise closure.ClosureError(f'native definitions={sorted(found)}')
    for n in found:
        if closure.FORBIDDEN.search(native[n]): raise closure.ClosureError(f'native forbidden={n}')
    print(f'FORWARDDATA_ROOTS operations=1 static_initializers={len(static)} status=PASS')
    print(f'FORWARDDATA_NOHEAP_CLOSURE reachable_defs={len(reached)+len(found)} '
          f'scanned_pre={len(reached)} scanned_final={len(reached)} scanned_object={len(reached)} '
          f'native_defs={len(found)} missing=0 status=PASS')
    print(f'FORWARDDATA_NOHEAP forbidden_alloc=0 forbidden_barrier=0 external_edges={len(external)} status=PASS')
except (closure.ClosureError, OSError) as e:
    print(f'FORWARDDATA_CLOSURE FAIL error={e}', file=sys.stderr); sys.exit(1)
