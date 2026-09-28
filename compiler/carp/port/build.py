#!/usr/bin/env python3
"""Build the native Carp port, caching code generation, objects, linking and tests.

Normal builds use checked-in Carp, Python and C11, not Bend or Node. Immutable
input snapshots prevent a failed/interrupted build from poisoning valid cache
entries. Publication is atomic and only follows successful runtime self-tests.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
from verify import verify_generated

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / 'compiler/carp/port'
SOURCE = PORT / 'generated'
CACHE_VERSION = b'carp-port-build-v2'


def digest(*parts: bytes) -> str:
    h = hashlib.sha256()
    for part in parts:
        h.update(len(part).to_bytes(8, 'little'))
        h.update(part)
    return h.hexdigest()


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_stamp(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def atomic_write(path: Path, data: bytes) -> None:
    temporary = path.with_name(path.name + '.new')
    temporary.write_bytes(data)
    os.replace(temporary, path)


def stamp(path: Path, data: dict) -> None:
    atomic_write(path, (json.dumps(data, sort_keys=True) + '\n').encode())


def snapshot(directory: Path, files: dict[str, bytes]) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        path = directory / name
        if not path.is_file() or path.read_bytes() != data:
            atomic_write(path, data)


def valid_output(path: Path, receipt: dict, key: str, executable: bool = False) -> bool:
    return (receipt.get('key') == key and path.is_file()
            and (not executable or os.access(path, os.X_OK))
            and receipt.get('sha256') == file_hash(path))


def run(args: list[str], log: Path, env: dict[str, str]) -> float:
    begin = time.perf_counter()
    with log.open('wb') as out:
        result = subprocess.run(args, cwd=ROOT, env=env, stdout=out,
                                stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}):\n'
                           + log.read_text(errors='replace')[-12000:])
    return time.perf_counter() - begin


def install(source: Path, target: Path) -> bool:
    """Do not relink, copy or change mtime on a validated no-change rebuild."""
    if (target.is_file() and os.access(target, os.X_OK)
            and file_hash(target) == file_hash(source)):
        return False
    temporary = target.with_name(target.name + '.new')
    shutil.copy2(source, temporary)
    os.replace(temporary, target)
    return True


def main() -> int:
    start = time.perf_counter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('debug', 'release', 'sanitize'), nargs='?', default='debug')
    parser.add_argument('--jobs', type=int, default=min(4, os.cpu_count() or 1))
    parser.add_argument('--rebuild', action='store_true', help='ignore build cache receipts')
    parser.add_argument('--retest', action='store_true', help='rerun runtime checks even for an unchanged binary')
    args = parser.parse_args()
    if not 1 <= args.jobs <= 32:
        parser.error('--jobs must be in 1..32')
    if not os.environ.get('CARP_DIR'):
        parser.error('CARP_DIR must name the pinned Carp 0.6.0 checkout')
    env = dict(os.environ)
    carp, cc = shutil.which(env.get('CARP', 'carp')), shutil.which(env.get('CC', 'clang'))
    if not carp or not cc:
        parser.error('CARP (default carp) and CC (default clang) must be executable')
    env['CARP_DIR'] = str(Path(env['CARP_DIR']).resolve())
    output = ROOT / 'generated/carp-port'
    output.mkdir(parents=True, exist_ok=True)
    # A single publication target is shared by build modes. Serialize builders,
    # including unit workers and test execution, rather than racing that target.
    with (output / 'build.lock').open('a+b') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return build(args, env, carp, cc, output, start)


def build(args: argparse.Namespace, env: dict[str, str], carp: str, cc: str,
          output: Path, start: float) -> int:
    verify_generated()
    manifest_bytes = (SOURCE / 'manifest.json').read_bytes()
    headers = {name: path.read_bytes() for name, path in [
        ('runtime.h', PORT / 'runtime.h'), ('tables.h', SOURCE / 'tables.h'),
        ('calls.h', SOURCE / 'calls.h')]}
    runtime = {name: path.read_bytes() for name, path in [
        ('runtime.c', PORT / 'runtime.c'), ('scheduler.inc', PORT / 'scheduler.inc'),
        ('calls.inc', SOURCE / 'calls.inc'), ('runtime_test.c', PORT / 'runtime_test.c')]}
    table_bytes = (SOURCE / 'tables.c').read_bytes()
    bindings = (SOURCE / 'bindings.carp').read_bytes()
    sources = sorted(SOURCE.glob('unit*.carp')) + [SOURCE / 'driver.carp']
    if len(sources) < 2:
        raise RuntimeError('missing generated semantic sources')
    source_bytes = {p.name: p.read_bytes() for p in sources}
    carp_identity = file_hash(Path(carp))
    cc_version = subprocess.check_output([cc, '--version'], env=env)
    # Hash executable bytes as well as its version: two wrappers may print the
    # same version while selecting different flags/toolchains.
    cc_identity = digest(cc_version, file_hash(Path(cc)).encode(), str(Path(cc).resolve()).encode())
    header_key = digest(CACHE_VERSION, *headers.values())
    header_dir = output / 'headers' / header_key
    snapshot(header_dir, headers)
    flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
             '-ffp-contract=off', '-pthread', '-I' + str(header_dir.relative_to(ROOT))]
    if b'clang' in cc_version.lower():
        flags.append('-fbracket-depth=4096')
    flags += {'debug': ['-O0', '-g'], 'release': ['-O2'],
              'sanitize': ['-O1', '-g', '-fsanitize=address,undefined',
                           '-fno-omit-frame-pointer', '-fno-sanitize-recover=all']}[args.mode]
    folder = output / args.mode
    folder.mkdir(parents=True, exist_ok=True)
    c_key = digest(CACHE_VERSION, cc_identity.encode(), json.dumps(flags).encode(), header_key.encode())
    gen_key = digest(CACHE_VERSION, carp_identity.encode(), bindings)

    def compile_c(source: Path, obj: Path, key: str, log: Path,
                  extra: list[str] | None = None) -> tuple[float, str, bool]:
        receipt = obj.with_suffix('.json')
        cached = not args.rebuild and valid_output(obj, read_stamp(receipt), key)
        seconds = 0.0
        if not cached:
            temporary = obj.with_suffix('.new.o')
            seconds = run([cc, *flags, *(extra or []), '-c', str(source), '-o', str(temporary)], log, env)
            os.replace(temporary, obj)
            stamp(receipt, {'key': key, 'sha256': file_hash(obj)})
        return seconds, file_hash(obj), cached

    def build_unit(source: Path) -> dict:
        name = source.stem
        data = source_bytes[source.name]
        generation = digest(gen_key.encode(), source.name.encode(), data)
        # Carp-to-C is independent of C optimization mode. Every mode shares
        # this immutable, content-addressed source snapshot and generated C.
        work = output / 'codegen' / generation
        work.mkdir(parents=True, exist_ok=True)
        generated = work / 'main.c'
        receipt = work / 'stamp.json'
        gen_cached = not args.rebuild and valid_output(generated, read_stamp(receipt), generation)
        gen_seconds = 0.0
        if not gen_cached:
            snapshot(work, {source.name: data, 'bindings.carp': bindings})
            generated.unlink(missing_ok=True)
            gen_seconds = run([carp, '--no-core', '--no-profile', '--generate-only',
                '--eval-postload', '(Project.config "output-directory" '
                + json.dumps(str(work.relative_to(ROOT))) + ')',
                '-b', str((work / source.name).relative_to(ROOT))], work / 'carp.log', env)
            if not generated.is_file():
                raise RuntimeError(f'Carp did not emit {generated}:\n' + (work / 'carp.log').read_text())
            stamp(receipt, {'key': generation, 'sha256': file_hash(generated)})
        native = digest(c_key.encode(), name.encode(), file_hash(generated).encode())
        obj = folder / (name + '.o')
        cc_seconds, obj_hash, c_cached = compile_c(generated, obj, native, folder / (name + '.log'),
                                                 [f'-Dcarp_init_globals=bp_init_{name}'])
        return {'unit': name, 'carp_seconds': gen_seconds, 'c_seconds': cc_seconds,
                'codegen_cached': gen_cached, 'native_cached': c_cached,
                'cached': gen_cached and c_cached, 'object_sha256': obj_hash,
                'codegen_key': generation}

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for result in pool.map(build_unit, sources):
            results.append(result)
            if not result['cached']:
                print(f'{result["unit"]}: '
                      f'Carp {result["carp_seconds"]:.3f}s, C {result["c_seconds"]:.3f}s', flush=True)
    results.sort(key=lambda r: r['unit'])
    objects = [folder / (p.stem + '.o') for p in sources]
    # Runtime/test sources include local .inc files. Keep those alongside their
    # source snapshot; generated headers are resolved through header_dir.
    support_dir = output / 'inputs' / digest(CACHE_VERSION, *runtime.values(), table_bytes)
    snapshot(support_dir, {**runtime, 'tables.c': table_bytes})
    support_results = []
    for name, data in [('runtime', runtime['runtime.c']), ('tables', table_bytes)]:
        dependencies = runtime['scheduler.inc'] + runtime['calls.inc'] if name == 'runtime' else b''
        key = digest(c_key.encode(), data, dependencies)
        obj = folder / (name + '.o')
        seconds, obj_hash, cached = compile_c(support_dir / (name + '.c'), obj, key,
                                             folder / (name + '.log'))
        objects.append(obj)
        support_results.append({'unit': name, 'c_seconds': seconds, 'native_cached': cached,
                                'object_sha256': obj_hash})
    object_hashes = {p.name: file_hash(p) for p in objects}
    binary = folder / 'blotc-carp-native'
    link_key = digest(c_key.encode(), json.dumps(object_hashes, sort_keys=True).encode())
    link_receipt = folder / 'link.json'
    link_cached = not args.rebuild and valid_output(binary, read_stamp(link_receipt), link_key, executable=True)
    link_seconds = 0.0
    if not link_cached:
        temporary = binary.with_name(binary.name + '.new')
        link_seconds = run([cc, *flags, *map(str, objects), '-lm', '-o', str(temporary)], folder / 'link.log', env)
        os.replace(temporary, binary)
        stamp(link_receipt, {'key': link_key, 'sha256': file_hash(binary)})
    # The runtime harness includes runtime.c itself and must not link runtime.o
    # or the separate driver main. Its hash covers all those included sources.
    test_objects = [p for p in objects if p.name not in ('runtime.o', 'driver.o')]
    test_key = digest(c_key.encode(), *runtime.values(),
                      json.dumps({p.name: file_hash(p) for p in test_objects}, sort_keys=True).encode())
    test_binary = folder / 'runtime-test'
    test_receipt = folder / 'runtime-test-build.json'
    test_build_cached = not args.rebuild and valid_output(test_binary, read_stamp(test_receipt), test_key, True)
    if not test_build_cached:
        temporary = test_binary.with_name(test_binary.name + '.new')
        run([cc, *flags, str(support_dir / 'runtime_test.c'), *map(str, test_objects),
             '-lm', '-o', str(temporary)], folder / 'runtime-test-build.log', env)
        os.replace(temporary, test_binary)
        stamp(test_receipt, {'key': test_key, 'sha256': file_hash(test_binary)})
    test_environment = {name: env.get(name) for name in
                        ['ASAN_OPTIONS', 'LSAN_OPTIONS', 'UBSAN_OPTIONS', 'TSAN_OPTIONS']}
    # Cache test success on this host/environment, not only on compiler inputs.
    test_run_key = digest(test_key.encode(), file_hash(test_binary).encode(),
                          str(platform.uname()).encode(), json.dumps(test_environment, sort_keys=True).encode())
    test_run_receipt = folder / 'runtime-test-run.json'
    tests_cached = (not args.rebuild and not args.retest
                    and read_stamp(test_run_receipt).get('key') == test_run_key
                    and read_stamp(test_run_receipt).get('passed') is True)
    if not tests_cached:
        test_run_receipt.unlink(missing_ok=True)
        run([str(test_binary)], folder / 'runtime-test.log', env)
        stamp(test_run_receipt, {'key': test_run_key, 'passed': True})
    # Inputs were compiled from snapshots. An edit made during the build must not
    # publish a binary that no longer corresponds to the user's working tree.
    verify_generated()
    current_runtime = {name: (SOURCE / name if name == 'calls.inc' else PORT / name).read_bytes()
                       for name in runtime}
    if ((SOURCE / 'manifest.json').read_bytes() != manifest_bytes or current_runtime != runtime
            or (PORT / 'runtime.h').read_bytes() != headers['runtime.h']):
        raise RuntimeError('inputs changed during build; previous published executable preserved')
    target = output / 'blotc-carp-native'
    published = install(binary, target)
    report = {'mode': args.mode, 'carp': 'Carp executable sha256:' + carp_identity,
              'cc': cc_version.decode(errors='replace').splitlines()[0], 'cc_identity': cc_identity,
              'flags': flags, 'jobs': args.jobs, 'elapsed_seconds': time.perf_counter() - start,
              'link_seconds': link_seconds, 'link_cached': link_cached,
              'runtime_test_build_cached': test_build_cached, 'runtime_tests_cached': tests_cached,
              'published': published, 'carp_units_generated': sum(not r['codegen_cached'] for r in results),
              'c_units_compiled': sum(not r['native_cached'] for r in results + support_results),
              'units': results, 'support_units': support_results,
              'binary': str(target.relative_to(ROOT)), 'binary_bytes': target.stat().st_size,
              'binary_sha256': file_hash(target)}
    atomic_write(folder / 'build.json', (json.dumps(report, indent=2) + '\n').encode())
    print(f'{report["binary"]}: {report["elapsed_seconds"]:.2f}s; '
          f'{report["carp_units_generated"]} Carp, {report["c_units_compiled"]} C units; '
          f'link {"cached" if link_cached else "rebuilt"}, '
          f'runtime checks {"cached" if tests_cached else "passed"}')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Carp port build failed: {error}', file=sys.stderr)
        raise SystemExit(1)
