#!/usr/bin/env python3
"""Cold builds of generated factory diamonds and public examples (task 085).

usage: principal_payoff.py REPS LABEL=BLOTC [LABEL=BLOTC ...]

Each wrapper calls its predecessor twice, so ordinary collection grows with
2^depth while open-principal retention grows with depth. Binaries alternate
within every repetition; each build uses a fresh restart-cache directory.
Prints the median child CPU per binary and the deterministic counters.
"""
import json, os, resource, statistics, subprocess, sys, tempfile

repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
reps = int(sys.argv[1])
binaries = [arg.split("=", 1) for arg in sys.argv[2:]]


def diamond(depth):
    lines = ["const w0 = func value => value + value"]
    for i in range(1, depth + 1):
        lines += [f"const w{i} = func value => do:", f"  let ignored = w{i - 1} value", f"  return w{i - 1} value"]
    lines += ["const factory = do:", f"  return w{depth}"]
    lines += ["entry const integer = func (value: U32) -> U32 => factory value"]
    lines += ["entry const floating = func (value: F32) -> F32 => factory value"]
    return "\n".join(lines) + "\n"


with tempfile.TemporaryDirectory() as work:
    sources = []
    for depth in (8, 12):
        path = f"{work}/diamond{depth}.blot"
        open(path, "w").write(diamond(depth))
        sources.append(path)
    sources += [f"{repo}/examples/{name}.blot" for name in ("ecs", "monads", "syntax", "generic_effects", "lists", "arrays")]
    for source in sources:
        samples = {label: [] for label, _ in binaries}
        counters = {}
        for _ in range(reps):
            for label, binary in binaries:
                with tempfile.TemporaryDirectory() as cache:
                    before = resource.getrusage(resource.RUSAGE_CHILDREN)
                    out = subprocess.run([binary, "build-project", source, f"{cache}/out.wasm", "--std-root", f"{repo}/std", "--prelude", f"{repo}/std/prelude.blot"], capture_output=True, text=True, env={**os.environ, "BLOT_CACHE_DIR": cache})
                    after = resource.getrusage(resource.RUSAGE_CHILDREN)
                record = next(json.loads(line) for line in out.stdout.splitlines() if '"compilation"' in line)
                assert record["success"], out.stdout[:400]
                samples[label].append((after.ru_utime - before.ru_utime + after.ru_stime - before.ru_stime) * 1000)
                work_counters = record["work_counters"]
                counters[label] = {key: work_counters.get(key) for key in ("inference_regions", "call_collections_unresolved", "principal_graph_builds", "principal_graph_deferred")}
        for label, _ in binaries:
            print(json.dumps({"source": os.path.basename(source), "binary": label, "median_cpu_ms": round(statistics.median(samples[label]), 1), "cpu_ms": [round(x, 1) for x in samples[label]], **counters[label]}))
