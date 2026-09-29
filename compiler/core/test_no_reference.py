#!/usr/bin/env python3
"""Run real source and edit smoke tests in a checkout with no JS compiler files."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='core-no-reference-') as directory:
    stage = Path(directory)
    for name in ['compiler', 'generated', 'std', 'examples']:
        shutil.copytree(ROOT / name, stage / name, ignore=shutil.ignore_patterns(
            '_build', '__pycache__', 'compiler.js', 'native_session.js', 'native_output.js',
            'blotc', 'bend-*', 'node_modules',
        ))
    for name in ['deno.json', 'deno.lock', 'baba.json']:
        shutil.copyfile(ROOT / name, stage / name)
    executable = stage / 'compiler/core/_build/blotc'
    executable.parent.mkdir(parents=True)
    shutil.copyfile(ROOT / 'compiler/core/_build/blotc', executable)
    executable.chmod(0o755)
    assert not list((stage / 'generated/compiler').glob('*.js'))
    subprocess.run([os.environ.get('DENO', 'deno'), 'run', '--allow-all',
                    'compiler/core/smoke.ts'], cwd=stage, check=True, timeout=120)
