#!/usr/bin/env python3
"""Exercise fail-closed generation and manifest validation in isolated copies."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from verify import PORT, verify_generated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path, help='pinned reference.mjs')
    args = parser.parse_args()
    node = shutil.which(os.environ.get('NODE', 'node'))
    if not node:
        parser.error('Node is required only for regeneration tests')
    text = args.input.read_text()
    manifest = verify_generated()
    checks = 0
    with tempfile.TemporaryDirectory(prefix='carp-generator-test-') as tmp:
        port = Path(tmp) / 'port'
        shutil.copytree(PORT, port, ignore=shutil.ignore_patterns('__pycache__'))
        input_path = Path(tmp) / 'input.mjs'
        output = Path(tmp) / 'output'

        def rejected(source: str, expected: str, update_lock: bool = False) -> None:
            nonlocal checks
            input_path.write_text(source)
            if update_lock:
                lock = json.loads((port / 'reference.lock.json').read_text())
                lock['semanticSha256'] = hashlib.sha256(source.encode()).hexdigest()
                (port / 'reference.lock.json').write_text(json.dumps(lock))
            result = subprocess.run(
                [node, str(port / 'generate.cjs'), str(input_path), str(output)],
                capture_output=True, text=True, timeout=60,
            )
            if result.returncode == 0 or expected not in result.stderr:
                raise AssertionError(f'expected rejection {expected!r}: {result.stderr}')
            if (output / 'manifest.json').exists():
                raise AssertionError('failed generation published a valid-looking manifest')
            checks += 1

        rejected(text + '\n', 'semantic input hash does not match')
        if output.exists():
            raise AssertionError('hash mismatch created an output directory')
        checks += 1
        needle = 'function $initial$() {'
        if text.count(needle) != 1:
            raise AssertionError('pinned initial function changed')
        rejected(text.replace(needle, needle + '\n  try {} catch (error) {}'),
                 'TryStatement', update_lock=True)
        shutil.copy2(PORT / 'reference.lock.json', port / 'reference.lock.json')
        victim = port / 'generated' / 'unit000.carp'
        original = victim.read_bytes()
        victim.write_bytes(original + b'\n')
        try:
            verify_generated(port)
        except ValueError as error:
            if 'generated file differs from manifest' not in str(error):
                raise
        else:
            raise AssertionError('altered generated source was accepted')
        checks += 1
        victim.write_bytes(original)
        (port / 'generated' / 'unexpected.carp').write_text('; unexpected\n')
        try:
            verify_generated(port)
        except ValueError as error:
            if 'file list does not match' not in str(error):
                raise
        else:
            raise AssertionError('untracked generated source was accepted')
        checks += 1
        (port / 'generated' / 'unexpected.carp').unlink()
        if verify_generated(port) != manifest:
            raise AssertionError('restored manifest differs')
        checks += 1
    print(f'Generator: {checks} integrity and fail-closed checks passed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
