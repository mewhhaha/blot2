#!/usr/bin/env python3
"""Regenerate the hash-locked semantic input and compare every emitted byte."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from verify import PORT, verify_generated

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path)
    args=parser.parse_args()
    node=shutil.which(os.environ.get('NODE','node'))
    if not node:parser.error('NODE (default node) is required only for regeneration')
    manifest=verify_generated()
    with tempfile.TemporaryDirectory(prefix='carp-regenerate-') as directory:
        output=Path(directory)
        subprocess.run([node,str(PORT/'generate.cjs'),str(args.input.resolve()),str(output)],check=True,stdout=subprocess.DEVNULL)
        names=set(manifest['files'])|{'manifest.json'}
        if {p.name for p in output.iterdir()}!=names:raise RuntimeError('regenerated file list differs')
        for name in sorted(names):
            if (output/name).read_bytes()!=(PORT/'generated'/name).read_bytes():
                raise RuntimeError(f'regeneration differs: {name}')
    print(f'Deterministic regeneration matched {len(names)} files byte for byte.')
    return 0

if __name__=='__main__':raise SystemExit(main())
