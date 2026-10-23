"""Measure Safe/noLLVM compiler iteration in isolated copies; never edit the checkout.

python3 scripts/bench/compiler_iteration.py --out build/bench/iteration-current --runs 3
Reports empty-cache initialization, unchanged builds, distinct production edits,
test-only edits and source-exact reverts. Compiler identity and native inventory
are checked separately from unstripped executable byte hashes. OS caches are not flushed. This is a build
measurement, not native test execution or release qualification.
"""
import argparse
import hashlib
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--runs', type=int, default=3)
parser.add_argument('--modes', default='cached,incremental')
parser.add_argument('--resume', action='store_true', help='Continue an incomplete run with unchanged pinned inputs and recorded completed cells')
args = parser.parse_args()
assert args.runs > 0
root, out = args.source.resolve(), args.out.resolve()
assert args.resume or not out.exists(), 'Choose a new output directory; previous evidence is preserved'
out.mkdir(parents=True, exist_ok=args.resume)
modes = args.modes.split(',')
assert modes and len(modes) == len(set(modes)) and set(modes) <= {'cached', 'incremental'}
def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()
paths = sorted({p for p in subprocess.check_output([
    'git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
    'zig-native/src', 'zig-native/fixtures', 'zig-native/build.zig',
    'zig-native/build.zig.zon', 'zig-native/compiler_fingerprint.zig',
], cwd=root).decode().split('\0') if p})
pins = {p: sha(root / p) for p in paths}
report = {'kind': 'compiler-iteration', 'started_at': datetime.now(timezone.utc).isoformat(), 'modes': modes, 'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
          'source_sha256': pins, 'host': platform.platform(), 'cpu_count': os.cpu_count(), 'runs': args.runs,
          'cache_scope': 'Each mode starts with empty task-local/global Zig caches; OS page caches are not flushed.',
          'measurement': 'wall clock; wait4 user+system CPU including waited descendants; max single-process RSS in KiB on Linux',
          'backend': 'Safe/noLLVM', 'success': False, 'samples': []}
if args.resume:
    previous = json.loads((out / 'results.json').read_text())
    assert not previous['success'] and previous['source_sha256'] == pins and previous['runs'] == args.runs
    assert previous.get('modes', ['cached', 'incremental']) == modes
    assert subprocess.check_output(['zig', 'version'], text=True).strip() == previous['zig'] == '0.17.0'
    shutil.copy2(out / 'results.json', out / f'results-before-resume-{time.time_ns()}.json')
    report = previous
    report['resumed'] = True
    report['modes'] = modes
    report['resume_rule'] = 'Source bytes, compiler identity and native inventory; ELF byte differences remain reported, not release qualification.'
def save():
    (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
def build(mode, work, env, phase, round_, target):
    if args.resume:
        old = [r for r in report['samples'] if (r['mode'], r['phase'], r['round'], r['target']) == (mode, phase, round_, target)]
        if old:
            assert len(old) == 1 and old[0]['exit_code'] == 0
            assert target == 'build-system' or 'binary_sha256' in old[0]
            return old[0]
    version = subprocess.check_output(['zig', 'version'], env=env, text=True).strip()
    assert version == '0.17.0', version
    report['zig'] = version
    suffix = f'{mode}-{round_}-{phase}-{target}'
    command = ['zig', 'build', *(['install', 'compiler-identity'] if target == 'compiler' else ['--help'] if target == 'build-system' else ['test-compile']),
               '-Doptimize=safe', '-Dllvm=false', '--prefix', 'zig-out-iteration', '--summary', 'all']
    if mode == 'incremental': command.append('-fincremental')
    started = time.perf_counter()
    with (out / (suffix + '.stdout.log')).open('wb') as stdout, (out / (suffix + '.stderr.log')).open('wb') as stderr:
        child = subprocess.Popen(command, cwd=work / 'zig-native', env=env, stdout=stdout, stderr=stderr)
        _, status, usage = os.wait4(child.pid, 0)
        child.returncode = os.waitstatus_to_exitcode(status)
    sample = {'mode': mode, 'round': round_, 'phase': phase, 'target': target, 'command': command,
              'wall_seconds': time.perf_counter() - started, 'cpu_seconds': usage.ru_utime + usage.ru_stime,
              'peak_process_rss_kib': usage.ru_maxrss, 'exit_code': child.returncode, 'log': suffix + '.stderr.log'}
    report['samples'].append(sample)
    save()
    print(json.dumps(sample), flush=True)
    assert child.returncode == 0, suffix
    if target == 'build-system': return sample
    binary = work / 'zig-native/zig-out-iteration/bin' / ('blotc' if target == 'compiler' else 'blot-tests')
    sample['binary_sha256'] = sha(binary)
    sample['binary_bytes'] = binary.stat().st_size
    if target == 'compiler': sample['identity_sha256'] = sha(work / 'zig-native/zig-out-iteration/compiler-identity.bin')
    else:
        inventory = subprocess.check_output([str(binary), '--list'])
        sample['inventory_sha256'] = hashlib.sha256(inventory).hexdigest()
        sample['inventory_tests'] = len(inventory.splitlines())
    save()
    return sample
try:
    for mode in modes:
        work = out / mode / 'source'
        for name in paths:
            destination = work / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / name, destination)
        env = {**os.environ, 'ZIG_GLOBAL_CACHE_DIR': str(out / mode / 'global-cache'), 'ZIG_LOCAL_CACHE_DIR': str(out / mode / 'local-cache')}
        originals = {name: (work / name).read_text() for name in [
            'zig-native/src/inference_limits.zig', 'zig-native/src/check/check.zig', 'zig-native/src/check/check_contract_tests.zig']}
        build(mode, work, env, 'initial-empty-cache', 0, 'build-system')
        build(mode, work, env, 'unchanged', 0, 'build-system')
        initial = {target: build(mode, work, env, 'initial-artifact', 0, target) for target in ['compiler', 'native']}
        for round_ in range(1, args.runs + 1):
            for target in ['compiler', 'native']: build(mode, work, env, 'unchanged', round_, target)
            changes = [
                ('leaf-edit', 'zig-native/src/inference_limits.zig', 'return 1_000_000;', f'return {1000000 + round_};'),
                ('checker-edit', 'zig-native/src/check/check.zig', 'Associated type normalization exceeded its work budget', f'Associated type normalization exceeded its work budget (iteration {round_})'),
                ('test-edit', 'zig-native/src/check/check_contract_tests.zig', 'const source = try effectRowSource(allocator, 512, 1000, true);', f'const source = try effectRowSource(allocator, 512, {1000 + round_}, true);'),
            ]
            for phase, name, search, replacement in changes:
                original = originals[name]
                assert original.count(search) == 1, name
                try:
                    (work / name).write_text(original.replace(search, replacement))
                    for target in ['compiler', 'native']:
                        sample = build(mode, work, env, phase, round_, target)
                        if target == 'compiler':
                            same = sample['identity_sha256'] == initial[target]['identity_sha256']
                            assert same == (phase == 'test-edit'), 'Production/test identity boundary changed'
                            if same: sample['binary_matches_initial'] = sample['binary_sha256'] == initial[target]['binary_sha256']
                finally:
                    (work / name).write_text(original)
                for target in ['compiler', 'native']:
                    sample = build(mode, work, env, phase.replace('edit', 'revert'), round_, target)
                    sample['binary_matches_initial'] = sample['binary_sha256'] == initial[target]['binary_sha256']
                    # Debug/native object layout need not reproduce byte-for-byte
                    # after a real rebuild. Keep the difference visible; validate
                    # source identity and the exact executable test inventory.
                    key = 'identity_sha256' if target == 'compiler' else 'inventory_sha256'
                    assert sample[key] == initial[target][key], 'Revert did not restore identity/inventory'
                    save()
        assert all(sha(work / p) == h for p, h in pins.items()), 'Isolated inputs not restored'
        native = work / 'zig-native/zig-out-iteration/bin/blot-tests'
        regression = subprocess.run([str(native), '--test=check.check_contract_tests.test.ordinary effect rows preserve associated work for actual projections', '--test=check.check_contract_tests.test.associated exhaustion reports its actual remaining work allowance', '--test=check.check_contract_tests.test.configured associated work can exceed the legacy million step cap'], capture_output=True)
        (out / (mode + '-restored-regressions.log')).write_bytes(regression.stdout + regression.stderr)
        assert regression.returncode == 0, 'Restored native regression failure'
    assert all(sha(root / p) == h for p, h in pins.items()), 'Original inputs changed during measurement'
    keys = [(s['mode'], s['round'], s['phase'], s['target']) for s in report['samples']]
    assert len(keys) == len(set(keys)) == len(modes) * (4 + args.runs * 14), 'Incomplete or repeated measurement cells'
    assert all(s['exit_code'] == 0 for s in report['samples'])
    report['success'] = True
finally:
    save()
