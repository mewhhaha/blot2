#!/usr/bin/env python3
"""Run `goose check` from two checker builds over upstream's test programs and compare."""
import concurrent.futures, json, pathlib, subprocess, sys
a, b, stdlib, tests = sys.argv[1], sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
files = sorted(p for p in tests.rglob('*.goose'))
def run(binary, path):
    try:
        p = subprocess.run([binary, 'check', str(path), '--stdlib', stdlib, '--diagnostics', 'json'],
                           capture_output=True, text=True, timeout=60, cwd=path.parent)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 'timeout', ''
def both(path):
    return path, run(a, path), run(b, path)
diffs, total = [], 0
with concurrent.futures.ThreadPoolExecutor(4) as pool:
    for path, x, y in pool.map(both, files):
        total += 1
        if x != y: diffs.append(str(path))
print(json.dumps({'programs': total, 'differences': len(diffs), 'first': diffs[:20]}, indent=1))
