#!/usr/bin/env python3
"""Run existing Blot regression tests against Native core in an isolated checkout.

Native tests select the Native core executable at the conventional native path.
An exact-URL import map redirects the synchronous source compiler to a test-only
adapter which compares every result/error against unmodified Bend JavaScript,
then returns the native result to the unchanged test. Low-level IR-only tests
still exercise the reference; the report separates mirrored operation counts.
No generated C/JavaScript, host module, or test file is patched.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_tests(suite: str) -> list[str]:
    paths = sorted((ROOT / 'compiler').rglob('*.test.ts'))
    if suite == 'native':
        paths = [p for p in paths if p.parent == ROOT / 'compiler' and 'native' in p.name]
    elif suite == 'full':
        # Match deno task test: the old graphical ECS application/prototype
        # is explicitly paused and still imports removed compiler APIs.
        paths += sorted((ROOT / 'scripts').glob('*.test.ts'))
    return [str(path.relative_to(ROOT)) for path in paths]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, default=ROOT / 'compiler/core/_build/blotc')
    parser.add_argument('--deno', default='deno')
    parser.add_argument('--report', type=Path)
    parser.add_argument('--suite', choices=['full', 'compiler', 'native'], default='full')
    parser.add_argument('--verify-type-graph', action='store_true', help='Verify source/native constraints with the experimental solver')
    parser.add_argument('--threads', type=int, default=1, help='Workers per mirrored source operation')
    parser.add_argument('tests', nargs='*', help='Explicit repository-relative test paths instead of the selected suite')
    args = parser.parse_args()
    if not 1 <= args.threads <= 64:
        parser.error('--threads must be in [1,64]')
    executable = args.executable.resolve(strict=True)
    if not (ROOT / 'generated/compiler/compiler.js').is_file():
        parser.error('build the unchanged JavaScript reference first: python3 scripts/build_compiler_reference.py')
    selected = args.tests or select_tests(args.suite)
    if not selected:
        parser.error('no test files were selected')
    for name in selected:
        path = (ROOT / name).resolve(strict=True)
        if ROOT not in path.parents or not path.name.endswith('.test.ts'):
            parser.error(f'invalid repository test path: {name}')
    reference_version = ROOT / 'generated/compiler/reference-version.txt'
    report = {
        'executable_sha256': digest(executable),
        'source_mirror_sha256': digest(ROOT / 'compiler/core/source_mirror.ts'),
        'reference_version': reference_version.read_text().strip() if reference_version.exists() else None,
        'threads': args.threads,
        'verify_type_graph': args.verify_type_graph,
        'tests': selected,
        'test_sha256': {name: digest(ROOT / name) for name in selected},
        'excluded': {str(path.relative_to(ROOT)): 'Archived/paused graphical sandbox; not part of deno task test (see README.md: Sandbox status)'
                     for path in sorted((ROOT / 'case-study').rglob('*.test.ts'))},
    }
    print(f'Running {len(selected)} unchanged regression files against {executable}', flush=True)
    print('Source operations are mirrored against the unmodified Bend JavaScript reference.', flush=True)
    with tempfile.TemporaryDirectory(prefix='blot-core-tests-') as directory:
        stage = Path(directory)
        shutil.copytree(ROOT, stage, dirs_exist_ok=True, ignore=shutil.ignore_patterns(
            '.git', '_build', '__pycache__', '_opam', 'node_modules', '.native-backend-*',
            'reference-tools', '.reference-cache', '.cache', 'build', 'parity-results',
        ))
        target = stage / 'generated/compiler/blotc'
        shutil.copyfile(executable, target)
        target.chmod(0o755)
        graph_reports = stage / 'graph-reports'
        if args.verify_type_graph:
            graph_reports.mkdir()
            real = target.with_name('blotc-verified-native')
            target.rename(real)
            wrapper = ('#!/bin/sh\nexec ' + shlex.quote(str(real)) +
                       ' --verify-type-graph --type-graph-report-dir ' +
                       shlex.quote(str(graph_reports)) + ' "$@"\n')
            target.write_text(wrapper)
            target.chmod(0o755)
            report['verification_wrapper_sha256'] = digest(target)
        config = json.loads((ROOT / 'deno.json').read_text())
        config['imports'] = dict(config.get('imports', {}))
        config['imports'][(stage / 'compiler/source.ts').as_uri()] = (
            stage / 'compiler/core/source_mirror.ts').as_uri()
        # Keep Deno config's npm package-prefix expansion. An external import
        # map would turn @package/subpath into an unmapped bare specifier.
        (stage / 'deno.json').write_text(json.dumps(config, indent=2) + '\n')
        environment = dict(os.environ, BLOT_CORE_MIRROR_THREADS=str(args.threads), NO_COLOR='1')
        environment['BLOT_CORE_VERIFY_TYPE_GRAPH'] = '1' if args.verify_type_graph else '0'
        command = [args.deno, 'test', '--allow-all', '--fail-fast', *selected]
        logs: list[str] = []
        with subprocess.Popen(command, cwd=stage, env=environment, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True) as process:
            assert process.stdout is not None
            for line in process.stdout:
                print(line, end='', flush=True)
                logs.append(ANSI.sub('', line))
            exit_code = process.wait()
        log = ''.join(logs)
        mirrors = [json.loads(match[1]) for match in re.finditer(r'CORE_MIRROR (\{[^\n]+\})', log)]
        report['mirror'] = {
            key: sum(item.get(key, 0) for item in mirrors)
            for key in ['operations', 'native_requests', 'successes', 'diagnostics', 'mismatches']
        }
        if args.verify_type_graph:
            names = ['attempts', 'accepted', 'rejected', 'skipped_rigid', 'skipped_free_row',
                     'skipped_kind', 'skipped_resource', 'skipped_normalization', 'mismatches']
            report['type_graph'] = {
                name: sum(item.get('graph_' + name, 0) for item in mirrors) for name in names
            }
            if report['type_graph']['mismatches'] or not (report['type_graph']['accepted'] + report['type_graph']['rejected']):
                print('ERROR: type-graph mismatches or no graph comparisons recorded', flush=True)
                exit_code = exit_code or 1
            reports = [json.loads(path.read_text()) for path in sorted(graph_reports.glob('*.json'))]
            for item in reports:
                values = item['graph']
                if any(type(values.get(name)) is not int or values[name] < 0 for name in names):
                    raise RuntimeError('Invalid native type-graph report')
                if values['attempts'] != sum(values[name] for name in names if name != 'attempts'):
                    raise RuntimeError('Incomplete native type-graph accounting')
            report['native_type_graph'] = {name: sum(item['graph'][name] for item in reports) for name in names}
            report['native_type_graph']['processes'] = len(reports)
            report['native_type_graph_reports'] = reports
            counts = report['native_type_graph']
            if counts['mismatches'] or counts['accepted'] + counts['rejected'] == 0 or counts['attempts'] < report['type_graph']['attempts']:
                print('ERROR: native graph disagreement or no native graph comparisons', flush=True)
                exit_code = exit_code or 1
        # A negative test can catch an AssertionError. Never let that hide a
        # differential failure, nor allow a broken import map to claim parity.
        if 'CORE_MISMATCH' in log or report['mirror']['mismatches']:
            print('ERROR: differential mismatch, including any caught by negative tests', flush=True)
            exit_code = exit_code or 1
        if not report['mirror']['native_requests']:
            print('ERROR: no mirrored native requests were recorded', flush=True)
            exit_code = exit_code or 1
        summaries = re.findall(r'(\d+) passed \| (\d+) failed(?: \| (\d+) ignored)?', log)
        if summaries:
            passed, failed, ignored = summaries[-1]
            report['summary'] = {'passed': int(passed), 'failed': int(failed), 'ignored': int(ignored or 0)}
        report['exit_code'] = exit_code
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    if args.verify_type_graph:
        print('Source-mirror type graph:', json.dumps(report.get('type_graph')), flush=True)
        print('All reported native type graphs:', json.dumps(report.get('native_type_graph')), flush=True)
    print('Mirrored source operations:', json.dumps(report['mirror']), flush=True)
    return exit_code


if __name__ == '__main__':
    raise SystemExit(main())
