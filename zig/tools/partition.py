#!/usr/bin/env python3
"""Partition every retained test; isolate the four long codegen cases.

The companion check_test_partition.ts checks the real registered test names.
A changed or additional case fails that inventory check instead of disappearing
behind a filter. The original test source and workload stay unchanged.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

CODEGEN = 'compiler/codegen_native_parallel.test.ts'
THREADS = (1, 2, 4, 8)
GROUPS = ('0', '1', '2', '3', *(f'codegen-{n}' for n in THREADS))


def select(files: list[str], group: str) -> tuple[list[str], str]:
    files = sorted(files)
    if len(files) != len(set(files)) or CODEGEN not in files:
        raise ValueError('expected unique test files including the codegen workload')
    if group not in GROUPS:
        raise ValueError(f'unknown compatibility group: {group}')
    if group.startswith('codegen-'):
        threads = int(group.split('-')[1])
        return [CODEGEN], f'/^native {threads}-thread codegen compiles only independent cache misses$/'
    # Keep the old source-order shards; only the expensive file moves into its
    # four independent groups. Every other present or future file is selected.
    return [f for i, f in enumerate(files) if i % 4 == int(group) and f != CODEGEN], ''


def main() -> None:
    if len(sys.argv) != 2:
        raise ValueError('usage: partition.py GROUP')
    root = Path(__file__).resolve().parents[2]
    files = [p.relative_to(root).as_posix() for p in (root / 'compiler').glob('*.test.ts')]
    selected, pattern = select(files, sys.argv[1])
    if not selected:
        raise ValueError('empty compatibility group')
    output = root / 'build/zig-validation'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'test-files.txt').write_text(''.join(f'{f}\n' for f in selected))
    (output / 'test-filter.txt').write_text(pattern + '\n')
    (output / 'selection.json').write_text(json.dumps({
        'group': sys.argv[1], 'files': selected, 'filter': pattern,
        'all_test_files': sorted(files), 'all_groups': GROUPS,
    }, indent=2) + '\n')
    print('\n'.join(selected))
    print('filter:', pattern or '(all tests in selected files)')


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
