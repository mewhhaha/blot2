#!/usr/bin/env python3
"""Run unchanged native regression tests with the OxCaml executable.

An isolated workspace selects the native executable at the host's conventional
path. No tests, host modules, Bend source, or emitted C/JavaScript are patched;
the caller's generated/compiler/blotc is never changed.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, default=ROOT / 'compiler/oxcaml/_build/blotc')
    parser.add_argument('--deno', default='deno')
    parser.add_argument('--report', type=Path)
    parser.add_argument('tests', nargs='*', help='Repository-relative test paths; defaults to native regression suites')
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    if not (ROOT / 'generated/compiler/compiler.js').is_file():
        parser.error('build the unchanged JavaScript reference first: python3 compiler/oxcaml/build_reference.py')
    selected = args.tests or sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'compiler').glob('*.test.ts')
        if ('native' in p.name or p.name == 'guest_native.test.ts'))
    for name in selected:
        path = (ROOT / name).resolve(strict=True)
        if ROOT not in path.parents or not path.name.endswith('.test.ts'):
            parser.error(f'invalid repository test path: {name}')
    report = {
        'executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
        'tests': selected,
        'excluded': {},
    }
    print(f'Running {len(selected)} unchanged native regression files against {executable}', flush=True)
    with tempfile.TemporaryDirectory(prefix='blot-oxcaml-tests-') as directory:
        stage = Path(directory)
        for name in ['compiler', 'generated', 'examples', 'std', 'scripts', 'case-study']:
            shutil.copytree(ROOT / name, stage / name,
                ignore=shutil.ignore_patterns('_build', '__pycache__', '_opam', 'node_modules', '.native-backend-*'))
        for name in ['deno.json', 'deno.lock']:
            if (ROOT / name).is_file():
                shutil.copy2(ROOT / name, stage / name)
        target = stage / 'generated/compiler/blotc'
        shutil.copyfile(executable, target)
        target.chmod(0o755)
        result = subprocess.run([args.deno, 'test', '--allow-all', '--fail-fast', *selected], cwd=stage, check=False)
        report['exit_code'] = result.returncode
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    return result.returncode

if __name__ == '__main__':
    raise SystemExit(main())
