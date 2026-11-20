"""Pair checked Blot and Rust scalar packets in the same Pen release engine."""
import argparse
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "benchmarks/checked-grid"
UINT_MAX = (1 << 32) - 1


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=120, **kw).stdout


def inputs():
    rng = random.Random(20221208)
    trees = "".join("".join(str(rng.randrange(10)) for _ in range(120)) + "\n" for _ in range(120))
    rows = [[chr(97 + min(x + y, 25)) for x in range(120)] for y in range(120)]
    rows[0][0], rows[-1][-1] = "S", "E"
    hills = "".join("".join(row) + "\n" for row in rows)
    sample = "30373\n25512\n65332\n33549\n35390\n"
    climb = "Sabqponm\nabcryxxl\naccszExk\nacctuvwj\nabdefghi\n"
    words = list(map(ord, trees))

    def checksum(data):
        return [sum(data) & UINT_MAX, sum(word * (i & 7) for i, word in enumerate(data)) & UINT_MAX]

    def case(data, expected):
        if isinstance(data, str):
            data = list(map(ord, data))
        return {"input": data, "expected": expected}

    return {
        "scan": [case(words, checksum(words)), case([], [0, 0]), case([UINT_MAX, 3], [2, 3])],
        "trees": [case(trees, [1357, 565440]), case(sample, [21, 8]), case("12\n3\n", None), case("5", [1, 0])],
        "hills": [case(hills, [238, 238]), case(climb, [31, 29]), case("Saa", None), case("SE", [UINT_MAX] * 2)],
        "parse": [case(trees, [120, 120]), case("", None), case("12\n3\n", None), case("a", [1, 1])],
        "write": [case(words, [sum(v + i for i, v in enumerate(words)) & UINT_MAX, len(words)]), case([], [0, 0])],
        "view": [case(words, [sum(words[len(words)//2:]) & UINT_MAX, len(words) - len(words)//2]), case([], [0, 0])],
        "packet": [case(words, [len(words), 0]), case([], [0, 0])],
    }


def describe(samples):
    return {"p50": statistics.median(samples), "p95": sorted(samples)[math.ceil(len(samples) * .95) - 1]}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--compiler", type=Path, default=ROOT / "compiler-goose/build/blotc-goose")
    ap.add_argument("--baseline", type=Path, help="include a second Blot compiler")
    ap.add_argument("--pen", type=Path, default=ROOT.parent / "pen")
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--warmups", type=int, default=5)
    ap.add_argument("--samples", type=int, default=25)
    ap.add_argument("--kernels", nargs="+", choices=inputs().keys())
    args = ap.parse_args()
    if min(args.rounds, args.samples) < 1 or args.warmups < 0:
        ap.error("rounds and samples must be positive and warmups nonnegative")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    pen = args.pen.resolve()
    host = pen / "target/release/examples/measure_packets"
    cases = inputs()
    kernels = args.kernels or list(cases)
    versions = {"blot": args.compiler.resolve()}
    if args.baseline:
        versions["baseline"] = args.baseline.resolve()
    rust = ["rustc", "+1.99.0"]
    flags = ["--edition=2021", "--crate-type=cdylib", "--target", "wasm32-unknown-unknown",
             "-O", "-C", "panic=abort", "-C", "strip=debuginfo", "-C", "link-arg=--export-memory"]
    meta = {"rust": run(rust + ["-vV"]), "rust_flags": flags, "os": platform.platform(),
            "std_tree": run(["git", "-C", ROOT, "rev-parse", "HEAD:std"]).strip(),
            "engine": "Pen release engine, Wasmtime Cranelift, native CPU; BLOT_INLINING=0 or 1",
            "cpu": platform.processor(), "affinity": sorted(os.sched_getaffinity(0)),
            "compiler_sha256": {k: sha(v) for k, v in versions.items()}, "host_sha256": sha(host),
            "pen": run(["git", "-C", pen, "rev-parse", "HEAD"]).strip(),
            "blot": run(["git", "-C", ROOT, "rev-parse", "HEAD"]).strip(),
            "sources": {str(p.relative_to(FIXTURES)): sha(p) for p in sorted(FIXTURES.rglob("*")) if p.suffix in (".blot", ".rs")},
            "wasmtime_lock_sha256": sha(pen / "Cargo.lock"), "rounds": args.rounds,
            "warmups": args.warmups, "samples_per_process": args.samples, "cases": {}, "modules": {}}
    for line in Path("/proc/cpuinfo").read_text().splitlines():
        if line.startswith("model name"):
            meta["cpu"] = line.split(":", 1)[1].strip()
            break
    order = []
    for name in kernels:
        path = out / (name + ".json")
        path.write_text(json.dumps(cases[name], separators=(",", ":")))
        meta["cases"][name] = {"sha256": sha(path), "answers": [c["expected"] for c in cases[name]]}
        for family in [*versions, "rust"]:
            key = f"{name}-{family}"
            mod = out / (key + ".wasm")
            start = time.perf_counter_ns()
            if family == "rust":
                run(rust + flags + [FIXTURES / "rust" / (name + ".rs"), "-o", mod])
            else:
                run([versions[family], "build-project", FIXTURES / (name + ".blot"), mod, "--std-root",
                     ROOT / "std", "--prelude", ROOT / "std/prelude.blot"])
            meta["modules"][key] = {"source_compile_ns": time.perf_counter_ns() - start,
                                    "sha256": sha(mod), "wasm_bytes": mod.stat().st_size}
            for mode in (0, 1):
                order.append((key, name, mode))

    rows = []
    # Record fresh compiler process costs in both orders, separately from execution.
    builds = []
    for turn in range(args.rounds):
        builds_this_turn = [(name, family) for name in kernels for family in versions]
        random.Random(981 + turn).shuffle(builds_this_turn)
        for name, family in builds_this_turn:
            mod = out / "compile-replay.wasm"
            start = time.perf_counter_ns()
            run([versions[family], "build-project", FIXTURES / (name + ".blot"), mod, "--std-root",
                 ROOT / "std", "--prelude", ROOT / "std/prelude.blot"])
            elapsed = time.perf_counter_ns() - start
            key = f"{name}-{family}"
            if sha(mod) != meta["modules"][key]["sha256"]:
                raise ValueError(f"{key} changed during fresh compilation")
            builds.append({"key": key, "round": turn, "elapsed_ns": elapsed})
    for turn in range(args.rounds):
        jobs = order[:]
        random.Random(4517 + turn).shuffle(jobs)
        for key, name, mode in jobs:
            tag = f"{key}-inline{mode}"
            env = os.environ | {"BLOT_INLINING": str(mode)}
            try:
                result = json.loads(run([host, out / (key + ".wasm"), out / (name + ".json"), out / (tag + ".cwasm"),
                                         str(args.warmups), str(args.samples)], env=env))
            except subprocess.CalledProcessError as exc:
                raise RuntimeError(f"{tag}: {exc.stderr}") from exc
            rows.append({"key": tag, "round": turn, **result})
    with gzip.open(out / "samples.json.gz", "wt") as f:
        json.dump({"metadata": meta, "compiles": builds, "runs": rows}, f, separators=(",", ":"))
    stats = {}
    for key in sorted({r["key"] for r in rows}):
        selected = [r for r in rows if r["key"] == key]
        # The first packet is the workload. Later packets qualify traps and reuse.
        warm = [s for r in selected for s in r["samples"] if s[0] == 0 and s[1] != 0]
        cold = [r["samples"][0] for r in selected]
        row = {k: describe([r[k] for r in selected]) for k in (
            "engine_ns", "aot_compile_ns", "cold_deserialize_ns", "instantiate_and_bind_ns",
            "aot_bytes", "guest_linear_bytes", "peak_rss_kib")}
        row.update({k: describe([s[i] for s in warm]) for i, k in enumerate(("prepare_ns", "guest_ns", "finish_ns"), 2)})
        row["first_packet_ns"] = describe([sum(s[2:]) for s in cold])
        stats[key] = row
    (out / "summary.json").write_text(json.dumps(stats, indent=2) + "\n")
    for key, stat in stats.items():
        print(f"{key:30} {stat['guest_ns']['p50'] / 1000:9.2f} us   p95 {stat['guest_ns']['p95'] / 1000:9.2f} us")


if __name__ == "__main__":
    main()
