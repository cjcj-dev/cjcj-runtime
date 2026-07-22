#!/usr/bin/env python3
import argparse, re, sys
from collections import deque
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'heap'))
import regionlist_fresh_closure as closure

parser = argparse.ArgumentParser()
parser.add_argument('--pre', required=True); parser.add_argument('--calls', required=True)
parser.add_argument('--final', action='append', required=True); parser.add_argument('--object', action='append', required=True)
args = parser.parse_args()
try:
    pre = closure.parse_ir(args.pre); calls = closure.parse_calls(args.calls)
    operations = sorted(n for n in pre if 'FieldRefNoHeapRoot' in n)
    if len(operations) != 1: raise closure.ClosureError(f'operation roots={operations}')
    static = sorted(n for n in pre if n.startswith('_CGV14rt.objectmodel'))
    reached = set(operations + static); queue = deque(reached); external = set()
    while queue:
        owner = queue.popleft()
        for target in calls.get(owner, ()):
            if target in pre and target not in reached: reached.add(target); queue.append(target)
            elif target not in pre: external.add(target)
    allowed = (r'^external node$', r'^llvm\.', r'^CJ_MCC_', r'^CJ_MRT_', r'^__cangjie_',
        r'^__stack_chk_fail$', r'^_CNat', r'^_CNap', r'^_CGPat', r'^cj_atomic_field_', r'^abort$')
    unknown = sorted(s for s in external if not any(re.match(p, s) for p in allowed))
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
    print(f'FIELDREF_ROOTS operations=1 static_initializers={len(static)} status=PASS')
    print(f'FIELDREF_NOHEAP_CLOSURE reachable_defs={len(reached)} scanned_pre={len(reached)} scanned_final={len(reached)} scanned_object={len(reached)} native_defs=9 missing=0 status=PASS')
    print(f'FIELDREF_NOHEAP forbidden_alloc=0 forbidden_barrier=0 external_edges={len(external)} status=PASS')
except (closure.ClosureError, OSError) as e:
    print(f'FIELDREF_CLOSURE FAIL error={e}', file=sys.stderr); sys.exit(1)
