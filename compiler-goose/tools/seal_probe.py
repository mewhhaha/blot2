#!/usr/bin/env python3
"""Seal a check_engines.py output directory into an immutable gzip receipt.

The receipt records the partial result, every hashed input, the raw diagnostic
log and a short audit note. Partial probes never qualify the whole compiler.
"""
import argparse
import base64
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'benchmarks/evidence/qualification'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='check_engines.py --output directory')
    parser.add_argument('name', help='receipt file stem, e.g. 2026-11-11-goose-backend-flow316')
    parser.add_argument('--audit', default='', help='what changed and why')
    args = parser.parse_args()
    args.output = args.output.resolve()
    result = json.loads((args.output / 'result.json').read_text())
    if not result.get('source_unchanged', False):
        parser.error('source changed during the probe; rerun before sealing')
    receipt = {
        'scope': 'Partial backend only; no complete compiler/runtime qualification',
        'result': result,
        'inputs': json.loads((args.output / 'inputs.json').read_text()),
        'audit': args.audit,
        'raw_logs_base64': {
            str((args.output / 'diagnostics.log').relative_to(ROOT)):
                base64.b64encode((args.output / 'diagnostics.log').read_bytes()).decode(),
        },
    }
    target = EVIDENCE / (args.name + '.json.gz')
    if target.exists():
        parser.error(str(target) + ' already exists; receipts are immutable')
    with gzip.open(target, 'wt') as handle:
        json.dump(receipt, handle, indent=1)
        handle.write('\n')
    print(target.relative_to(ROOT))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
