#!/usr/bin/env python3
import argparse
import re
import sys
from collections import deque
from pathlib import Path


DEFINE = re.compile(r'^define\b.*?@(?:"([^"]+)"|([^ (]+))\(')
OBJECT_DEFINE = re.compile(r'^[0-9a-fA-F]+ <(.+)>:$')
IR_EDGE = re.compile(r'\b(?:call|invoke)\b[^@\n]*@(?:"([^"]+)"|([-A-Za-z0-9_.$]+))\(')
OBJECT_EDGE = re.compile(r'\bcall\w*\s+[0-9a-fA-F]+\s+<([^>]+)>')
RELOCATION = re.compile(r'R_X86_64_(?:PLT32|PC32)\s+([^\s]+)')
FORBIDDEN = re.compile(
    r'MCC_New|CJ_MCC_New|MCC_Write|CJ_MCC_Write|write.?barrier|safepoint|'
    r'Create[A-Za-z]*Exception|ThrowException|llvm\.cj\.throw|ArrayList|HashMap|HashSet|'
    r'\bmalloc\b|\bcalloc\b|\brealloc\b|_Znwm|operator new', re.I)
ROOT_MARKERS = (
    'BarrierP0BaseObjectSizeRoot',
    'BarrierP0MarkedObjectRoot',
    'BarrierP0MarkedOffsetRoot',
)
NATIVE_ALLOWED = {
    'cj_atomic_uintptr_load_acquire', 'cj_atomic_u64_load_acquire',
    'cj_atomic_u64_load_seq_cst', 'cj_atomic_u8_load', 'RtFatal',
}


class ClosureError(Exception):
    pass


def parse_ir(path):
    definitions = {}
    current = None
    body = []
    for line in Path(path).read_text(encoding='utf-8', errors='replace').splitlines():
        match = DEFINE.match(line)
        if match:
            current = match.group(1) or match.group(2)
            body = [line]
            continue
        if current is not None:
            body.append(line)
            if line == '}':
                if current in definitions:
                    raise ClosureError(f'duplicate IR definition={current}')
                definitions[current] = '\n'.join(body) + '\n'
                current = None
    return definitions


def parse_object(path):
    definitions = {}
    current = None
    body = []
    for line in Path(path).read_text(encoding='utf-8', errors='replace').splitlines():
        match = OBJECT_DEFINE.match(line.strip())
        if match:
            if current is not None:
                if current in definitions:
                    raise ClosureError(f'duplicate object definition={current}')
                definitions[current] = '\n'.join(body) + '\n'
            current = match.group(1)
            body = [line]
        elif current is not None:
            body.append(line)
    if current is not None:
        if current in definitions:
            raise ClosureError(f'duplicate object definition={current}')
        definitions[current] = '\n'.join(body) + '\n'
    return definitions


def merge(paths, parser, stage):
    definitions = {}
    for path in paths:
        for name, body in parser(path).items():
            if name in definitions:
                raise ClosureError(f'{stage} ambiguous definition={name}')
            definitions[name] = body
    return definitions


def root_inventory(definitions, stage):
    roots = []
    unexpected = []
    for name in definitions:
        matches = [marker for marker in ROOT_MARKERS if marker in name]
        if matches:
            if len(matches) != 1:
                raise ClosureError(f'{stage} ambiguous root={name}')
            roots.append(name)
        elif 'BarrierP0' in name:
            unexpected.append(name)
    if unexpected:
        raise ClosureError(f'{stage} extra roots={unexpected}')
    if len(roots) != 3 or any(sum(marker in name for name in roots) != 1 for marker in ROOT_MARKERS):
        raise ClosureError(f'{stage} roots={roots}')
    return sorted(roots)


def ir_edges(body):
    edges = {match.group(1) or match.group(2) for match in IR_EDGE.finditer(body)}
    indirect = []
    for line in body.splitlines():
        instruction = re.search(r'(?:^|=)\s*(?:tail\s+)?(?:call|invoke)\b', line)
        if instruction and '@' not in line and ' asm ' not in line:
            indirect.append(line.strip())
    return edges, indirect


def object_edges(body):
    edges = set()
    for match in OBJECT_EDGE.finditer(body):
        target = match.group(1).split('@plt', 1)[0].split('@@', 1)[0]
        edges.add(re.sub(r'\+0x[0-9a-fA-F]+$', '', target))
    for match in RELOCATION.finditer(body):
        target = re.sub(r'[-+]0x[0-9a-fA-F]+$', '', match.group(1))
        edges.add(target.split('@', 1)[0])
    return edges, []


def allowed_external(symbol):
    if symbol in NATIVE_ALLOWED:
        return True
    if symbol.startswith('cj_atomic_'):
        return False
    if symbol.startswith(('_CN2rt', '_CN7rt.', '_CGV', '_CGP')):
        return False
    patterns = (
        r'^llvm\.', r'^CJ_MCC_', r'^CJ_MRT_', r'^__cangjie_', r'^_CNat', r'^_CNap',
        r'^_CGPat', r'^rt\$', r'^__stack_chk_fail$', r'^memcpy$', r'^memset$', r'^abort$',
        r'^strlen$', r'^write$', r'^backtrace$', r'^backtrace_symbols_fd$', r'^\.L',
    )
    return any(re.match(pattern, symbol) for pattern in patterns)


def traverse(definitions, roots, edge_reader, stage):
    reached = set(roots)
    queue = deque(roots)
    external = set()
    scanned = set()
    while queue:
        owner = queue.popleft()
        if owner not in definitions:
            raise ClosureError(f'{stage} missing definition={owner}')
        body = definitions[owner]
        scanned.add(owner)
        bad = FORBIDDEN.search(body)
        if bad:
            bad_line = next(line.strip() for line in body.splitlines() if FORBIDDEN.search(line))
            raise ClosureError(f'{stage} forbidden={bad.group(0)} owner={owner} line={bad_line}')
        edges, indirect = edge_reader(body)
        if indirect:
            raise ClosureError(f'{stage} indirect edges owner={owner} edges={indirect[:3]}')
        for target in edges:
            if target in definitions:
                if target not in reached:
                    reached.add(target)
                    queue.append(target)
            else:
                external.add(target)
    unknown = sorted(symbol for symbol in external if not allowed_external(symbol))
    if unknown:
        raise ClosureError(f'{stage} unexpected external/native edges={unknown[:20]}')
    if reached != scanned:
        raise ClosureError(f'{stage} reached/scanned mismatch reached={len(reached)} scanned={len(scanned)}')
    return reached, scanned, external


def apply_injection(kind, pre, final, objects):
    if kind == 'none':
        return
    if kind == 'missing-root':
        target = next(name for name in final if ROOT_MARKERS[0] in name)
        del final[target]
    elif kind == 'extra-root':
        target = next(name for name in final if ROOT_MARKERS[0] in name)
        final[target + '.BarrierP0UnexpectedRoot'] = final[target]
    elif kind == 'forbidden-final':
        target = next(name for name in final if ROOT_MARKERS[1] in name)
        final[target] += '\n  call void @MCC_NewObject()\n'
    elif kind == 'forbidden-object':
        target = next(name for name in objects if ROOT_MARKERS[2] in name)
        objects[target] += '\n  call 0 <malloc>\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pre', required=True)
    parser.add_argument('--final', action='append', required=True)
    parser.add_argument('--object', action='append', required=True)
    parser.add_argument('--native', action='append', default=[])
    parser.add_argument('--inject', choices=('none', 'missing-root', 'extra-root',
        'forbidden-final', 'forbidden-object'), default='none')
    args = parser.parse_args()
    try:
        pre = merge([args.pre], parse_ir, 'pre')
        final = merge(args.final, parse_ir, 'final')
        objects = merge(args.object + args.native, parse_object, 'object')
        apply_injection(args.inject, pre, final, objects)

        pre_roots = root_inventory(pre, 'pre')
        pre_static = sorted(name for name in pre if name.startswith('_CGV'))
        pre_reached, pre_scanned, pre_external = traverse(
            pre, pre_roots + pre_static, ir_edges, 'pre')

        final_roots = root_inventory(final, 'final')
        final_static = sorted(name for name in final if name.startswith('_CGV'))
        final_reached, final_scanned, final_external = traverse(
            final, final_roots + final_static, ir_edges, 'final')

        object_roots = root_inventory(objects, 'object')
        object_static = sorted(name for name in objects if name.startswith('_CGV'))
        object_reached, object_scanned, object_external = traverse(
            objects, object_roots + object_static, object_edges, 'object')

        print(f'BARRIER_P0_PREOPT_ROOTS operations=3 static_initializers={len(pre_static)} '
              f'reachable_defs={len(pre_reached)} scanned_defs={len(pre_scanned)} status=PASS')
        print(f'BARRIER_P0_FINAL_CLOSURE roots=3 static_initializers={len(final_static)} '
              f'reachable_defs={len(final_reached)} scanned_defs={len(final_scanned)} '
              f'external_edges={len(final_external)} status=PASS')
        print(f'BARRIER_P0_OBJECT_CLOSURE roots=3 static_initializers={len(object_static)} '
              f'reachable_defs={len(object_reached)} scanned_defs={len(object_scanned)} '
              f'external_edges={len(object_external)} status=PASS')
        print('BARRIER_P0_NOHEAP forbidden_alloc=0 forbidden_barrier=0 forbidden_safepoint=0 '
              'forbidden_exception=0 missing=0 ambiguous=0 status=PASS')
        return 0
    except (ClosureError, OSError, StopIteration) as error:
        print(f'BARRIER_P0_CLOSURE FAIL injection={args.inject} error={error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
