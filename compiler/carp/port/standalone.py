#!/usr/bin/env python3
"""Test the public Carp APIs with no Bend compiler or generated Bend JavaScript.

Copies only host/frontend TypeScript, parser Wasm, example and standard-library
sources, and the Carp executable into an isolated tree. No oracle is copied.
"""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[3]

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable',type=Path,default=ROOT/'generated/carp-port/blotc-carp-native')
    args=parser.parse_args()
    deno=shutil.which(os.environ.get('DENO','deno'))
    if not deno:parser.error('DENO (default deno) must be executable')
    binary=args.executable.resolve()
    if not binary.is_file():parser.error('build the native Carp compiler first')
    print('Standalone binary SHA256: '+hashlib.sha256(binary.read_bytes()).hexdigest(),flush=True)
    with tempfile.TemporaryDirectory(prefix='blot-carp-standalone-') as tmp:
        tree=Path(tmp)
        for name in ['deno.json','deno.lock']:
            shutil.copy2(ROOT/name,tree/name)
        for folder in ['std','examples','generated/wasm']:
            shutil.copytree(ROOT/folder,tree/folder)
        for source in (ROOT/'compiler').glob('*.ts'):
            dest=tree/source.relative_to(ROOT)
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,dest)
        shutil.copy2(ROOT/'compiler/guide.md',tree/'compiler/guide.md')
        for name in ['backend.test.ts','eof.test.ts','cli.ts','worker_probe.ts']:
            dest=tree/'compiler/carp'/name
            dest.parent.mkdir(exist_ok=True)
            shutil.copy2(ROOT/'compiler/carp'/name,dest)
        dest=tree/'generated/carp-port/blotc-carp-native'
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(binary,dest)
        if (tree/'generated/compiler').exists():
            raise RuntimeError('standalone test unexpectedly contains a reference compiler')
        env=dict(os.environ)
        env.setdefault('DENO_DIR',str(ROOT/'.deno-cache'))
        result=subprocess.run([deno,'test','--allow-read=compiler,generated,examples,std',
           '--allow-run=generated/carp-port/blotc-carp-native','compiler/carp/backend.test.ts','compiler/carp/eof.test.ts'],cwd=tree,env=env)
        if result.returncode:return result.returncode
        result=subprocess.run([deno,'run','--allow-read=generated',
          '--allow-run=generated/carp-port/blotc-carp-native','compiler/carp/worker_probe.ts'],cwd=tree,env=env)
        if result.returncode:return result.returncode
        for command in [['guide'],['check','examples/records.blot'],['build','examples/arrays.blot','build/arrays.wasm']]:
            result=subprocess.run([deno,'run','--allow-read','--allow-write=build',
              '--allow-run=generated/carp-port/blotc-carp-native','compiler/carp/cli.ts',*command],
              cwd=tree,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            if result.returncode:
                print(result.stderr.decode(errors='replace'))
                return result.returncode
        wasm=(tree/'build/arrays.wasm').read_bytes()
        if not wasm.startswith(b'\0asm\1\0\0\0'):raise RuntimeError('CLI did not produce Wasm')
        (tree/'examples/invalid.blot').write_text('entry const answer = missing\n')
        result=subprocess.run([deno,'run','--allow-read','--allow-write=build',
          '--allow-run=generated/carp-port/blotc-carp-native','compiler/carp/cli.ts','build',
          'examples/invalid.blot','build/arrays.wasm'],cwd=tree,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if result.returncode==0 or (tree/'build/arrays.wasm').read_bytes()!=wasm:
            raise RuntimeError('failed compilation overwrote the existing artifact')
        print('Standalone: public APIs and CLI passed without generated/compiler, Bend, or a fallback.')
    return 0

if __name__=='__main__':raise SystemExit(main())
