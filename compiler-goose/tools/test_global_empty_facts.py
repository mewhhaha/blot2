#!/usr/bin/env python3
"""Check the optional direct-global empty-holder precision and conservative boundaries."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'compiler-goose/tests/global_empty_facts'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--stdlib', type=Path, default=ROOT.parent / 'goose-to-wasm/build/source/stdlib')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/goose-port/global-empty-controls')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    binaries = {name: path.resolve(strict=True) for name, path in
                [('baseline', args.baseline), ('candidate', args.candidate)]}
    expected = json.loads((FIXTURES / 'expectations.json').read_text())
    report = {'binaries': {name: {'path': str(path), 'sha256': digest(path)}
                          for name, path in binaries.items()}, 'cases': {}, 'passed': True,
              'scope': 'checker acceptance/rejection; executed Plan lifecycle is a separate engine law'}
    for name, accepted in expected.items():
        source = FIXTURES / (name + '.goose')
        row = {'sha256': digest(source), 'candidate_accept': accepted}
        for variant, binary in binaries.items():
            command = [str(binary), 'check', str(source), '--stdlib', str(args.stdlib.resolve(strict=True))]
            started = time.monotonic()
            try:
                result = subprocess.run(command, capture_output=True, timeout=5)
                status = result.returncode
                output = result.stdout + result.stderr
            except subprocess.TimeoutExpired as error:
                status = 124
                output = (error.stdout or b'') + (error.stderr or b'')
            log = args.output / (name + '-' + variant + '.log')
            log.write_bytes(output)
            wanted = accepted and variant == 'candidate'
            passed = status == 0 if wanted else status == 1
            if not wanted:
                passed = passed and b'error:' in output and b'\xc2\xa75.1' in output
            row[variant] = {'command': command, 'exit': status, 'seconds': time.monotonic() - started,
                            'log': str(log), 'log_sha256': digest(log), 'passed': passed}
            report['passed'] = report['passed'] and passed
        report['cases'][name] = row
        print(name + ': ' + str(all(row[v]['passed'] for v in binaries)), flush=True)
    (args.output / 'evidence.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
