#!/usr/bin/env python3
"""Build the official, unmodified Bend JavaScript reference for this checkout.

Sequential module builds bound peak memory. No generated code is transformed.
Pass another checkout directory to build the same modules for a baseline.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import urllib.request

root = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]
if len(sys.argv) > 2:
    raise SystemExit('Usage: build_compile_reference.py [checkout]')
env = dict(os.environ, BEND_NO_TELEMETRY='1')
def run(args, **kwargs):
    return subprocess.run(args, cwd=root, env=env, check=True, **kwargs)
version = run(['bend', 'version'], capture_output=True, text=True).stdout.strip()
match = re.fullmatch(r'bend (\d+\.\d+\.\d+(?:-[\w.-]+)?)', version, re.IGNORECASE)
if not match:
    raise RuntimeError(f'Unrecognized Bend release: {version}')
print(version, flush=True)
run(['bend', 'PROOF.bend'])
output = root / 'generated/compiler'
backend = output / f'bend-{match[1]}'
backend.mkdir(parents=True, exist_ok=True)
for name in ['main.ts', 'bend.ts', 'comp.ts', 'safe.ts', 'base.bend']:
    url = f'https://raw.githubusercontent.com/bendlang/bend/v{match[1]}/bend2/{name}'
    with urllib.request.urlopen(url, timeout=120) as source:
        (backend / name).write_bytes(source.read())
program = '''const {load} = await import(process.argv[1]);
const result = await load(process.argv[2], {}, () => { throw new Error("Unknown Bend entry"); });
process.stdout.write(result.source);'''
for entry, target in [('main', 'compiler'), ('native_session', 'native_session'), ('native_output', 'native_output')]:
    temporary = output / f'.{target}.js.tmp'
    try:
        with temporary.open('wb') as handle:
            run(['bun', '--eval', program, (backend / 'main.ts').as_uri(),
                 (root / 'compiler' / f'{entry}.bend').as_uri()], stdout=handle)
        temporary.replace(output / f'{target}.js')
    finally:
        temporary.unlink(missing_ok=True)
(output / 'compile-reference-version.txt').write_text(version + '\n')
