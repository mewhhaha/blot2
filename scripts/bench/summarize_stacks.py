"""CPU-weighted compiler stack attribution (inclusive rows overlap).

python3 scripts/bench/summarize_stacks.py PROFILE_DIRECTORY
Only complete sampling intervals inside a measured build count. Thread CPU
deltas weight endpoint stacks; work ending in a wait can remain unattributed.
Missing boundaries and truncated stacks remain visible. Profiling is diagnostic.
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
checking, normalization_callers, checking_families = (Counter() for _ in range(3))
validation = Counter()
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
        names = [f[0] for f in stack]
        if any(n.startswith('reuse.dependency_closure.validateMode') for n in names):
            validation['all'] += weight
            bucket = 'other'
            for label, prefix in [('bounds', 'check.frozen_core_validation.validateBounds'),
                                  ('task_context', 'check.task_core.validateContextWorkspace'),
                                  ('cycles', 'check.frozen_core_validation.cycles'),
                                  ('principal_interfaces', 'reuse.dependency_interface_validation.'),
                                  ('list_roles', 'check.frozen_core_validation.listRoles')]:
                if any(n.startswith(prefix) for n in names):
                    bucket = label
                    break
            validation[bucket] += weight
        if any(n.startswith(('reuse.project_check.', 'check.check.')) for n in names):
            checking['all'] += weight
            unification = any(n.startswith('check.types.Store.unifyMode') for n in names)
            if unification: checking['unification_inclusive'] += weight
            resolving = [i for i, n in enumerate(names) if n.startswith('check.types.Store.resolve')]
            if resolving:
                checking['normalization_inclusive'] += weight
                if unification: checking['normalization_under_unification'] += weight
                caller = max(resolving) + 1
                normalization_callers[names[caller] if caller < len(names) else '(unresolved caller)'] += weight
            for label, prefix in [('scheme_import', 'check.check_scheme_import.'),
                                  ('body_cache', 'reuse.body_check_cache.'),
                                  ('substitution', 'check.types.Store.substitute'),
                                  ('covariance_open', 'check.types.Store.openCovariant'),
                                  ('free_rows', 'check.types.Store.freeRowVariables')]:
                if any(n.startswith(prefix) for n in names): checking_families[label] += weight
missing_cpu = sum(b.get('cpu_ms') is None for b in windows)
process_ms = None
if not missing_cpu: process_ms = sum(b['cpu_ms'] for b in windows)
build_process_ms = process_ms
cpu_scope = 'whole measured build'
focus_path = root / 'sampling-window.json'
if len(windows) == 1 and focus_path.exists():
    focus = json.loads(focus_path.read_text())
    if focus.get('focus') == 'emission' and focus.get('focus_reached') and focus.get('process_cpu_ms') is not None:
        process_ms = focus['process_cpu_ms']
        cpu_scope = 'owned.emit sampling window'
def ranked(counter):
    return [{'name': name, 'cpu_ms': ns / 1e6, 'sampled_cpu_percent': 100 * ns / covered} for name, ns in counter.most_common(40)]
report = {'scope': __doc__.split('\n')[0], 'builds': len(windows), 'complete_intervals': intervals,
          'discarded_boundary_intervals': discarded, 'sampled_process_cpu_ms': process_ms,
          'process_cpu_scope': cpu_scope, 'whole_build_process_cpu_ms': build_process_ms,
          'covered_cpu_ms': covered / 1e6, 'coverage_ratio': covered / 1e6 / process_ms if process_ms else None,
          'missing_process_cpu_builds': missing_cpu,
          'uncovered_cpu_ms': max(0, process_ms - covered / 1e6) if process_ms is not None else None, 'missing_stack_cpu_ms': unknown / 1e6,
          'truncated_stack_cpu_ms': truncated / 1e6, 'self': ranked(leaf), 'compiler_owner': ranked(owner),
          'compiler_directory': ranked(directories), 'inclusive_overlapping': ranked(inclusive), 'hot_lines': ranked(lines)}
report['checking'] = {
    'scope': 'Stacks containing project_check/check.Engine frames; inclusive categories overlap, and missing callers are outside this cohort.',
    'cpu_ms': {name: weight / 1e6 for name, weight in checking.items()},
    'normalization_callers': [{'name': name, 'cpu_ms': weight / 1e6,
                               'checking_sample_cpu_percent': 100 * weight / checking['all']}
                              for name, weight in normalization_callers.most_common(40)],
    'other_inclusive_ms': {name: weight / 1e6 for name, weight in checking_families.items()},
}
report['validation'] = {
    'scope': 'Closure validateMode stacks; first matching bucket is exclusive. Source identity checks and backend entry/bounds validation are outside this cohort.',
    'cpu_ms': validation['all'] / 1e6,
    'buckets': [{'name': name, 'cpu_ms': weight / 1e6,
                  'validation_sample_cpu_percent': 100 * weight / validation['all']}
                for name, weight in validation.items() if name != 'all'],
}
assert covered > 0
(root / 'cpu-report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: report[key] for key in ['builds', 'complete_intervals', 'coverage_ratio', 'truncated_stack_cpu_ms', 'compiler_owner']}, indent=2))
