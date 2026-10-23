"""CPU-weighted compiler stack attribution (inclusive rows overlap).

python3 scripts/bench/summarize_stacks.py PROFILE_DIRECTORY
Only complete sampling intervals inside a measured build count. Idle thread
stacks have zero weight. Missing boundaries and truncated stacks remain visible;
profiling CPU is diagnostic, never a substitute for uninstrumented timing.
"""
import argparse
from collections import Counter
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
args = parser.parse_args()
root = args.directory
builds = [json.loads(line) for line in (root / 'builds.jsonl').read_text().splitlines() if line]
windows = [b for b in builds if b['sampled']]
assert windows, 'No sampled build windows'
rows = [json.loads(line) for line in (root / 'samples.jsonl').read_text().splitlines() if line]
leaf, owner, inclusive, directories, lines = (Counter() for _ in range(5))
previous = {}
covered = unknown = truncated = intervals = discarded = 0
for row in rows:
    run, end = row['run'], row['wall_ns'] / 1e6
    start = previous.get(run)
    previous[run] = end
    if start is None or not any(b['run'] == run and b['started_ms'] <= start <= end <= b['finished_ms'] for b in windows):
        discarded += 1
        continue
    intervals += 1
    assert len(row['st']) == len(row['cpu_ns'])
    for stack, weight in zip(row['st'], row['cpu_ns']):
        if weight is None or weight <= 0: continue
        covered += weight
        if not stack:
            unknown += weight
            continue
        if len(stack) >= row.get('frame_limit', 4096): truncated += weight
        leaf[stack[0][0]] += weight
        lines[f'{stack[0][0]} {stack[0][1]}:{stack[0][2]}'] += weight
        owned = next((f for f in stack if '/zig-native/src/' in f[1]), None)
        owner[owned[0] if owned else '(no compiler frame)'] += weight
        directories[owned[1].split('/zig-native/src/', 1)[1].split('/')[0] if owned else '(no compiler frame)'] += weight
        for name in set(f[0] for f in stack): inclusive[name] += weight
process_ms = sum(b['cpu_ms'] for b in windows)
def ranked(counter):
    return [{'name': name, 'cpu_ms': ns / 1e6, 'sampled_cpu_percent': 100 * ns / covered} for name, ns in counter.most_common(40)]
report = {'scope': __doc__.split('\n')[0], 'builds': len(windows), 'complete_intervals': intervals,
          'discarded_boundary_intervals': discarded, 'sampled_process_cpu_ms': process_ms,
          'covered_cpu_ms': covered / 1e6, 'coverage_ratio': covered / 1e6 / process_ms,
          'uncovered_cpu_ms': max(0, process_ms - covered / 1e6), 'missing_stack_cpu_ms': unknown / 1e6,
          'truncated_stack_cpu_ms': truncated / 1e6, 'self': ranked(leaf), 'compiler_owner': ranked(owner),
          'compiler_directory': ranked(directories), 'inclusive_overlapping': ranked(inclusive), 'hot_lines': ranked(lines)}
assert covered > 0
(root / 'cpu-report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: report[key] for key in ['builds', 'complete_intervals', 'coverage_ratio', 'truncated_stack_cpu_ms', 'compiler_owner']}, indent=2))
