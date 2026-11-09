#!/usr/bin/env python3
"""Bounded production native worker OOM tests against a selected Goose runtime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True, help='observer-enabled emitted Goose runtime.c')
    parser.add_argument('--cc', default='clang')
    parser.add_argument('--output', type=Path, default=ROOT.parent/'build/goose-port/worker-oom-tests')
    args = parser.parse_args()
    args.runtime = args.runtime.resolve(strict=True)
    work = args.output.resolve(); work.mkdir(parents=True, exist_ok=True)
    sources = [ROOT/'native'/p for p in ('main.c', 'platform.c', 'request_supervisor.c',
        'request_supervisor.h', 'request_cache.c', 'request_cache.h',
        'allocation_observer.c', 'allocation_observer.h', 'tests/worker_oom_test.c',
        'tests/request_supervisor_test.c', 'tests/request_transport_test.c')]
    sources += [ROOT/'native/request_transport.c', ROOT/'native/request_transport.h', Path(__file__).resolve()]
    identities = {str(p.relative_to(ROOT)): digest(p) for p in sources}
    wrapper = work/'worker-oom.c'
    wrapper.write_text('#define _GNU_SOURCE\n#include '+json.dumps(str(args.runtime))+'\n#include '+
                       json.dumps(str(ROOT/'native/tests/worker_oom_test.c'))+'\n')
    started = time.monotonic(); rows = []
    def run(command, env=None):
        result = subprocess.run([str(v) for v in command], capture_output=True, text=True,
                                timeout=30, env=env)
        if result.returncode:
            raise RuntimeError(f'{command}: exit {result.returncode}\n{result.stdout}\n{result.stderr}')
        return result
    for name, extra in [('native', []), ('sanitized', ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'])]:
        flags = ['-std=gnu11', '-O1', '-g', '-pthread', *extra]
        entry = work/(name+'-entry.o')
        run([args.cc, *flags, '-Wall', '-Wextra', '-Werror', '-Dmain=blot_native_main',
             '-c', ROOT/'native/main.c', '-o', entry])
        binary = work/('worker-oom-'+name)
        run([args.cc, *flags, wrapper, entry, ROOT/'native/platform.c',
             ROOT/'native/request_supervisor.c', ROOT/'native/request_cache.c',
             ROOT/'native/allocation_observer.c', '-lm', '-o', binary])
        env = dict(os.environ)
        for key in ('BLOT_GOOSE_FAIL_AT', 'BLOT_GOOSE_FAIL_REQUEST', 'BLOT_GOOSE_FAIL_KIND'):
            env.pop(key, None)
        env['ASAN_OPTIONS'] = 'detect_leaks=0:allocator_may_return_null=1'
        env['UBSAN_OPTIONS'] = 'halt_on_error=1'
        for test, command in [('worker-oom', [binary]),
                              ('supervisor', [work/('supervisor-'+name)]),
                              ('transport', [work/('transport-'+name)])]:
            if test != 'worker-oom':
                source = ROOT/('native/tests/request_'+test+'_test.c')
                link = [ROOT/'native/request_supervisor.c', ROOT/'native/platform.c']
                if test == 'transport': link += [ROOT/'native/request_transport.c']
                run([args.cc, *flags, '-Wall', '-Wextra', '-Werror', source, *link, '-lm', '-o', command[0]])
            t = time.monotonic(); result = run(command, env)
            (work/(test+'-'+name+'.stdout')).write_text(result.stdout)
            (work/(test+'-'+name+'.stderr')).write_text(result.stderr)
            rows.append({'test': test, 'variant': name, 'seconds': round(time.monotonic()-t, 3),
                         'binary_sha256': digest(command[0]), 'stdout': result.stdout})
    if identities != {str(p.relative_to(ROOT)): digest(p) for p in sources}:
        raise RuntimeError('native sources changed during qualification')
    receipt = {'runtime_sha256': digest(args.runtime), 'source_sha256': identities, 'checks': rows,
               'allocator_refusal': 'real Goose registry calloc under RLIMIT_AS; physical RAM exhaustion untested',
               'compiler_runtime_qualified': False, 'seconds': round(time.monotonic()-started, 3)}
    (work/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps({'receipt': str(work/'receipt.json'), 'checks': len(rows), 'seconds': receipt['seconds']}))

if __name__ == '__main__':
    main()
