"""Reproduce the post-CT96 hill analysis from archived diagnostic evidence.

python3 scripts/bench/review_performance.py CT96_DIRECTORY OOM_DIRECTORY OUTPUT
No compiler invocation or private source contents are needed. Profiled clocks
rank work; they are not throughput acceptance measurements.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('qualification', type=Path)
parser.add_argument('oom', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
pins = {}


def read(root, relative, prefix):
    data = (root / relative).read_bytes()
    pins[f'{prefix}/{relative}'] = hashlib.sha256(data).hexdigest()
    return data.decode()


def qualified(relative):
    return read(args.qualification, relative, 'ct96')


builds = [json.loads(line) for line in qualified('stacks/builds.jsonl').splitlines()]
windows = [build for build in builds if build['sampled']]
original = json.loads(qualified('stacks/cpu-report.json'))
targets = ['check.effects.Store.node', 'check.effects.Store.replacement',
           'check.types.Store.resolveOperationRow', 'check.types.Store.closedHeight']
previous, per_run = {}, Counter()
leaf, inline = Counter(), Counter()
callers = defaultdict(Counter)
paths = defaultdict(Counter)
run_leaf = defaultdict(Counter)
covered = intervals = missing = truncated = 0
for line in qualified('stacks/samples.jsonl').splitlines():
    row = json.loads(line)
    run, end = row['run'], row['wall_ns'] / 1e6
    start = previous.get(run)
    previous[run] = end
    if start is None or not any(b['run'] == run and b['started_ms'] <= start <= end <= b['finished_ms'] for b in windows):
        continue
    intervals += 1
    assert len(row['st']) == len(row['cpu_ns'])
    for stack, ns in zip(row['st'], row['cpu_ns']):
        if ns is None or ns <= 0:
            continue
        covered += ns
        per_run[run] += ns
        if not stack:
            missing += ns
            continue
        if len(stack) >= row.get('frame_limit', 4096):
            truncated += ns
        name = stack[0][0]
        if name not in targets:
            continue
        leaf[name] += ns
        run_leaf[run][name] += ns
        if stack[0][3]:
            inline[name] += ns
        callers[name][f'{stack[1][0]}:{stack[1][2]}' if len(stack) > 1 else '(none)'] += ns
        paths[name][tuple(f'{frame[0]}:{frame[2]}' for frame in stack[1:4])] += ns

assert covered > 0 and missing == truncated == 0
assert intervals == original['complete_intervals']
assert abs(covered / 1e6 - original['covered_cpu_ms']) < 1e-6
for name in targets:
    old = next(row for row in original['self'] if row['name'] == name)
    assert abs(leaf[name] / 1e6 - old['cpu_ms']) < 1e-6


def ranked(counter, denominator):
    return [{'name': name, 'cpu_ms': ns / 1e6, 'percent': ns * 100 / denominator}
            for name, ns in counter.most_common()]


profile = {
    'complete_intervals': intervals, 'covered_cpu_ms': covered / 1e6,
    'coverage_ratio': original['coverage_ratio'],
    'missing_stack_cpu_ms': missing / 1e6, 'truncated_stack_cpu_ms': truncated / 1e6,
    'hotspots': [{
        'name': name, 'self_cpu_percent': 100 * leaf[name] / covered,
        'inline_percent_of_self': 100 * inline[name] / leaf[name],
        'callers_percent_of_self': ranked(callers[name], leaf[name]),
        'paths_percent_of_self': ranked(paths[name], leaf[name])[:5],
        'per_run_self_percent': {str(run): 100 * values[name] / per_run[run]
                                 for run, values in sorted(run_leaf.items())},
    } for name in targets],
    'builds': [],
}
for build in windows:
    stats = build['stats']
    work = stats['backendTiming']['work']
    regions = sorted(work['regions'], key=lambda region: region['us'], reverse=True)
    profile['builds'].append({
        'run': build['run'], 'phase_profile': stats['phaseProfile'],
        'work_us': {key: value for key, value in work.items() if key.endswith('_us')},
        'top_regions': [{**region, 'file': Path(region['file']).name} for region in regions[:3]],
        'region_clock_note': 'Inclusive region lifetimes; do not add to exclusive phase clocks or sampled CPU.',
    })

retained = []
for line in qualified('retained/samples.jsonl').splitlines():
    row = json.loads(line)
    if row['variant'] != 'candidate' or row['phase'] not in ['restart', 'noop', 'edit:literal_in_body', 'edit:body_change']:
        continue
    stats = row['stats']
    retained.append({
        'phase': row['phase'], 'cpu_ms': row['cpu_ms'], 'wall_ms': row['wall_ms'],
        'wasm_sha256': row['wasm_sha256'],
        'backend': stats['backend'],
        'principals': {key: stats['principals'][key] for key in ['requests', 'hits', 'fresh_regions']},
        'selected_queries': {key: stats['selectedQueries'][key] for key in ['lookups', 'candidates', 'reused', 'shared_gates']},
        'constant_receipts': {key: stats['constantReceipts'][key] for key in ['lookups', 'candidates', 'reused']},
        'fresh_modules': stats['freshModules'], 'cached_modules': stats['cachedModules'],
        'rebuilt_seed': stats['attemptStats']['rebuilt_seed'],
    })

native_dir = 'gate/native-execution/run-c1011db08814df28'
native = json.loads(qualified(f'{native_dir}/results.json'))
assert native['success'] and native['allocation_failures'] == 'full'
tests, shard_ns = [], Counter()
for shard in range(4):
    for line in qualified(f'{native_dir}/shard-{shard}.stderr.log').splitlines():
        marker = 'BLOT_NATIVE_TEST\t'
        if marker not in line:
            continue
        test = json.loads(line.split(marker, 1)[1])
        assert test['status'] == 'passed' and test['allocation_failures'] == 'full'
        assert test['leaks'] == test['logged_errors'] == 0
        tests.append({**test, 'shard': shard})
        shard_ns[shard] += test['duration_ns']
assert len(tests) == len(native['inventory']) == len({test['name'] for test in tests}) == 2539
assert {test['name'] for test in tests} == set(native['inventory'])
tests.sort(key=lambda test: test['duration_ns'], reverse=True)
total_ns = sum(shard_ns.values())
gate = {
    'inventory_count': len(tests), 'wall_seconds': native['wall_seconds'],
    'shard_test_seconds': {str(shard): ns / 1e9 for shard, ns in sorted(shard_ns.items())},
    'sum_test_seconds': total_ns / 1e9,
    'ideal_four_shard_seconds_at_fixed_test_cost': total_ns / 4e9,
    'ideal_rebalance_saving_percent': 100 * (1 - total_ns / 4e9 / native['wall_seconds']),
    'top_three_seconds': sum(test['duration_ns'] for test in tests[:3]) / 1e9,
    'top_tests': tests[:8],
}

oom_meta = json.loads(read(args.oom, 'metadata.json', 'oom'))
assert oom_meta['zig_version'] == '0.17.0'
assert all(flag in oom_meta['build_command'] for flag in ['-Doptimize=safe', '-Dllvm=false', '-Doom-profile=true'])
oom_tests = []
for test in oom_meta['tests']:
    assert test['exit_code'] == 0
    sweeps, results = [], []
    for line in read(args.oom, test['stderr'], 'oom').splitlines():
        if 'BLOT_OOM_PROFILE\t' in line:
            sweep = json.loads(line.split('BLOT_OOM_PROFILE\t', 1)[1])
            assert sweep['completed'] and sweep['runs'] == sweep['allocations'] + 1
            for field in ['scenario_source', 'source']:
                sweep[field]['file_name'] = sweep[field]['file_name'].split('/zig-native/', 1)[-1]
            sweeps.append(sweep)
        elif 'BLOT_NATIVE_TEST\t' in line:
            results.append(json.loads(line.split('BLOT_NATIVE_TEST\t', 1)[1]))
    assert len(results) == 1 and results[0]['name'] == test['name']
    assert results[0]['status'] == 'passed' and results[0]['allocation_failures'] == 'full'
    assert results[0]['leaks'] == results[0]['logged_errors'] == 0
    assert len(sweeps) == results[0]['sweeps']['full_sweeps']
    oom_tests.append({
        'name': test['name'], 'wall_seconds': test['wall_seconds'],
        'sweep_seconds': sum(sweep['duration_ns'] for sweep in sweeps) / 1e9,
        'discovered_allocations': sum(sweep['allocations'] for sweep in sweeps),
        'scenario_runs': sum(sweep['runs'] for sweep in sweeps),
        'sweeps_in_fixture_order': sweeps,
    })

report = {
    'compiler_commit': oom_meta['compiler_commit'],
    'scope': 'Post-CT96 diagnosis, not a new optimization or a paired throughput claim.',
    'input_sha256': pins, 'profile': profile, 'retained_single_screen': retained,
    'qualified_native_run': gate, 'oom_profile': {'metadata': oom_meta, 'tests': oom_tests},
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'output': str(args.output), 'profile_intervals': intervals,
                  'native_laws': len(tests), 'oom_sweeps': sum(len(t['sweeps_in_fixture_order']) for t in oom_tests)}, indent=2))
