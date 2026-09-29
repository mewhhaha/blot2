#!/usr/bin/env python3
"""Archive an exact committed core build and optional validation evidence.

Source, generated native modules, executable and checksums travel together.
This command never uploads anything or changes Git refs. A clean working tree
and matching build-input/output hashes are required; test logs are preserved,
not converted into an invented passing test result.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import tarfile
from zipfile import ZipFile, ZIP_DEFLATED

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = HERE / '_build'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_build() -> dict:
    manifest = json.loads((BUILD / 'build-manifest.json').read_text())
    if not manifest.get('inputs'):
        raise RuntimeError('Rebuild with the input-verifying builder before checkpointing')
    for name, expected in manifest['inputs'].items():
        path = (ROOT / name).resolve(strict=True)
        if ROOT not in path.parents or digest(path) != expected:
            raise RuntimeError(f'Build input changed after compilation: {name}')
    for name, expected in manifest['sources'].items():
        if Path(name).name != name or digest(BUILD / name) != expected:
            raise RuntimeError(f'Generated/support module changed after compilation: {name}')
    if digest(BUILD / 'blotc') != manifest['executable_sha256']:
        raise RuntimeError('Executable differs from the build manifest')
    return manifest


def verify_archive(archive: Path, manifest: dict) -> None:
    """Tie the tested build to Git's immutable snapshot, not just the worktree."""
    with tarfile.open(archive, 'r:gz') as source:
        for name, expected in manifest['inputs'].items():
            member = source.getmember(name)
            if not member.isfile():
                raise RuntimeError(f'Compiler input is not a committed file: {name}')
            stream = source.extractfile(member)
            if stream is None or hashlib.sha256(stream.read()).hexdigest() != expected:
                raise RuntimeError(f'Committed compiler input differs from build: {name}')


def package(args: argparse.Namespace) -> None:
    manifest = verify_build()
    status = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=all'], cwd=ROOT)
    if status.strip():
        raise RuntimeError('Commit source changes before creating a checkpoint')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if args.base:
        subprocess.run(['git', 'merge-base', '--is-ancestor', args.base, revision], cwd=ROOT, check=True)
    paths: dict[str, Path] = {
        'native/blotc': BUILD / 'blotc',
        'native/build-manifest.json': BUILD / 'build-manifest.json',
    }
    paths.update({'native/source/' + name: BUILD / name for name in manifest['sources']})
    for file in args.evidence:
        path = file.resolve(strict=True)
        name = 'evidence/' + path.name
        if name in paths:
            raise ValueError('Duplicate evidence basename: ' + path.name)
        paths[name] = path
    destination = args.output.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='core-checkpoint-') as directory:
        temporary = Path(directory)
        archive = temporary / 'source.tar.gz'
        with archive.open('wb') as output:
            subprocess.run(['git', 'archive', '--format=tar.gz', revision], cwd=ROOT, stdout=output, check=True)
        verify_archive(archive, manifest)
        paths['source.tar.gz'] = archive
        commit = temporary / 'commit.txt'
        commit.write_bytes(subprocess.check_output(['git', 'cat-file', 'commit', revision], cwd=ROOT))
        paths['commit.txt'] = commit
        if args.base:
            bundle = temporary / 'changes.bundle'
            subprocess.run(['git', 'bundle', 'create', str(bundle), 'HEAD', '^' + args.base], cwd=ROOT, check=True)
            paths['changes.bundle'] = bundle
        record = {
            'revision': revision,
            'base': args.base,
            'executable_sha256': manifest['executable_sha256'],
            'ocaml': manifest['ocaml'],
            'files': {name: {'sha256': digest(path), 'bytes': path.stat().st_size}
                      for name, path in sorted(paths.items())},
            'validation': 'See attached evidence; packaging does not imply tests passed.',
        }
        # Write alongside the destination so publication is one atomic rename.
        with tempfile.NamedTemporaryFile(dir=destination.parent, suffix='.zip', delete=False) as handle:
            zip_path = Path(handle.name)
        try:
            with ZipFile(zip_path, 'w', ZIP_DEFLATED) as zipped:
                for name, path in sorted(paths.items()):
                    zipped.write(path, name)
                zipped.writestr('checkpoint.json', json.dumps(record, indent=2, sort_keys=True) + '\n')
            zip_path.replace(destination)
        finally:
            zip_path.unlink(missing_ok=True)
    print(f'Checkpoint {revision}: {destination} ({destination.stat().st_size} bytes)')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--base', help='Known ancestor for an incremental Git bundle')
    parser.add_argument('--evidence', nargs='*', type=Path, default=[])
    args = parser.parse_args()
    # The builder holds this exact lock while regenerating modules, replacing
    # the executable and writing its manifest. Keep all checkpoint reads under
    # it too, so concurrent builds cannot mix two otherwise valid revisions.
    BUILD.mkdir(parents=True, exist_ok=True)
    with (BUILD / '.build.lock').open('a') as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        package(args)


if __name__ == '__main__':
    main()
