"""Check the provenance and integrity of the checked-in semantic port."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

PORT = Path(__file__).resolve().parent

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_generated(port: Path = PORT) -> dict:
    source = port / 'generated'
    manifest = json.loads((source / 'manifest.json').read_text())
    lock = json.loads((port / 'reference.lock.json').read_text())
    if manifest['inputSha256'] != lock['semanticSha256'] or manifest['sourceCommit'] != lock['sourceCommit']:
        raise ValueError('generated source does not match the pinned semantic input')
    for field, filename in [('generatorSha256', 'generate.cjs'), ('loopsSha256', 'loops.cjs'),
                            ('vendorSha256', 'vendor/acorn.cjs')]:
        if manifest[field] != sha256(port / filename):
            raise ValueError(f'{filename} changed; regenerate the Carp source')
    expected = manifest['files']
    actual = {path.name for path in source.iterdir() if path.name != 'manifest.json'}
    if set(expected) != actual:
        raise ValueError('generated file list does not match its manifest')
    for name, digest in expected.items():
        if Path(name).name != name or sha256(source / name) != digest:
            raise ValueError(f'generated file differs from manifest: {name}')
    return manifest

if __name__ == '__main__':
    manifest = verify_generated()
    print(f'Verified {manifest["functions"]} native Carp functions in {len(manifest["files"])} generated files.')
