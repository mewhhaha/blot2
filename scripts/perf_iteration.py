#!/usr/bin/env python3
"""Paired JS measurements of gdev's real compile/reload path, without rebuilding.

--baseline/--candidate identify passed run_m3_batch_js_build.py receipts.
The workload is a frozen gdev tree; its manifest maps paths to sha256/mode rows.
Each sample uses a fresh process and disposable copy. Only that copy is edited.
"""
from pathlib import Path
import argparse
import fcntl
import hashlib
import json
import os
import shutil
import signal
import stat
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'build/perf-overhaul'
sys.path.insert(0, str(BASE))
import bend_batch
import run_m3_full_proof as owned
import run_m3_batch_js_build as build_checks


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def verify_build(path, check_installed=True):
    report = json.loads(path.read_text())
    assert report['schema'] == 'm3-batch-official-js-v1'
    assert report['status'] == 'pass' and report['sources_unchanged']
    root = Path(report['snapshot'])
    assert sha(report['manifest']) == report['manifest_sha256']
    for name, digest in json.loads(Path(report['manifest']).read_text()).items():
        assert sha(root / name) == digest, name
    for name, digest in report['artifacts'].items():
        assert sha(root / 'generated/compiler' / name) == digest, name
    assert 'compiler.js' in report['artifacts']
    assert report['toolchain'] == report['post_toolchain']
    assert {r['artifact'] for r in report['module_runs']} == set(report['artifacts'])
    assert all(r['exit_code'] == 0 and r['cutoff'] is None for r in report['module_runs'])
    build_checks.verify_prior_proof(Path(report['prior_proof_receipt']),
                                   report['prior_proof_receipt_sha256'], root,
                                   Path(report['manifest']), report['manifest_sha256'],
                                   report['toolchain'])
    bend_batch.verify_batch(Path(report['toolchain_receipt']),
                            report['toolchain_receipt_sha256'], check_installed)
    return report


def verify_workload(root, rows):
    for name, row in rows.items():
        rel = Path(name)
        assert not rel.is_absolute() and '..' not in rel.parts
        if row.get('deleted'):
            assert not (root / rel).exists(), name
            continue
        assert not (root / rel).is_symlink() and sha(root / rel) == row['sha256'], name
        assert stat.S_IMODE((root / rel).stat().st_mode) == row['mode'], name
    assert {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() or p.is_symlink()} == {
        name for name, row in rows.items() if not row.get('deleted')}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', type=Path, required=True, help='passed JS build receipt')
    p.add_argument('--candidate', type=Path, help='passed JS build receipt')
    p.add_argument('--workload', type=Path, required=True)
    p.add_argument('--workload-manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True, help='new report directory')
    p.add_argument('--rounds', type=int, default=3)
    p.add_argument('--profile', action='store_true', help='one diagnostic cold sample per side')
    p.add_argument('--timeout', type=int, default=300)
    args = p.parse_args()
    assert args.rounds > 0 and args.timeout > 0
    out = args.output.resolve()
    assert not out.exists(), 'use a new output directory; keep failed/raw samples'
    workload = args.workload.resolve()
    rows = json.loads(args.workload_manifest.read_text())
    with (BASE / 'logs/.gate.lock').open('a') as gate:
        fcntl.flock(gate, fcntl.LOCK_EX | fcntl.LOCK_NB)
        builds = {name: verify_build(path.resolve()) for name, path in
                  [('A', args.baseline), ('B', args.candidate)] if path}
        assert len({b['toolchain_receipt_sha256'] for b in builds.values()}) == 1
        stds = [{n: h for n, h in json.loads(Path(b['manifest']).read_text()).items()
                 if n.startswith('std/')} for b in builds.values()]
        assert all(std == stds[0] for std in stds), 'A/B must use the same std sources'
        verify_workload(workload, rows)
        out.mkdir(parents=True)
        report = {'status': 'running', 'profiled': args.profile,
                  'command': sys.argv, 'builds': builds,
                  'workload_manifest_sha256': sha(args.workload_manifest),
                  'harness': {f.name: sha(f) for f in Path(__file__).parent.glob('perf_iteration*') if f.is_file()},
                  'samples': [], 'summary': {}, 'paired': {}}
        write(out / 'report.json', report)
        signal.signal(signal.SIGTERM, owned.cancelled)
        signal.signal(signal.SIGINT, owned.cancelled)
        child = None
        try:
            for round_index in range(1 if args.profile else args.rounds):
                order = list(builds)
                if round_index % 2:
                    order.reverse()
                for side in order:
                    sample_dir = out / f'{round_index + 1}-{side}'
                    game = sample_dir / 'project/gdev'
                    game.mkdir(parents=True)
                    for name, row in rows.items():
                        if row.get('deleted'):
                            continue
                        target = game / name
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(workload / name, target)
                    compiler = Path(builds[side]['snapshot'])
                    (game.parent / 'blot2').symlink_to(compiler, target_is_directory=True)
                    config = json.loads((compiler / 'deno.json').read_text())
                    imports = config.setdefault('imports', {})
                    wrapper = (ROOT / 'scripts/perf_iteration_trace.ts').as_uri()
                    sibling = game.parent / 'blot2/compiler'
                    imports.update({
                        'perf/source-original': (compiler / 'compiler/source.ts').as_uri(),
                        'perf/project-original': (compiler / 'compiler/source_project.ts').as_uri(),
                        (sibling / 'source.ts').as_uri(): wrapper,
                        (sibling / 'source_project.ts').as_uri(): wrapper,
                    })
                    write(sample_dir / 'deno.json', config)
                    cmd = ['python3', str(BASE / 'run_normal_priority.py'), 'deno', 'run',
                           '--no-prompt', '--no-lock', f'--config={sample_dir / "deno.json"}', '--allow-read',
                           f'--allow-write={game / "src/daylight.blot"},{sample_dir / "compile.cpuprofile"}',
                           str(ROOT / 'scripts/perf_iteration.ts'), str(game)]
                    if args.profile:
                        cmd.insert(cmd.index('--allow-read') + 1, '--allow-sys=inspector')
                        cmd.append(str(sample_dir / 'compile.cpuprofile'))
                    start = time.monotonic()
                    epoch = time.time() * 1000
                    sample = {'round': round_index + 1, 'side': side, 'command': cmd,
                              'directory': str(sample_dir), 'start_epoch_ms': epoch}
                    report['samples'].append(sample)
                    print(f'Running {round_index + 1}-{side}', flush=True)
                    with (sample_dir / 'stdout.jsonl').open('w') as stdout, (sample_dir / 'stderr.log').open('w') as stderr:
                        child = subprocess.Popen(cmd, cwd=ROOT, stdout=stdout, stderr=stderr,
                                                 start_new_session=True, env={**os.environ, 'NO_COLOR': '1'})
                        sample['owned_process_group'] = child.pid
                        write(out / 'report.json', report)
                        peak = 0
                        while child.poll() is None:
                            peak = max(peak, owned.group_rss_mib(child.pid))
                            if time.monotonic() - start > args.timeout or peak > 8192:
                                owned.stop_owned(child)
                                raise RuntimeError('sample resource limit exceeded')
                            time.sleep(0.2)
                        sample['exit_code'] = child.wait()
                        owned.stop_owned(child)
                        child = None
                    sample['elapsed_seconds'] = time.monotonic() - start
                    sample['peak_group_rss_mib'] = peak
                    assert sample['exit_code'] == 0, (sample_dir / 'stderr.log').read_text()[-5000:]
                    events = [json.loads(line) for line in (sample_dir / 'stdout.jsonl').read_text().splitlines()]
                    sample['events'] = events
                    metrics = [e for e in events if e['event'] == 'measurement']
                    assert [e['phase'] for e in metrics] == (['cold'] if args.profile else ['cold', 'unchanged', 'edit'])
                    metrics[0]['startup_to_wasm_ms'] = metrics[0]['ready_epoch_ms'] - epoch
                    assert len([e for e in events if e['event'] == 'behavior']) == (1 if args.profile else 2)
                    verify_workload(game, rows)  # worker must restore the edited source
                    write(out / 'report.json', report)
                    print(json.dumps({'sample': f'{round_index + 1}-{side}',
                                      'request_ms': {e['phase']: round(e['request_ms'], 2) for e in metrics}}), flush=True)
            for side in builds:
                for phase in ['cold', 'unchanged', 'edit']:
                    events = [e for s in report['samples'] if s['side'] == side for e in s['events']
                              if e['event'] == 'measurement' and e['phase'] == phase]
                    if not events:
                        continue
                    # Byte determinism is required within a side, behavior across sides.
                    assert len({e['wasm_sha256'] for e in events}) == 1
                    assert len({e['source_sha256'] for e in events}) == 1
                    report['summary'][f'{side}/{phase}'] = {
                        metric: {'median': statistics.median(e[metric] for e in events),
                                 'min': min(e[metric] for e in events), 'max': max(e[metric] for e in events)}
                        for metric in ['request_ms', 'compile_ms', 'project_ms', 'setup_ms', 'process_cpu_ms']
                    }
            for phase in ['cold', 'edit']:
                behaviors = [e for s in report['samples'] for e in s['events']
                             if e['event'] == 'behavior' and e['phase'] == phase]
                assert len({e['frame_sha256'] for e in behaviors}) <= 1, 'guest behavior differs'
            for phase in ['cold', 'unchanged', 'edit']:
                sources = [e['source_sha256'] for s in report['samples'] for e in s['events']
                           if e['event'] == 'measurement' and e['phase'] == phase]
                assert len(set(sources)) <= 1, 'A/B workload sources differ'
                if 'B' in builds and not args.profile:
                    pairs = []
                    for round_index in range(1, args.rounds + 1):
                        measurements = {s['side']: next(e for e in s['events']
                                        if e['event'] == 'measurement' and e['phase'] == phase)
                                        for s in report['samples'] if s['round'] == round_index}
                        a, b = measurements['A']['request_ms'], measurements['B']['request_ms']
                        pairs.append({'round': round_index, 'A_ms': a, 'B_ms': b,
                                      'difference_ms': b - a, 'B_over_A': b / a})
                    report['paired'][phase] = {'pairs': pairs,
                        'median_ratio': statistics.median(pair['B_over_A'] for pair in pairs)}
            for name, path in [('A', args.baseline), ('B', args.candidate)]:
                if path:
                    assert verify_build(path.resolve(), check_installed=False) == builds[name]
            verify_workload(workload, rows)
            assert report['harness'] == {f.name: sha(f) for f in Path(__file__).parent.glob('perf_iteration*') if f.is_file()}, 'benchmark harness changed during measurements'
            report['status'] = 'pass'
        except BaseException as error:
            report['status'] = 'fail'
            report['error'] = f'{type(error).__name__}: {error}'
            raise
        finally:
            if child is not None:
                owned.stop_owned(child)
            write(out / 'report.json', report)
    print(json.dumps(report['summary'], indent=2))


if __name__ == '__main__':
    main()
