"""Measure complete Safe/noLLVM edit/check cycles in a disposable checkout.

The first check and source-restoration checks are reported separately from the
20 measured edits. Never edits the source checkout or its neighboring project.
Requires git, Deno, Zig 0.17.0 and ZIG_ANALYZER. Full qualification stays pending.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
root, out = args.source.resolve(), args.out.resolve()
assert not out.exists(), 'Choose a new output directory'
assert os.environ.get('ZIG_ANALYZER'), 'Set ZIG_ANALYZER to the native analyzer'
out.mkdir(parents=True)
work = out / 'workspace' / 'blot2'
subprocess.run(['git', 'clone', '--quiet', '--shared', str(root), str(work)], check=True)
paths = set(subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0'))
paths.update(subprocess.check_output(['git', 'ls-files', '-z', '--others', '--exclude-standard', 'zig-native/src', 'scripts'], cwd=root).decode().split('\0'))
paths.discard('')
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
pins = {}
for name in sorted(paths):
    original, target = root / name, work / name
    if original.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        pins[name] = sha(original)
    elif target.is_file():
        target.unlink()
fixtures = {}
for name in ['src', 'packages']:
    source = root.parent / 'gdev' / name
    if not source.exists():
        continue
    for path in source.rglob('*.blot'):
        relative = path.relative_to(root.parent / 'gdev')
        target = work.parent / 'gdev' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        fixtures[str(relative)] = sha(target)
changes = [
    ('leaf', 'zig-native/src/inference_limits.zig', 'return 1_000_000;', lambda n: f'return {1000000+n};', 7),
    ('checker', 'zig-native/src/check/check.zig', 'Associated type normalization exceeded its work budget', lambda n: f'Associated type normalization exceeded its work budget (cycle {n})', 7),
    ('test', 'zig-native/src/check/check_contract_tests.zig', 'const source = try effectRowSource(allocator, 512, 1000, true);', lambda n: f'const source = try effectRowSource(allocator, 512, {1000+n}, true);', 6),
]
originals = {name: (work / name).read_text() for _, name, _, _, _ in changes}
report = {'kind': 'complete-development-cycles', 'started_at': datetime.now(timezone.utc).isoformat(),
          'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
          'source_sha256': pins, 'sibling_gdev_sha256': fixtures, 'backend': 'Safe/noLLVM',
          'cache_scope': 'Fresh checkout/local cache; retained host global cache; OS caches not flushed.',
          'samples': [], 'success': False, 'qualifies_release': False}
def save():
    (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
def check(kind, number, measured):
    assert subprocess.check_output(['zig', 'version'], text=True).strip() == '0.17.0'
    directory = out / f'{kind}-{number}'
    started = time.perf_counter()
    command = ['deno', 'task', 'check:dev', '--area', 'static-sharing', '--timings-dir', str(directory)]
    with (out / f'{kind}-{number}.log').open('wb') as log:
        result = subprocess.run(command, cwd=work, stdout=log, stderr=subprocess.STDOUT)
    data = json.loads((directory / 'results.json').read_text()) if (directory / 'results.json').exists() else {}
    sample = {'kind': kind, 'number': number, 'measured_edit': measured, 'command': command,
              'wall_seconds': time.perf_counter()-started, 'exit_code': result.returncode,
              'check': data, 'host_load': list(os.getloadavg())}
    report['samples'].append(sample)
    save()
    print(json.dumps({k: v for k, v in sample.items() if k not in ['check', 'command']}), flush=True)
    assert result.returncode == 0 and data.get('success'), f'Incomplete cycle {kind}-{number}'
    sample['compiler_identity_sha256'] = sha(work / 'zig-native/zig-out-dev/compiler-identity.bin')
    inventory = subprocess.check_output([str(work / 'zig-native/zig-out-native-dev/bin/blot-tests'), '--list'])
    sample['native_inventory_sha256'] = hashlib.sha256(inventory).hexdigest()
    if kind == 'initial':
        report['initial_identity_sha256'] = sample['compiler_identity_sha256']
        report['initial_inventory_sha256'] = sample['native_inventory_sha256']
    same = sample['compiler_identity_sha256'] == report['initial_identity_sha256']
    assert same == (not measured or kind == 'test'), 'Compiler identity did not follow production/test boundaries'
    assert sample['native_inventory_sha256'] == report['initial_inventory_sha256'], 'Native inventory changed'
    save()
try:
    check('initial', 0, False)
    for kind, name, search, replacement, count in changes:
        original = originals[name]
        assert original.count(search) == 1, name
        try:
            for number in range(1, count+1):
                (work / name).write_text(original.replace(search, replacement(number)))
                check(kind, number, True)
        finally:
            (work / name).write_text(original)
        check(kind+'-restore', 0, False)
    assert all(sha(work / p) == digest for p, digest in pins.items()), 'Isolated inputs not restored'
    edits = [s for s in report['samples'] if s['measured_edit']]
    assert len(edits) == 20
    seconds = sorted(s['wall_seconds'] for s in edits)
    report['summary'] = {'measured_edits': len(edits), 'median_seconds': statistics.median(seconds),
                         'sample_p95_seconds': seconds[math.ceil(.95*len(seconds))-1],
                         'maximum_seconds': max(seconds), 'note': 'Observed sample percentile, not a host-independent latency guarantee.'}
    report['success'] = True
finally:
    for name, contents in originals.items():
        (work / name).write_text(contents)
    save()
