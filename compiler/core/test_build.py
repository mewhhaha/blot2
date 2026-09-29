#!/usr/bin/env python3
"""Clean/incremental/failure recovery tests for the real native builder."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
checks = 0


def check(condition: bool, label: str) -> None:
    global checks
    if not condition:
        raise AssertionError(label)
    checks += 1


with tempfile.TemporaryDirectory(prefix='core-build-test-') as directory:
    stage = Path(directory)
    shutil.copytree(ROOT / 'compiler', stage / 'compiler', ignore=shutil.ignore_patterns(
        '_build', '__pycache__', 'semantic',
    ))
    core = stage / 'compiler/core'
    output = core / '_build'

    def build(ok: bool = True) -> subprocess.CompletedProcess:
        result = subprocess.run(['python3', 'build.py', '-j', '2'], cwd=core,
                                text=True, capture_output=True, timeout=180)
        check((result.returncode == 0) == ok, result.stdout + result.stderr)
        return result

    build()
    digest = lambda: hashlib.sha256((output / 'blotc').read_bytes()).hexdigest()
    initial = digest()
    check('0 modules compiled; linked=False' in build().stdout, 'unchanged build does work')
    check(digest() == initial, 'unchanged build changes executable')
    (output / 'core_text.o').unlink()
    check('0 modules compiled' not in build().stdout, 'missing object was not restored')
    check(digest() == initial, 'restoring an object changes output')
    source = core / 'core_index.ml'
    original = source.read_bytes()
    source.write_bytes(original + b'\nlet deliberately_invalid =\n')
    build(ok=False)
    check(digest() == initial, 'failed compile replaced the last successful executable')
    source.write_bytes(original)
    build()
    check(digest() == initial, 'failure recovery changes output')
    model = stage / 'compiler/model.bend'
    original_model = model.read_text()
    marker = '  FreeTy{scope: String, name: String}\n'
    check(marker in original_model, 'model schema fixture drifted')
    model.write_text(original_model.replace(marker, marker + '  UnreviewedType{}\n', 1))
    failure = build(ok=False)
    check('metadata schema changed' in failure.stderr, 'unreviewed type not rejected by generator')
    model.write_text(original_model)
    build()
    # Two independent invocations must not race their shared build products.
    processes = [subprocess.Popen(['python3', 'build.py', '-j', '2'], cwd=core,
                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(2)]
    for process in processes:
        stdout, stderr = process.communicate(timeout=180)
        check(process.returncode == 0 and '0 modules compiled; linked=False' in stdout, stdout + stderr)
    check(digest() == initial, 'concurrent unchanged builds change output')
    manifest = json.loads((output / 'build-manifest.json').read_text())
    check(manifest['inputs']['compiler/core/build.py'] == hashlib.sha256((core / 'build.py').read_bytes()).hexdigest(),
          'build provenance omits the builder')
print(f'{checks} clean, incremental, schema, concurrent and failed-build checks passed')
