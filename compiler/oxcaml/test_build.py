#!/usr/bin/env python3
"""Regression tests for the real Makefile, using a tiny dependency graph.

The fixture keeps this gate quick: no compiler-core rebuild is needed. It checks
outputs and object mtimes, not a dry-run approximation of make's decisions.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default='ocamlopt')
    args = parser.parse_args()
    compiler = shutil.which(args.compiler)
    if not compiler:
        parser.error(f'compiler not found: {args.compiler}')
    major = int(subprocess.check_output([compiler, '-version'], text=True).split('.')[0])
    dependency_tool = f'{compiler} -depend' if major >= 5 else 'ocamldep'
    checks = 0
    with tempfile.TemporaryDirectory(prefix='blot-build-test-') as directory:
        root = Path(directory)
        (root / 'core').mkdir()
        shutil.copyfile(HERE / 'Makefile', root / 'Makefile')
        sources = {
            'core/modules.txt': 'ox_model\nox_user\n',
            'base.ml': 'let value = 40\n',
            'native_runtime.ml': 'let configure _ = ()\n',
            'native_parallel_domains.ml': 'let backend = "domains"\n',
            'native_parallel_serial.ml': 'let backend = "serial"\n',
            'core/ox_model.ml': 'let value = Base.value + 1\n',
            'core/ox_user.ml': 'let value = Ox_model.value + 1\n',
            'driver.ml': 'let () = Printf.printf "%d %s\\n" Ox_user.value Native_parallel.backend\n',
            'runtime_stubs.c': 'void blot_build_fixture(void) {}\n',
        }
        for test in ['wasm_bytes', 'test_bytes', 'test_runtime', 'test_parallel', 'test_domains']:
            sources[f'{test}.ml'] = 'let () = ()\n'
        for name, contents in sources.items():
            (root / name).write_text(contents)
        command = ['make', '--no-print-directory', '-j2', f'OCAMLOPT={compiler}',
                   f'OCAMLDEP={dependency_tool}']

        def build(*options: str) -> dict[str, int]:
            result = subprocess.run([*command, *options, 'all'], cwd=root,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if result.returncode:
                raise AssertionError(result.stdout)
            return {path.name: path.stat().st_mtime_ns for path in (root / '_build').glob('*.cmx')}

        def changed(before: dict[str, int], after: dict[str, int]) -> set[str]:
            return {name for name, stamp in after.items() if before.get(name) != stamp}

        def output() -> str:
            return subprocess.check_output([root / '_build/blotc'], text=True).strip()

        backend = 'domains' if major >= 5 else 'serial'
        first = build()
        assert output() == f'42 {backend}'
        checks += 1
        executable_time = (root / '_build/blotc').stat().st_mtime_ns
        second = build()
        assert changed(first, second) == set(), 'unchanged objects rebuilt'
        assert executable_time == (root / '_build/blotc').stat().st_mtime_ns, 'unchanged executable relinked'
        checks += 1
        with (root / 'driver.ml').open('a') as handle:
            handle.write('(* independent leaf edit *)\n')
        leaf = build()
        assert changed(second, leaf) == {'driver.cmx'}, 'leaf edit rebuilt unrelated modules'
        checks += 1
        (root / 'core/ox_model.ml').write_text('let value = Base.value + 2\n')
        dependency = build()
        assert changed(leaf, dependency) == {'ox_model.cmx', 'ox_user.cmx', 'driver.cmx'}
        assert output() == f'43 {backend}'
        checks += 1
        flags = 'OCAMLFLAGS=-g -w -8-11-26-27 -inline 0'
        configured = build(flags)
        assert changed(dependency, configured) == set(configured), 'flags did not invalidate every object'
        checks += 1
        switched = build(flags, 'PARALLEL=serial')
        assert output() == '43 serial'
        assert (root / '_build/native_parallel.ml').read_text() == sources['native_parallel_serial.ml']
        if backend != 'serial':
            assert changed(configured, switched) == set(switched), 'backend change left stale objects'
        checks += 1
        restored = build()
        assert output() == f'43 {backend}'
        assert changed(switched, restored) == set(restored), 'restoring flags left stale objects'
        checks += 1
        # Missing compiler outputs must be repaired, even if .cmx still exists.
        (root / '_build/ox_model.cmi').unlink()
        recovered = build()
        assert (root / '_build/ox_model.cmi').is_file()
        assert output() == f'43 {backend}'
        assert 'ox_model.cmx' in changed(restored, recovered)
        checks += 1
    print(f'{checks} incremental-build checks passed (OCaml {major})')


if __name__ == '__main__':
    main()
