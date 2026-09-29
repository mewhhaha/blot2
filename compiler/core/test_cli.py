#!/usr/bin/env python3
"""Exercise the explicit native CLI task with no JavaScript compiler backend."""
from __future__ import annotations
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
checks = 0


def check(condition: bool, message: str) -> None:
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1


with tempfile.TemporaryDirectory(prefix='core-cli-test-') as directory:
    stage = Path(directory)
    for name in ['compiler', 'generated', 'std', 'examples']:
        shutil.copytree(ROOT / name, stage / name, ignore=shutil.ignore_patterns(
            '_build', '__pycache__', 'compiler.js', 'native_session.js',
            'native_output.js', 'blotc', 'bend-*', 'node_modules'))
    for name in ['deno.json', 'deno.lock', 'baba.json']:
        shutil.copyfile(ROOT / name, stage / name)
    executable = stage / 'compiler/core/_build/blotc'
    executable.parent.mkdir(parents=True)
    shutil.copyfile(ROOT / 'compiler/core/_build/blotc', executable)
    executable.chmod(0o755)
    check(not list((stage / 'generated/compiler').glob('*.js')),
          'CLI fixture must not contain a JavaScript compiler backend')
    deno = os.environ.get('DENO', 'deno')

    def cli(*arguments: str, code: int = 0) -> subprocess.CompletedProcess:
        result = subprocess.run([deno, 'task', 'blot:core', *arguments], cwd=stage,
                                capture_output=True, text=True, timeout=60)
        check(result.returncode == code, result.stdout + result.stderr)
        return result

    cli('check', 'examples/generic_effects.blot')
    cli('build', 'examples/scalar.blot', 'output/scalar.wasm')
    check((stage / 'output/scalar.wasm').read_bytes().startswith(b'\0asm'), 'CLI did not write Wasm')
    result = subprocess.run([deno, 'eval',
        'const {instance}=await WebAssembly.instantiate(await Deno.readFile("output/scalar.wasm")); console.log(instance.exports.answer());'],
        cwd=stage, capture_output=True, text=True, timeout=30)
    check(result.returncode == 0 and result.stdout.strip() == '42', result.stdout + result.stderr)
    guide = cli('guide')
    check(guide.stdout.strip() == (stage / 'compiler/guide.md').read_text().strip(), 'CLI guide differs')
    source = stage / 'format.blot'
    source.write_text('entry   const answer = fn () => 42\n')
    original = source.read_bytes()
    cli('fmt', 'format.blot', '--check', code=1)
    check(source.read_bytes() == original, 'fmt --check modified source')
    cli('fmt', 'format.blot')
    cli('fmt', 'format.blot', '--check')
    cli('check', 'format.blot')
    invalid = stage / 'invalid.blot'
    invalid.write_text('entry const answer = fn () => missing\n')
    error = cli('check', 'invalid.blot', code=1)
    check('missing' in error.stderr and 'invalid.blot' in error.stderr, 'CLI lost source diagnostic')
    cli(code=2)
    cli('build', 'format.blot', 'out.wasm', 'extra', code=2)
    cli('check', 'absent.blot', code=1)
    # Leave a default backend at its ordinary path, then remove the core. The
    # explicit task must fail rather than silently selecting that backend.
    fallback = stage / 'generated/compiler/blotc'
    fallback.write_text('#!/bin/sh\nprintf used > fallback-used\nexit 1\n')
    fallback.chmod(0o755)
    executable.rename(executable.with_name('blotc.saved'))
    missing = cli('check', 'format.blot', code=1)
    check('blotc' in missing.stderr, 'missing core executable was not reported')
    check(not (stage / 'fallback-used').exists(), 'CLI silently ran the default backend')
    cli('guide')
print(f'{checks} explicit native CLI, Wasm, formatting, diagnostic and no-fallback checks passed')
