#!/usr/bin/env python3
"""Build official Bend JS reference modules sequentially, without rewriting them."""
from pathlib import Path
import os
import re
import subprocess
import sys
import urllib.request


def main():
    if len(sys.argv) > 2:
        raise SystemExit('Usage: build_compiler_reference.py [source-directory]')
    root = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]
    env = dict(os.environ, BEND_NO_TELEMETRY='1')

    def run(args, **kwargs):
        return subprocess.run(args, cwd=root, env=env, check=True, **kwargs)

    version = run(['bend', 'version'], capture_output=True, text=True).stdout.strip()
    match = re.fullmatch(r'bend (\d+\.\d+\.\d+(?:-[\w.-]+)?)', version, re.IGNORECASE)
    if not match:
        raise RuntimeError(f'Unrecognized Bend version: {version}')
    output = root / 'generated/compiler'
    backend = output / f'bend-{match[1]}'
    backend.mkdir(parents=True, exist_ok=True)
    with (output / 'reference-guide.txt').open('w') as guide:
        run(['bend', 'guide'], stdout=guide)
    run(['bend', 'PROOF.bend'])
    for name in ['main.ts', 'bend.ts', 'comp.ts', 'safe.ts', 'base.bend']:
        with urllib.request.urlopen(f'https://raw.githubusercontent.com/bendlang/bend/v{match[1]}/bend2/{name}', timeout=120) as source:
            (backend / name).write_bytes(source.read())
    program = '''const { load } = await import(process.argv[1]);
const result = await load(process.argv[2], {}, () => { throw new Error("Unrecognized compiler entry"); });
process.stdout.write(result.source);'''
    for module, name in [('main', 'compiler'), ('native_session', 'native_session'), ('native_output', 'native_output')]:
        temporary = output / f'.{name}.js.tmp'
        try:
            with temporary.open('wb') as handle:
                run(['bun', '--eval', program, (backend / 'main.ts').as_uri(), (root / f'compiler/{module}.bend').as_uri()], stdout=handle)
            temporary.replace(output / f'{name}.js')
        finally:
            temporary.unlink(missing_ok=True)
    (output / 'reference-version.txt').write_text(version + '\n')


if __name__ == '__main__':
    main()
