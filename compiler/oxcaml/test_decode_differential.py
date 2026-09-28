#!/usr/bin/env python3
"""Compare complete canonical decoder results and allocation with a pinned native baseline.

The companion decode_probe.ml stops at decoding, so malformed fuel values never
execute source programs. Cases include every prefix of valid messages, scalar
and count mutations, seeded random frames, and deep/wide trees. No timing gate.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import random
import tempfile
import threading
import struct
import subprocess

MAGIC = 0x424C4F54
VERSION = 13
BOUNDARIES = [0,1,2,9,13,0xffff,0x10000,0xd800,0xdfff,0x10ffff,0x110000,0x7fffffff,0xffffffff]

def words(values):
    return struct.pack('<' + 'I' * len(values), *values)

def dictionary(strings):
    out = [len(strings)]
    for value in strings:
        out += [len(value), *map(ord, value)]
    return out

def make(opcode, strings, root, extra=None):
    header = [MAGIC, VERSION, opcode, 0xffffffff, 0xffff]
    if opcode != 2:
        header += [0xffffffff,0xffff]
    return header + dictionary(strings) + root + ([] if extra is None else extra)

class Probe:
    def __init__(self, executable, timeout):
        self.errors = tempfile.TemporaryFile()
        self.process = subprocess.Popen([str(executable)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=self.errors)
        self.expired = False
        def expire():
            self.expired = True
            if self.process.poll() is None:
                self.process.kill()
        # Bound the complete corpus run, including blocked reads/writes, with
        # two timers total rather than creating a thread for every test case.
        self.timer = threading.Timer(timeout, expire)
        self.timer.daemon = True
        self.timer.start()
    def error(self):
        self.errors.seek(0)
        detail = self.errors.read().decode(errors='replace')
        return ('decoder corpus timeout; ' if self.expired else '') + detail
    def request(self, values):
        payload = words(values)
        try:
            self.process.stdin.write(struct.pack('<I', len(values)))
            self.process.stdin.write(payload)
            self.process.stdin.flush()
        except BrokenPipeError as error:
            raise RuntimeError('decoder probe stopped: ' + self.error()) from error
        header = self.process.stdout.readline()
        if not header:
            raise RuntimeError('decoder probe stopped: ' + self.error())
        length, allocation = map(int, header.split())
        if not 0 <= length <= 256 * 1024 * 1024:
            raise RuntimeError('invalid decoder probe output length')
        canonical = self.process.stdout.read(length)
        if len(canonical) != length:
            raise RuntimeError('truncated decoder probe response: ' + self.error())
        return canonical, allocation
    def close(self):
        self.timer.cancel()
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        finally:
            self.process.stdout.close()
            self.errors.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--timeout', type=float, default=120., help='Total seconds allowed per probe')
    args = parser.parse_args()
    if not 0 < args.timeout <= 3600:
        parser.error('--timeout must be in (0,3600]')
    paths = [path.resolve(strict=True) for path in (args.baseline, args.candidate)]
    probes = []
    count = 0
    measured = []
    corpus_hash = hashlib.sha256()
    def check(label, frame, measure=False):
        nonlocal count
        a, b = [probe.request(frame) for probe in probes]
        if a[0] != b[0]:
            raise AssertionError(f'{label}: decode mismatch\nframe={frame[:150]}\n{a[0][:300]}\n{b[0][:300]}')
        count += 1
        payload = words(frame)
        corpus_hash.update(struct.pack('<I',len(payload)))
        corpus_hash.update(payload)
        if measure:
            measured.append({'case':label,'words':len(frame),'baseline_bytes':a[1],
                'candidate_bytes':b[1], 'canonical_sha256':hashlib.sha256(a[0]).hexdigest()})
    tiny = [0,1,1,0,0,0]
    seeds = []
    for opcode in range(10):
        if opcode in (5,6,9):
            body = [3, 0, 0xffffffff,0xffff, 1, *tiny, 0,0,0]
        else:
            body = tiny + (tiny if opcode in (0,1,7) else [])
        seeds.append(make(opcode,['module',''],body))
    unicode_node = [0,1,2,0xffffffff,0xffff,2, *tiny, *tiny]
    seeds.append(make(1,['module','', '\0aåλ😀é'+'e\u0301'],unicode_node,tiny))
    try:
        for path in paths:
            probes.append(Probe(path, args.timeout))
        for index,seed in enumerate(seeds):
            check(f'valid-{index}',seed,True)
            for end in range(len(seed)):
                check(f'prefix-{index}-{end}',seed[:end])
            for offset in range(len(seed)):
                for value in BOUNDARIES:
                    changed = seed.copy(); changed[offset]=value
                    check(f'mutation-{index}-{offset}-{value}',changed)
            check(f'trailing-{index}',seed+[42])
        rng = random.Random(0x424c4f5413)
        for index in range(5000):
            frame = [rng.getrandbits(32) for _ in range(rng.randrange(0,65))]
            if len(frame)>1: frame[0:2] = [MAGIC,VERSION]
            if len(frame)>2: frame[2] = rng.randrange(12)
            check(f'random-{index}',frame)
        # Validation precedence: invalid available character before truncated suffix.
        for offset in range(8):
            body = [1, 20, *([97]*offset),0xd800]
            check(f'unicode-before-eof-{offset}',[MAGIC,VERSION,2,0,0,*body])
        # Explicit parent stacks, not recursive descent on the machine stack.
        depth = 30000
        deep = [0,1,1,0,0,1] * depth + tiny
        check('deep-30000',make(2,['module',''],deep),True)
        width = 65536
        wide = [0,1,1,0,0,width] + tiny * width
        check('wide-65536',make(2,['module',''],wide),True)
        check('unicode-100000',make(2,['module','', '\U0001f600'*100000],tiny),True)
        report={'completed':True,'cases':count,'mismatches':0,'seed':0x424c4f5413,
            'corpus_sha256':corpus_hash.hexdigest(),
            'baseline_sha256':hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
            'candidate_sha256':hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
            'allocations':measured}
        if args.report:
            args.report.parent.mkdir(parents=True,exist_ok=True)
            args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(f'{count} complete decoder comparisons; 0 mismatches')
        for row in measured[-3:]: print(row)
    finally:
        for probe in probes:
            probe.close()

if __name__=='__main__': main()
