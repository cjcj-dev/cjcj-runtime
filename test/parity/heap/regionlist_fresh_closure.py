#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys
from collections import defaultdict, deque
from pathlib import Path


DEFINE = re.compile(r'^define\b.*?@(?:"([^"]+)"|([^ (]+))\(')
OBJECT_DEFINE = re.compile(r'^[0-9a-fA-F]+ <(.+)>:$')
FORBIDDEN = re.compile(
    r'MCC_New|CJ_MCC_New|RawArrayAllocate|llvm\.cj\.alloca\.generic|'
    r'StringBuilder|ArrayList|HashMap|ThrowException|gcwrite|write_barrier', re.I)
PROJECT = ('_CN2rt', '_CN7rt.', '_CGV', '_CGP', 'FreshRegion', 'wrapper.FC')
MUTEX = {
    'CJRT_PagePoolMutexConstruct', 'CJRT_PagePoolMutexDestroy',
    'CJRT_PagePoolMutexLock', 'CJRT_PagePoolMutexUnlock',
}
WRITE_LOG = '_ZN12MapleRuntime8WriteLogEbNS_7LogTypeEPKcz'


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
                    raise ClosureError(f'duplicate IR definition: {current}')
                definitions[current] = '\n'.join(body) + '\n'
                current = None
    return definitions


def parse_calls(path):
    calls = defaultdict(set)
    for raw in Path(path).read_text(encoding='utf-8').splitlines():
        fields = raw.split('\t')
        if len(fields) == 2:
            calls[fields[0]].add(fields[1])
    return calls


def parse_object(path):
    definitions = {}
    current = None
    body = []
    for line in Path(path).read_text(encoding='utf-8', errors='replace').splitlines():
        match = OBJECT_DEFINE.match(line.strip())
        if match:
            if current is not None:
                definitions[current] = '\n'.join(body) + '\n'
            current = match.group(1)
            body = [line]
        elif current is not None:
            body.append(line)
    if current is not None:
        definitions[current] = '\n'.join(body) + '\n'
    return definitions


def allowed_external(symbol, debug):
    patterns = (
        r'^external node$', r'^llvm\.', r'^CJ_MCC_', r'^CJ_MRT_', r'^__cangjie_',
        r'^cj_atomic_', r'^RtFatal$', r'^abort$', r'^memset$', r'^malloc$', r'^free$',
        r'^_CNat', r'^_CNap', r'^_CNar', r'^rt\$CreateArithmeticException_msg$',
        r'^_Z', r'^pthread_', r'^__stack_chk_fail$', r'^sizeOf',
    )
    if symbol in MUTEX:
        return True
    if debug and symbol == WRITE_LOG:
        return True
    return any(re.match(pattern, symbol) for pattern in patterns)


def traverse(pre, calls, debug):
    root_names = ('FreshRegionListLifecycle', 'FreshRegionListOperations',
                  'FreshRegionListVisitors', 'FreshRegionCache',
                  'FreshRegionListRemove', 'FreshRegionListDebug')
    operation_roots = sorted(name for name in pre if any(root in name for root in root_names))
    expected = 6 if debug else 5
    if len(operation_roots) != expected:
        raise ClosureError(f'operation root count={len(operation_roots)} expected={expected}')
    static_roots = sorted(name for name in pre if '_CGV' in name)
    if not static_roots:
        raise ClosureError('no emitted static initializer/accessor roots')
    callback = [name for name in pre if name == 'FreshNoHeapVisitor']
    if len(callback) != 1:
        raise ClosureError(f'callback targets={len(callback)}')
    roots = operation_roots + static_roots + callback
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
    unknown = sorted(symbol for symbol in external if not allowed_external(symbol, debug))
    if unknown:
        raise ClosureError(f'unknown external edges={unknown[:20]}')
    aliases = {name for name in reached
               if re.match(r'^wrapper\.FCuPRN17rt\.heap\.allocator10RegionInfoEPuE\.[0-9]+$', name)}
    if len(aliases) != 1:
        raise ClosureError(f'pre callback aliases={sorted(aliases)}')
    reached.difference_update(aliases)
    return roots, operation_roots, static_roots, callback, aliases, reached, external


def check_stage(stage, reached, definitions):
    missing = sorted(reached - set(definitions))
    extra_scanned = sorted(set(definitions).intersection(reached) - reached)
    scanned = set(definitions).intersection(reached)
    if missing or extra_scanned or scanned != reached:
        raise ClosureError(
            f'{stage} reached/scanned mismatch reached={len(reached)} scanned={len(scanned)} '
            f'missing={missing[:12]} extra={extra_scanned[:12]}')
    bad = [(name, FORBIDDEN.search(definitions[name]).group(0)) for name in reached
           if FORBIDDEN.search(definitions[name])]
    if bad:
        raise ClosureError(f'{stage} forbidden references={bad[:12]}')
    return scanned


def symbol_table(runtime):
    output = subprocess.run(
        ['readelf', '-Ws', runtime], check=True, text=True, stdout=subprocess.PIPE).stdout
    symbols = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 8 or fields[3] != 'FUNC' or fields[6] == 'UND':
            continue
        try:
            address = int(fields[1], 16)
            size = int(fields[2])
        except ValueError:
            continue
        name = fields[7].split('@@', 1)[0]
        if address and size and name not in symbols:
            symbols[name] = (address, size)
    return symbols


def runtime_closure(runtime):
    symbols = symbol_table(runtime)
    if WRITE_LOG not in symbols:
        raise ClosureError('live runtime WriteLog definition absent')
    reached = {WRITE_LOG}
    queue = deque([WRITE_LOG])
    bodies = {}
    call_pattern = re.compile(r'\bcall\w*\s+[0-9a-fA-F]+\s+<([^>]+)>')
    while queue:
        name = queue.popleft()
        address, size = symbols[name]
        output = subprocess.run([
            'objdump', '-dr', f'--start-address={address}', f'--stop-address={address + size}',
            runtime], check=True, text=True, stdout=subprocess.PIPE).stdout
        bodies[name] = output
        for target in call_pattern.findall(output):
            target = target.split('@@', 1)[0].split('@plt', 1)[0]
            target = re.sub(r'\+0x[0-9a-fA-F]+$', '', target)
            if target == name or target not in symbols:
                continue
            if target not in reached:
                reached.add(target)
                queue.append(target)
    bad = [(name, FORBIDDEN.search(body).group(0)) for name, body in bodies.items()
           if FORBIDDEN.search(body)]
    if bad:
        raise ClosureError(f'WriteLog target closure forbidden={bad[:12]}')
    return reached, bodies


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
        pre = parse_ir(args.pre)
        calls = parse_calls(args.calls)
        roots, operations, static, callback, aliases, reached, external = traverse(pre, calls, args.debug)
        check_stage('pre', reached, pre)

        final = {}
        for path in args.final:
            for name, body in parse_ir(path).items():
                final.setdefault(name, body)
        check_stage('final', reached, final)

        objects = {}
        for path in args.object:
            for name, body in parse_object(path).items():
                objects.setdefault(name, body)
        check_stage('object', reached, objects)

        native = {}
        for path in args.native:
            native.update(parse_object(path))
        native_defs = MUTEX.intersection(native)
        if native_defs != MUTEX:
            raise ClosureError(f'native mutex definitions={sorted(native_defs)}')
        native_bad = [(name, FORBIDDEN.search(native[name]).group(0)) for name in native_defs
                      if FORBIDDEN.search(native[name])]
        if native_bad:
            raise ClosureError(f'native forbidden={native_bad}')

        runtime_defs = set()
        if args.debug:
            runtime_defs, _ = runtime_closure(args.runtime)
        total = len(reached) + len(native_defs) + len(runtime_defs)
        print(
            f'REGIONLIST_{"DEBUG_" if args.debug else ""}ROOTS operations={len(operations)} '
            f'static_initializers={len(static)} callback_targets={len(callback)} '
            f'pre_callback_aliases={len(aliases)} status=PASS')
        print(
            f'REGIONLIST_{"DEBUG_" if args.debug else ""}NOHEAP_CLOSURE '
            f'reachable_defs={total} scanned_pre={len(reached)} scanned_final={len(reached)} '
            f'scanned_object={len(reached)} native_defs={len(native_defs)} '
            f'runtime_target_defs={len(runtime_defs)} missing=0 status=PASS')
        print(
            f'REGIONLIST_{"DEBUG_" if args.debug else ""}NOHEAP '
            f'forbidden_alloc=0 forbidden_barrier=0 external_edges={len(external)} status=PASS')
        return 0
    except (ClosureError, OSError, subprocess.CalledProcessError) as error:
        print(f'REGIONLIST_CLOSURE FAIL debug={int(args.debug)} error={error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
