#!/usr/bin/env python3
"""Paired private static-array evaluation timing, not a legacy benchmark."""
import hashlib
import os
from pathlib import Path
import platform
import re
import resource
import time
import statistics
import subprocess
import tempfile

def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def cgroup_dir():
    membership = read('/proc/self/cgroup') or ''
    for line in membership.splitlines():
        if line.startswith('0::'):
            return Path('/sys/fs/cgroup') / line[3:].lstrip('/')
    return Path('/sys/fs/cgroup')


def cpu_stat():
    content = read(cgroup_dir() / 'cpu.stat')
    if content is None:
        return None
    try:
        return {key: int(value) for key, value in (line.split() for line in content.splitlines())}
    except ValueError:
        return None


def host_cpu():
    content = read('/proc/stat')
    if content is None:
        return None
    fields = content.splitlines()[0].split()
    return [int(x) for x in fields[1:]] if fields[0] == 'cpu' else None


def delta(after, before):
    if before is None or after is None:
        return None
    return {key: after[key] - value for key, value in before.items() if key in after}

root = Path(__file__).resolve().parent
compiler = os.environ.get('GOOSE', 'goose')
source = root / 'static_fast_bench.goose'
print('platform:', platform.platform(), flush=True)
print('goose:', subprocess.check_output([compiler, '--version'], text=True).strip(), flush=True)
for name in ('static_fast_bench.goose','static_fast_eval.goose','static_fast_verify.goose','static_product_eval.goose','static_product_verify.goose'):
    print('sha256', name, hashlib.sha256((root / name).read_bytes()).hexdigest(), flush=True)
with tempfile.TemporaryDirectory(prefix='k1-static-fast-bench-') as tmp:
    exe = Path(tmp) / 'bench'
    subprocess.run([compiler,'build',str(source),'-O2','-o',str(exe)], check=True)
    print('binary sha256:', hashlib.sha256(exe.read_bytes()).hexdigest(), flush=True)
    samples = {'repeated': [], 'unique': []}
    print('available_cpu_affinity:', sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else None, flush=True)
    print('cgroup_cpu_max:', read(cgroup_dir() / 'cpu.max'), flush=True)
    for run in range(1):
        load_before = os.getloadavg() if hasattr(os, 'getloadavg') else None
        before = cpu_stat()
        host_before = host_cpu()
        cpu_before = resource.getrusage(resource.RUSAGE_CHILDREN)
        wall_start = time.monotonic()
        output = subprocess.check_output([str(exe)], text=True)
        wall_seconds = time.monotonic() - wall_start
        cpu_after = resource.getrusage(resource.RUSAGE_CHILDREN)
        host_after = host_cpu()
        after = cpu_stat()
        load_after = os.getloadavg() if hasattr(os, 'getloadavg') else None
        print('load_before_after:', load_before, load_after, flush=True)
        print('benchmark_process_wall_user_sys_seconds:', wall_seconds,
              cpu_after.ru_utime - cpu_before.ru_utime, cpu_after.ru_stime - cpu_before.ru_stime, flush=True)
        print('cgroup_cpu_stat_delta:', delta(after, before), flush=True)
        print('host_proc_stat_cpu_delta:', [a-b for a,b in zip(host_after,host_before)] if host_before and host_after else None, flush=True)
        print('process',run,flush=True);print(output,flush=True)
        case = None
        for line in output.splitlines():
            if line.startswith('case '):
                case = line.split()[1]
                a = re.search(r'old_fnv32=(\d+)', line)
                b = re.search(r'new_fnv32=(\d+)', line)
                if not a or not b or a.group(1) != b.group(1): raise RuntimeError('output mismatch')
            elif line.startswith('sample '):
                a = re.search(r'old_ns=(\d+)', line)
                b = re.search(r'new_ns=(\d+)', line)
                if case not in samples or not a or not b: raise RuntimeError('bad sample')
                samples[case].append((int(a.group(1)),int(b.group(1))))
    for case, data in samples.items():
        if len(data)!=31: raise RuntimeError('missing samples')
        old = [a for a,_ in data]; new = [b for _,b in data]
        ratios = [a/b for a,b in data]
        def quantile(values, fraction):
            ordered = sorted(values)
            at = (len(ordered) - 1) * fraction
            lo = int(at)
            hi = min(lo + 1, len(ordered) - 1)
            return ordered[lo] + (ordered[hi] - ordered[lo]) * (at - lo)
        print(case, 'n=',len(data),
              'baseline_ns_p10_median_p90=',tuple(round(quantile(old,p)) for p in (0.1,0.5,0.9)),
              'candidate_ns_p10_median_p90=',tuple(round(quantile(new,p)) for p in (0.1,0.5,0.9)),
              'paired_speedup_p10_median_p90=',tuple(round(quantile(ratios,p),3) for p in (0.1,0.5,0.9)),flush=True)
