#!/usr/bin/env python3
"""Collect partial diagnostics from concrete production entry paths in one pass."""
from pathlib import Path
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
ENGINES = ['runtime', 'semantic', 'check', 'lower', 'independent']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose', type=Path, default=ROOT / 'build/goose-port/selected-roots-build/goose')
    parser.add_argument('--engines', nargs='+', choices=ENGINES, default=ENGINES)
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--jobs', type=int, default=5)
    parser.add_argument('--source', type=Path, default=ROOT / 'compiler-goose/src/_diagnostic_roots.goose')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/goose-port/engine-checks')
    args = parser.parse_args()
    if not args.goose.exists():
        command = ['python3', str(Path(__file__).with_name('build_goose_checker.py')),
                   '--diagnostic-roots', '--expansion-node-limit', '1000000']
        built = subprocess.run(command, check=True, capture_output=True, text=True)
        args.goose = Path(json.loads(built.stdout)['binary'])
    if b'PARTIAL selected-root diagnostics' not in args.goose.read_bytes():
        parser.error('--goose must be the diagnostic-roots build')
    if args.jobs > 1 and len(args.engines) > 1:
        args.output.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        def check_one(key):
            output = args.output / key
            command = ['python3', str(Path(__file__).resolve()), '--goose', str(args.goose.resolve()),
                       '--engines', key, '--jobs', '1', '--timeout', str(args.timeout), '--output', str(output),
                       '--source', str(args.source.resolve())]
            checked = subprocess.run(command, capture_output=True, text=True)
            result = output / 'result.json'
            if result.exists():
                return json.loads(result.read_text())
            return {'engines': [key], 'exit': checked.returncode, 'errors': [], 'tool_error': checked.stderr[-1000:]}
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(check_one, args.engines))
        report = {'partial': True, 'seconds': round(time.monotonic() - started, 3),
                  'results': results, 'full_qualification': False}
        (args.output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        for result in results:
            key = result['engines'][0]
            status = 'partial pass'
            if result['exit']:
                status = str(len(result['errors'])) + ' diagnostic(s)'
            print(key + ': ' + status)
            for error in result['errors']:
                print(error['file'] + ':' + str(error['line']) + ': ' + error['message'])
        print('Partial batch: ' + str(report['seconds']) + 's; full compiler qualification pending')
        if any(result['exit'] for result in results):
            return 1
        return 0
    args.output.mkdir(parents=True, exist_ok=True)
    log_path = args.output / 'diagnostics.log'
    command = [str(args.goose.resolve()), 'check', str(args.source.resolve()),
               '--stdlib', str(ROOT.parent / 'goose-to-wasm/build/source/stdlib')]
    environment = dict(os.environ)
    environment['GOOSE_DIAGNOSTIC_ROOTS'] = ','.join('blot_diagnostic_roots::' + key for key in args.engines)
    started = time.monotonic()
    reason = 'completed'
    with log_path.open('w') as log:
        child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                 start_new_session=True, env=environment)
        def cancelled(signum, frame):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, cancelled)
        try:
            while child.poll() is None:
                if time.monotonic() - started >= args.timeout or log_path.stat().st_size > 8 * 1024 * 1024:
                    reason = 'batch limit'
                    break
                time.sleep(.1)
        finally:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=.25)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
    output = log_path.read_text()
    errors = []
    for match in re.finditer(r'^(/[^\n:]+\.goose):(\d+): (.*)$', output, re.M):
        if match[3].startswith('warning:'):
            continue
        item = {'file': match[1], 'line': int(match[2]), 'message': match[3]}
        if item not in errors:
            errors.append(item)
    report = {'partial': True, 'engines': args.engines, 'exit': child.returncode,
              'seconds': round(time.monotonic() - started, 3), 'stop': reason,
              'errors': errors, 'full_qualification': False}
    (args.output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if child.returncode:
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
