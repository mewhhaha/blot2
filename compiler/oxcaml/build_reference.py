#!/usr/bin/env python3
"""Build the unmodified Bend JavaScript reference sequentially.

Uses exactly the installed release's official loader and Base, as the existing
build script does. Sequential module builds bound peak memory in parity CI.
This script is not needed to build or run the OxCaml compiler itself.
"""
from __future__ import annotations
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[2]

def main() -> None:
    environment = dict(os.environ, BEND_NO_TELEMETRY='1')
    def run(args, **kwargs):
        return subprocess.run(args, cwd=ROOT, env=environment, check=True, **kwargs)
    version = run(['bend', 'version'], capture_output=True, text=True).stdout.strip()
    match = re.fullmatch(r'bend (\d+\.\d+\.\d+(?:-[\w.-]+)?)', version, re.IGNORECASE)
    if not match:
        raise RuntimeError(f'Unrecognized Bend release: {version}')
    release = match[1]
    output = ROOT / 'generated/compiler'
    output.mkdir(parents=True, exist_ok=True)
    with (output / 'reference-guide.txt').open('w') as guide:
        run(['bend', 'guide'], stdout=guide)
    run(['bend', 'PROOF.bend'])
    backend = output / f'bend-{release}'
    backend.mkdir(exist_ok=True)
    for name in ['main.ts', 'bend.ts', 'comp.ts', 'safe.ts', 'base.bend']:
        url = f'https://raw.githubusercontent.com/bendlang/bend/v{release}/bend2/{name}'
        with urllib.request.urlopen(url, timeout=120) as source:
            (backend / name).write_bytes(source.read())
    program = '''const { load } = await import(process.argv[1]);
const result = await load(process.argv[2], {}, () => {
  throw new Error("Bend loader did not recognize the compiler entry");
});
process.stdout.write(result.source);'''
    for module, filename in [('main', 'compiler'), ('native_session', 'native_session'), ('native_output', 'native_output')]:
        print(f'Building unchanged {filename}.js with {version}', flush=True)
        destination = output / f'{filename}.js'
        temporary = output / f'.{filename}.js.tmp'
        try:
            with temporary.open('wb') as handle:
                run(['bun', '--eval', program, (backend / 'main.ts').as_uri(),
                     (ROOT / 'compiler' / f'{module}.bend').as_uri()], stdout=handle)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    (output / 'reference-version.txt').write_text(version + '\n')

if __name__ == '__main__':
    main()
