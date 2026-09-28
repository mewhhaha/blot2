#!/usr/bin/env python3
"""Link the same decode-only probe against an already-built compiler checkout.

Build the checkout with its normal Makefile first. This helper never modifies
its source files; each probe has a private directory under that checkout's
_build. Use the same compiler and flags as the native executable being compared.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess

HERE = Path(__file__).resolve().parent

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--compiler', default=os.environ.get('OCAMLOPT', 'ocamlopt'))
    parser.add_argument('--flags', default=os.environ.get('OCAMLFLAGS', '-g -w -8-11-26-27'))
    args = parser.parse_args()
    compiler = shutil.which(args.compiler)
    if not compiler:
        parser.error(f'compiler not found: {args.compiler}')
    native = args.checkout.resolve(strict=True) / 'compiler/oxcaml'
    build = native / '_build'
    modules = ['native_runtime', 'native_parallel', 'base',
               *(native / 'core/modules.txt').read_text().split()]
    objects = [build / f'{name}.cmx' for name in modules]
    objects.insert(0, build / 'runtime_stubs.o')
    missing = [str(path) for path in objects if not path.is_file()]
    if missing:
        parser.error('build the native checkout first; missing: ' + ', '.join(missing))
    staging = build / 'decoder-probe'
    staging.mkdir(exist_ok=True)
    shutil.copyfile(HERE / 'decode_probe.ml', staging / 'decode_probe.ml')
    major = int(subprocess.check_output([compiler, '-version'], text=True).split('.')[0])
    includes = ['-I', str(build), '-I', '+threads']
    if major >= 5:
        includes += ['-I', '+unix']
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [compiler, *shlex.split(args.flags), *includes,
               '-o', str(output), 'unix.cmxa', 'threads.cmxa',
               *map(str, objects), 'decode_probe.ml']
    subprocess.run(command, cwd=staging, check=True)
    print(output)

if __name__ == '__main__':
    main()
