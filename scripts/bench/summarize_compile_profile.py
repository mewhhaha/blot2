"""CPU-weighted stack screen for timed compiler profiles, not a receipt proof."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
args = parser.parse_args()
builds = [json.loads(line) for line in (args.directory / 'builds.jsonl').read_text().splitlines() if line]
samples = [json.loads(line) for line in (args.directory / 'samples.jsonl').read_text().splitlines() if line]
selected, occurrences = [], Counter()
for build in builds:
    key = build['run'], build['label']
    occurrences[key] += 1
    if build['sampled'] and build['label'] == 'edit literal_constant' and occurrences[key] > 1:
        selected.append({**build, 'covered_ns': 0, 'constant_ns': 0, 'nested_inference_ns': 0,
                         'serialization_ns': 0, 'other_inference_ns': 0, 'other_backend_ns': 0, 'runtime_emission_ns': 0, 'unattributed_ns': 0, 'owners': Counter()})
previous = {}
for sample in samples:
    run, end = sample['run'], sample['wall_ns'] / 1e6
    start = previous.get(run)
    previous[run] = end
    if start is None:
        continue
    # Drop intervals crossing an edit boundary; charge the missing coverage as
    # unknown rather than assigning another edit's CPU to this one.
    windows = [b for b in selected if b['run'] == run and b['started_ms'] <= start and end <= b['finished_ms']]
    if not windows:
        continue
    assert len(windows) == 1
    build = windows[0]
    for stack, cpu in zip(sample['st'], sample['cpu_ns']):
        if cpu is None or cpu <= 0:
            continue
        build['covered_ns'] += cpu
        constant = any('eval/core_eval.zig' in frame[1] and re.search(r'Session\.(?:constant(?:Inner)?|prepare(?:Work)?)(?:$|\.|\()', frame[0]) for frame in stack)
        static_frames = [i for i, frame in enumerate(stack) if 'backend/backend_static_data.zig' in frame[1]]
        # Serializing a closure can request an entire runtime function. Its
        # checking/replay/emission is not serialization of constant data.
        runtime_emission = bool(static_frames) and any(
            re.search(r'core_backend\.Generator\.(?:callable|function|closureFunction|reconstructRetained)(?:$|__|\.)', frame[0])
            for frame in stack[:min(static_frames)])
        serialization = bool(static_frames) and not runtime_emission
        inference = any('/check/' in frame[1] or '/infer/' in frame[1] for frame in stack)
        if runtime_emission and not constant:
            build['runtime_emission_ns'] += cpu
        if constant:
            build['constant_ns'] += cpu
            if inference:
                build['nested_inference_ns'] += cpu
        elif serialization:
            build['serialization_ns'] += cpu
        owner = next((frame for frame in stack if '/zig-native/src/' in frame[1]), None)
        if (owner is None or len(stack) >= sample.get('frame_limit', 500)) and not constant and not serialization:
            build['unattributed_ns'] += cpu
        elif not constant and not serialization:
            if inference:
                build['other_inference_ns'] += cpu
            elif any('/backend/' in frame[1] for frame in stack):
                build['other_backend_ns'] += cpu
        build['owners'][owner[0] if owner else '(no compiler symbol)'] += cpu
rows = []
owners = Counter()
for build in selected:
    owners.update(build['owners'])
    total = build['cpu_ms'] * 1e6
    unknown = max(0, total - build['covered_ns'])
    rows.append({
        'run': build['run'], 'started_ms': build['started_ms'], 'cpu_ms': build['cpu_ms'],
        'covered_cpu_ms': build['covered_ns'] / 1e6,
        'uncovered_cpu_ms': unknown / 1e6,
        'unattributed_cpu_ms': build['unattributed_ns'] / 1e6,
        'other_inference_cpu_ms': build['other_inference_ns'] / 1e6,
        'other_backend_cpu_ms': build['other_backend_ns'] / 1e6,
        'runtime_emission_beneath_serializer_cpu_ms': build['runtime_emission_ns'] / 1e6,
        'constant_inclusive_cpu_ms': build['constant_ns'] / 1e6,
        'nested_inference_cpu_ms': build['nested_inference_ns'] / 1e6,
        'serialization_cpu_ms': build['serialization_ns'] / 1e6,
        'screen_with_all_uncovered_ms': (build['constant_ns'] + build['serialization_ns'] + unknown + build['unattributed_ns']) / 1e6,
        'stats': build['stats'],
    })
assert rows, 'No timed later-edit samples; use profile_compile_timed.ts first'
per_run = defaultdict(list)
for row in rows:
    per_run[row['run']].append(row)
summary = []
for run, group in per_run.items():
    summary.append({'run': run, **{key: statistics.median(row[key] for row in group) for key in group[0] if key.endswith('_ms')}})
report = {
    'scope': 'Sampling screen of all constant-evaluation/preparation/static-serialization contexts, including changed inputs. Runtime callable emission beneath the serializer is excluded; closure specialization is conservatively included. It does not identify unchanged constants or prove Quantity C. Boundary intervals and missing symbols require review. Instrumented CPU and tick rounding need an uninstrumented control.',
    'later_edits': rows, 'per_run_medians': summary,
    'weighted_compiler_owners_ms': [(name, ns / 1e6) for name, ns in owners.most_common(40)],
}
print(json.dumps(report, indent=2))
