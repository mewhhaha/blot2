#!/usr/bin/env python3
"""Paired native peak-RSS experiment, with exact protocol-output comparison.

Requires Linux /usr/bin/time. Input is frozen by memory_fixtures.ts before
measurement. Each sample starts a fresh native process and submits five identical
stateless requests. RSS is the maximum resident set of that native process, not
Deno or the whole application. CPU/wall measurements include native startup and
pipe I/O, but not source parsing. No speed thresholds are imposed.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import struct
import subprocess
import tempfile
import time


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check_frames(data: bytes, requests: int) -> None:
    position = 0
    for index in range(requests + 1):
        require(position + 4 <= len(data), 'missing response prefix')
        count, = struct.unpack_from('<I', data, position)
        position += 4
        require(count <= 16777216 and position + 4*count <= len(data), 'invalid response size')
        payload = data[position:position + 4*count]
        position += 4*count
        if index == 0:
            require(payload == struct.pack('<II', 0x424c4f54, 13), 'wrong handshake')
        else:
            require(len(payload) >= 12 and payload[:8] == struct.pack('<II', 0x424c4f54, 13), 'invalid response header')
            require(struct.unpack_from('<I', payload, 8)[0] == 2, 'compilation did not return an artifact')
    require(position == len(data), 'trailing output')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--requests', type=int, default=5)
    parser.add_argument('--threads', default='1,4')
    args = parser.parse_args()
    threads = [int(value) for value in args.threads.split(',')]
    if not 1 <= args.samples <= 100 or not 1 <= args.requests <= 100 or not threads or any(not 1 <= n <= 64 for n in threads):
        parser.error('samples/requests must be 1..100 and workers 1..64')
    paths = [args.baseline.resolve(strict=True), args.candidate.resolve(strict=True)]
    hashes = [sha(path.read_bytes()) for path in paths]
    report = dict(completed=False, platform=platform.platform(), started_at=time.time(),
                  harness_sha256=sha(Path(__file__).read_bytes()),
                  fixture_manifest_sha256=sha((args.fixtures / 'manifest.json').read_bytes()),
                  order='alternating baseline-first/candidate-first; no warmup; fresh process each sample',
                  executables=[dict(path=str(path), sha256=digest) for path,digest in zip(paths,hashes)],
                  requests_per_process=args.requests, samples=args.samples, rows=[])
    manifest = json.loads((args.fixtures / 'manifest.json').read_text())
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    with tempfile.TemporaryDirectory(prefix='blot-rss-') as directory:
        stats = Path(directory) / 'stats.txt'
        for fixture in manifest:
            frame = (args.fixtures / (fixture['name'] + '.frame')).read_bytes()
            require(sha(frame) == fixture['frame_sha256'], 'fixture changed')
            for workers in threads:
                samples: list[list[dict]] = [[], []]
                for sample in range(args.samples):
                    results: list[bytes | None] = [None, None]
                    for side in ([0,1] if sample % 2 == 0 else [1,0]):
                        run = subprocess.run(['/usr/bin/time', '-f', '%M %U %S %e', '-o', str(stats),
                                              str(paths[side]), '--threads', str(workers)],
                                             input=frame * args.requests, stdout=subprocess.PIPE,
                                             stderr=subprocess.PIPE, env={}, timeout=120, check=True)
                        check_frames(run.stdout, args.requests)
                        results[side] = run.stdout
                        rss, user, system, wall = map(float, stats.read_text().split())
                        samples[side].append(dict(peak_rss_kib=rss, user_s=user, system_s=system, wall_s=wall,
                                                  output_sha256=sha(run.stdout)))
                    require(results[0] == results[1], 'native response mismatch')
                row = dict(fixture=fixture, workers=workers, baseline=samples[0], candidate=samples[1])
                report['rows'].append(row)
                print(f"{fixture['name']}/{workers}: RSS KiB "
                      f"{statistics.median(x['peak_rss_kib'] for x in samples[0]):.0f} -> "
                      f"{statistics.median(x['peak_rss_kib'] for x in samples[1]):.0f}", flush=True)
                args.report.write_text(json.dumps(report, indent=2) + '\n')
    require([sha(path.read_bytes()) for path in paths] == hashes, 'executable changed')
    report['completed'] = True
    args.report.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
