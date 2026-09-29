#!/usr/bin/env python3
"""Build the explicit native core from source, with no network or Bend runtime.

Generated semantic modules are an audited migration bridge. They live under
_build and are archived by CI; the production Bend sources are never rewritten.
Each successful build records exact source, generator and toolchain identities.
"""
from __future__ import annotations
import argparse
import fcntl
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FLAGS = ['-O2', '-g', '-w', '-8-11-26-27', '-I', '+threads', '-I', '+unix']
SUPPORT = ['core_nodes', 'core_text', 'core_index', 'base', 'core_symbols',
           'core_scopes', 'native_runtime', 'sem_native_transport', 'driver']


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args: list[str], cwd: Path, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else ''


def write_changed(path: Path, data: bytes) -> None:
    if path.exists() and path.read_bytes() == data:
        return
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_bytes(data)
    temporary.replace(path)


def build_locked(compiler: str, jobs: int) -> Path:
    compiler = str(Path(shutil.which(compiler) or compiler).resolve(strict=True))
    version = run([compiler, '-version'], HERE, True).strip()
    if int(version.split('.')[0]) < 5:
        raise RuntimeError('Native core requires OCaml 5 or newer and a 64-bit host')
    output = HERE / '_build'
    output.mkdir(exist_ok=True)
    config = run([compiler, '-config'], HERE, True)
    settings = dict(line.split(': ', 1) for line in config.splitlines() if ': ' in line)
    if settings.get('word_size') != '64':
        raise RuntimeError('Native core requires a 64-bit OCaml toolchain')
    configuration = hashlib.sha256((compiler + config + repr(FLAGS) + digest(Path(compiler))).encode()).hexdigest()
    state_path = output / 'build-manifest.json'
    old = json.loads(state_path.read_text()) if state_path.exists() else {}
    same_config = old.get('configuration') == configuration
    with tempfile.TemporaryDirectory(prefix='core-generate-', dir=output) as scratch:
        generated = Path(scratch)
        run(['python3', str(HERE / 'bootstrap/generate.py'), '--source', str(HERE.parent),
             '--output', str(generated)], ROOT)
        semantic_manifest = json.loads((generated / 'manifest.json').read_text())
        source_files = {p.name: p for p in generated.glob('*.ml')}
        source_files.update({name + '.ml': HERE / (name + '.ml') for name in SUPPORT})
        source_files['native_parallel.ml'] = HERE / 'native_parallel_domains.ml'
        for name, source in source_files.items():
            write_changed(output / name, source.read_bytes())
        hashes = {name: digest(source) for name, source in source_files.items()}
        for module in semantic_manifest:
            name = 'sem_' + module['module'] + '.ml'
            if hashes.get(name) != module['native_sha256']:
                raise RuntimeError('Generated source does not match its manifest: ' + name)
        # Never let a removed migration module leak into later test/link scans.
        for name in set(old.get('sources', {})) - set(source_files):
            if Path(name).name != name or not name.endswith('.ml'):
                raise RuntimeError('Invalid cached module path')
            for extension in ['.ml', '.cmi', '.cmx', '.o']:
                (output / (Path(name).stem + extension)).unlink(missing_ok=True)
        order = run([str(Path(compiler).with_name('ocamldep')), '-sort', *sorted(source_files)], output, True).split()
        deps = {}
        for line in run([str(Path(compiler).with_name('ocamldep')), '-modules', *sorted(source_files)], output, True).splitlines():
            name, imports = line.split(':', 1)
            deps[name] = {module[0].lower() + module[1:] + '.ml' for module in imports.split()}
            deps[name].intersection_update(source_files)
            deps[name].discard(name)
        stale = set()
        for name in order:
            stem = Path(name).stem
            products = [output / (stem + ext) for ext in ['.cmx', '.cmi', '.o']]
            if (not same_config or old.get('sources', {}).get(name) != hashes[name]
                    or any(not product.exists() for product in products)
                    or bool(deps[name] & stale)):
                stale.add(name)
        # A failed compile must never leave a stale object looking up to date.
        for name in stale:
            for ext in ['.cmx', '.cmi', '.o']:
                (output / (Path(name).stem + ext)).unlink(missing_ok=True)
        completed = set(source_files) - stale
        pending = set(stale)
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            while pending:
                ready = [name for name in order if name in pending and deps[name] <= completed]
                if not ready:
                    raise RuntimeError('Native module dependency cycle: ' + ', '.join(sorted(pending)))
                futures = {pool.submit(run, [compiler, *FLAGS, '-c', name], output): name for name in ready}
                for future in as_completed(futures):
                    future.result()
                    completed.add(futures[future])
                    pending.remove(futures[future])
        stub = HERE / 'runtime_stubs.c'
        stub_hash = digest(stub)
        stub_changed = not same_config or old.get('stub') != stub_hash or not (output / 'runtime_stubs.o').exists()
        if stub_changed:
            (output / 'runtime_stubs.o').unlink(missing_ok=True)
            run([compiler, '-c', str(stub)], output)
        executable = output / 'blotc'
        linked = bool(stale) or stub_changed or not executable.exists()
        if linked:
            temporary = output / 'blotc.tmp'
            temporary.unlink(missing_ok=True)
            objects = [str(Path(name).with_suffix('.cmx')) for name in order]
            run([compiler, *FLAGS, '-o', str(temporary), 'unix.cmxa', 'threads.cmxa',
                 'runtime_stubs.o', *objects], output)
            temporary.replace(executable)
        input_paths = set(source for source in source_files.values() if source.parent == HERE)
        input_paths.update((HERE / 'bootstrap').glob('*.py'))
        input_paths.update(HERE.parent / (module['module'] + '.bend') for module in semantic_manifest)
        # native_transport's implementation is hand-written, but its protocol
        # source remains an input to the migration's dependency/schema checks.
        input_paths.update([HERE.parent / 'native_transport.bend', stub, Path(__file__)])
        inputs = {str(path.relative_to(ROOT)): digest(path) for path in sorted(input_paths)}
        manifest = {'configuration': configuration, 'ocaml': version, 'flags': FLAGS,
                    'inputs': inputs,
                    'toolchain_config': config,
                    'sources': hashes, 'semantic_sources': semantic_manifest,
                    'bootstrap': {p.name: digest(p) for p in sorted((HERE / 'bootstrap').glob('*.py'))},
                    'stub': stub_hash, 'executable_sha256': digest(executable)}
        write_changed(state_path, (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode())
        print(f'Native core: {len(stale)} modules compiled; linked={linked}; SHA-256={manifest["executable_sha256"]}', flush=True)
    return executable


def build(compiler: str, jobs: int) -> Path:
    output = HERE / '_build'
    output.mkdir(exist_ok=True)
    # Build products are private to this checkout. Serialize concurrent builds
    # rather than racing compiler output, temporary executables and manifests.
    with (output / '.build.lock').open('a') as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        return build_locked(compiler, jobs)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default=os.environ.get('OCAMLOPT', 'ocamlopt'))
    parser.add_argument('-j', '--jobs', type=int, default=2)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 64:
        parser.error('jobs must be in [1,64]')
    build(args.compiler, args.jobs)


if __name__ == '__main__':
    main()
