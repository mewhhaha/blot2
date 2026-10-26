#!/usr/bin/env python3
"""Paired private scalar-session benchmark; this is not a legacy comparison."""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import platform
import shutil
import statistics
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
EXPECTED_SOURCE = b"let identity: U32 -> U32 = fn x => return x\n"
SAMPLES = 31
WARMUPS = 4
ITERATIONS = 200

def digest(data):
    return hashlib.sha256(data).hexdigest()

def cpu_stat():
    try:
        return pathlib.Path("/sys/fs/cgroup/cpu.stat").read_text()
    except OSError:
        return None

def cpu_model():
    try:
        for line in pathlib.Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return None

def percentile(values, fraction):
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    low = int(index)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=pathlib.Path, help="write ordered samples and metadata as JSON")
    parser.add_argument("--preflight-only", action="store_true", help="build and execute correctness witnesses without timing")
    args = parser.parse_args()
    goose = os.environ.get("GOOSE", "goose")
    goose_path = shutil.which(goose) or goose
    node = shutil.which("node")
    if not node:
        raise SystemExit("Node is required for the independent Wasm witness")
    with tempfile.TemporaryDirectory(prefix="k1-session-bench-") as temp:
        temp = pathlib.Path(temp)
        environment = os.environ.copy()
        environment.setdefault("GOOSE_HOME", str(temp / "goose-home"))
        binary = temp / "session-bench"
        subprocess.run([goose, "build", "-O2", "-o", str(binary), str(HERE / "session_bench.goose")],
                       env=environment, check=True, stdout=subprocess.DEVNULL)
        def invoke(mode):
            proc = subprocess.run([str(binary), mode], cwd=temp, env=environment,
                                  check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
            record = json.loads(proc.stdout)
            source = (temp / "session_bench_source.blot").read_bytes()
            wasm = (temp / "session_bench.wasm").read_bytes()
            if source != EXPECTED_SOURCE:
                raise RuntimeError("benchmark source changed")
            return record, digest(source), digest(wasm)
        _, source_hash, wasm_hash = invoke("probe")
        node_witness = r'''const assert = require('node:assert/strict');
const fs = require('node:fs');
const b = fs.readFileSync(process.argv[1]);
assert(WebAssembly.validate(b));
WebAssembly.instantiate(b).then(({instance}) => {
  for (const x of [0, 1, 42, 0x7fffffff, 0x80000000, 0xffffffff])
    assert.equal(instance.exports.identity(0, x) >>> 0, x);
}).catch(e => { console.error(e); process.exit(1); });'''
        subprocess.run([node, "-e", node_witness, str(temp / "session_bench.wasm")], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        verified, verified_source, verified_wasm = invoke("verify")
        if verified.get("mode") != "verify" or verified_source != source_hash or verified_wasm != wasm_hash:
            raise RuntimeError("untimed fresh/warm correctness preflight failed")
        if args.preflight_only:
            print("private session source and Wasm correctness preflight passed; no timing samples taken")
            return
        before = cpu_stat()
        samples = []
        counts = None
        for index in range(WARMUPS + SAMPLES):
            order = ["fresh", "warm"] if index % 2 == 0 else ["warm", "fresh"]
            pair = {"order": order}
            for mode in order:
                record, got_source, got_wasm = invoke(mode)
                if got_source != source_hash or got_wasm != wasm_hash:
                    raise RuntimeError("source or Wasm changed during paired run")
                if record.get("mode") != mode or record.get("iterations") != ITERATIONS or record.get("elapsed_ns", 0) <= 0:
                    raise RuntimeError("malformed benchmark output")
                expected_counts = (1, ITERATIONS) if mode == "warm" else (ITERATIONS, 0)
                if (record.get("fresh_runs"), record.get("hits")) != expected_counts:
                    raise RuntimeError("reported session work does not match requested mode")
                observed = (record.get("semantic"), record.get("validation_semantic"), record.get("validation_target_visits"))
                if counts is None:
                    counts = observed
                if observed != counts:
                    raise RuntimeError("partial work receipt differs across samples")
                pair[mode] = record
            if index >= WARMUPS:
                pair["warm_over_fresh"] = pair["warm"]["elapsed_ns"] / pair["fresh"]["elapsed_ns"]
                samples.append(pair)
        after = cpu_stat()
        ratios = [p["warm_over_fresh"] for p in samples]
        goose_version = subprocess.run([goose, "version"], env=environment, check=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout.strip()
        node_version = subprocess.run([node, "--version"], check=True, stdout=subprocess.PIPE, text=True).stdout.strip()
        pins = {p.name: digest(p.read_bytes()) for p in sorted(HERE.glob("*.goose"))}
        pins["session_bench.py"] = digest(pathlib.Path(__file__).read_bytes())
        result = {
            "scope": "private scalar session: fresh session vs same-process warm validated hit; not K1 vs legacy",
            "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "platform": platform.platform(), "cpu_model": cpu_model(),
            "goose_version": goose_version, "goose_binary_sha256": digest(pathlib.Path(goose_path).read_bytes()),
            "node_version": node_version, "benchmark_binary_sha256": digest(binary.read_bytes()),
            "source_sha256": source_hash, "wasm_sha256": wasm_hash, "source_pins_sha256": pins,
            "warmup_pairs": WARMUPS, "measured_pairs": SAMPLES, "iterations_per_sample": ITERATIONS,
            "receipt": {"semantic": counts[0], "validation_semantic": counts[1], "validation_target_visits": counts[2]},
            "cpu_stat_before": before, "cpu_stat_after": after,
            "ratio_warm_over_fresh": {"median": statistics.median(ratios),
                                      "p10": percentile(ratios, .1), "p90": percentile(ratios, .9)},
            "samples": samples,
            "notes": "Fresh includes Session construction; warm includes source/plan/target validation. Both include per-iteration output/counter checks. No general K1, array, public API, retained project or legacy comparison is implied."
        }
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(f"wrote {len(samples)} paired samples to {args.output}")

if __name__ == "__main__":
    main()
