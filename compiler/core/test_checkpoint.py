#!/usr/bin/env python3
"""Verify, restore and exercise an exact native-core checkpoint in isolation.

A supplied bundle's base must exist in the current repository. No network,
credentials, remote ref updates or automatic pushes are used by this test.
"""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
checks = 0


def check(condition: bool, message: str) -> None:
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1


def git(path: Path, *arguments: str, data: bytes | None = None) -> bytes:
    return subprocess.check_output(['git', *arguments], cwd=path, input=data,
                                   stderr=subprocess.PIPE)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def extract(archive: Path, destination: Path) -> None:
    with tarfile.open(archive) as source:
        source.extractall(destination, filter='data')


def reconstruct(path: Path, archive: Path, revision: str, commit: bytes) -> None:
    path.mkdir()
    extract(archive, path)
    git(path, 'init', '-q', '-b', 'checkpoint')
    git(path, 'add', '--force', '--all')
    tree = git(path, 'write-tree').decode().strip()
    check(commit.splitlines()[0] == ('tree ' + tree).encode(), 'source archive Git tree differs')
    found = git(path, 'hash-object', '-t', 'commit', '-w', '--stdin', data=commit).decode().strip()
    check(found == revision, 'source commit identity differs')
    (path / '.git/shallow').write_text(revision + '\n')
    git(path, 'update-ref', 'refs/heads/checkpoint', revision)
    check(not git(path, 'status', '--porcelain').strip(), 'restored source is not clean')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkpoint', type=Path)
    parser.add_argument('--source-only', action='store_true',
                        help='Restore from the self-contained source archive, without a base repository')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='core-restore-test-') as directory:
        scratch = Path(directory)
        envelope = scratch / 'envelope'
        envelope.mkdir()
        with ZipFile(args.checkpoint) as archive:
            record = json.loads(archive.read('checkpoint.json'))
            for name, identity in record['files'].items():
                path = (envelope / name).resolve()
                check(envelope in path.parents, 'unsafe checkpoint member path')
                data = archive.read(name)
                check(len(data) == identity['bytes'] and digest(data) == identity['sha256'],
                      'checkpoint member digest differs: ' + name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        revision = record['revision']
        commit = (envelope / 'commit.txt').read_bytes() if (envelope / 'commit.txt').exists() else git(ROOT, 'cat-file', 'commit', revision)
        stage = scratch / 'source'
        if not args.source_only and record.get('base') and (envelope / 'changes.bundle').exists():
            base = record['base']
            base_archive = scratch / 'base.tar.gz'
            base_archive.write_bytes(git(ROOT, 'archive', '--format=tar.gz', base))
            reconstruct(stage, base_archive, base, git(ROOT, 'cat-file', 'commit', base))
            git(stage, 'bundle', 'verify', str(envelope / 'changes.bundle'))
            git(stage, 'fetch', '--no-tags', str(envelope / 'changes.bundle'), 'HEAD')
            git(stage, 'merge', '--ff-only', 'FETCH_HEAD')
            check(git(stage, 'rev-parse', 'HEAD').decode().strip() == revision, 'bundle did not restore exact HEAD')
            check(git(stage, 'cat-file', 'commit', revision) == commit, 'bundle commit differs from archive')
        else:
            reconstruct(stage, envelope / 'source.tar.gz', revision, commit)
        build = stage / 'compiler/core/_build'
        build.mkdir(parents=True, exist_ok=True)
        for source in (envelope / 'native/source').iterdir():
            shutil.copyfile(source, build / source.name)
        shutil.copyfile(envelope / 'native/blotc', build / 'blotc')
        shutil.copyfile(envelope / 'native/build-manifest.json', build / 'build-manifest.json')
        binary = build / 'blotc'
        binary.chmod(0o755)
        manifest = json.loads((build / 'build-manifest.json').read_text())
        for name, expected in manifest['inputs'].items():
            check(digest((stage / name).read_bytes()) == expected, 'restored build input differs: ' + name)
        for name, expected in manifest['sources'].items():
            check(digest((build / name).read_bytes()) == expected, 'restored generated source differs: ' + name)
        check(digest(binary.read_bytes()) == record['executable_sha256'], 'restored executable differs')
        result = subprocess.run([str(binary)], input=b'', capture_output=True, timeout=15)
        check(result.returncode == 0 and result.stderr == b'', 'restored executable does not exit cleanly')
        # Protocol version is checked by the repository's own native tests;
        # this gate additionally verifies that the standalone artifact runs.
        check(len(result.stdout) == 12 and struct.unpack('<II', result.stdout[:8]) == (2, 0x424C4F54),
              'restored executable has no valid handshake')
        repacked = scratch / 'repacked.zip'

        def package(expected_success: bool) -> None:
            result = subprocess.run([sys.executable, str(stage / 'compiler/core/checkpoint.py'),
                                     '--output', str(repacked)], cwd=stage,
                                    capture_output=True, text=True, timeout=30)
            check((result.returncode == 0) == expected_success, result.stdout + result.stderr)

        package(True)
        # Checkpointing and compilation use the same lock; an in-progress
        # build cannot be sampled halfway through replacing its products.
        with (build / '.build.lock').open('a') as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            child = subprocess.Popen([sys.executable, str(stage / 'compiler/core/checkpoint.py'),
                                      '--output', str(repacked)], cwd=stage,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                time.sleep(0.2)
                check(child.poll() is None, 'checkpoint ignored an active build lock')
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
                output, errors = child.communicate(timeout=30)
                check(child.returncode == 0, output.decode() + errors.decode())
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate()
        for damaged in [build / 'core_levels.ml', stage / 'compiler/core/core_levels.ml',
                        binary, stage / 'compiler/core/README.md']:
            original = damaged.read_bytes()
            damaged.write_bytes(original + b'\ncorruption for negative checkpoint test\n')
            package(False)
            damaged.write_bytes(original)
        package(True)
    print(f'{checks} checkpoint checksum, Git recovery, executable and rejection checks passed')


if __name__ == '__main__':
    main()
