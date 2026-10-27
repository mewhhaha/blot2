"""Retained edit matrix, with process CPU/RSS and exact raw protocol evidence.

Run after correctness qualification; no timing threshold is imposed. Source
edits and output inspection are outside the measured request interval.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--rounds", type=int, default=5)
parser.add_argument("--scales", default="8,32,128")
parser.add_argument("--out", default="build/bench-sessions")
parser.add_argument("--build-label", required=True)
parser.add_argument("--compiler", default="build/blot")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
out = (root / args.out).resolve()
out.mkdir(parents=True, exist_ok=True)
scales = [int(x) for x in args.scales.split(",")]
assert 1 <= args.rounds <= 100 and all(1 <= n <= 2048 for n in scales)
exe = (root / args.compiler).resolve()
metadata = {"timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "platform": platform.platform(), "cpu": next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unknown"),
            "candidate_sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
            "compiler": str(exe),
            "build_label": args.build_label, "threads": 1, "rounds": args.rounds,
            "scales": scales, "instrumentation": "phase and work counters enabled; request wall includes cache decode/encode and publication",
            "cache": "fresh process per scale/round; successive in-process revisions; filesystem cache uncontrolled"}
samples = []

def usage(pid):
    stat = Path(f"/proc/{pid}/stat").read_text().split(")", 1)[1].split()
    cpu = (int(stat[11]) + int(stat[12])) * 1000 / os.sysconf("SC_CLK_TCK")
    status = Path(f"/proc/{pid}/status").read_text().splitlines()
    rss = int(next(line.split()[1] for line in status if line.startswith("VmRSS:")))
    peak = int(next(line.split()[1] for line in status if line.startswith("VmHWM:")))
    return cpu, rss, peak

def source(n, delta=1, depth=1, static=5, bad=False, comment=""):
    text = comment + f"static let offset: U32 = {static}\n"
    value = "true" if bad else f"U32.wrapping_add(x,{delta})"
    text += f"pub let leaf: U32 -> U32 ! {{}} resources {{depth:{depth},frame:0}} = fn x => return {value}\n"
    for i in range(n):
        text += f"pub let run_{i}: U32 -> U32 ! {{}} resources {{depth:3,frame:0}} = fn x => return U32.wrapping_add(leaf(x),offset)\n"
    return text

for scale in scales:
    for round_id in range(args.rounds):
        directory = out / f"{scale}-{round_id}"
        directory.mkdir(exist_ok=True)
        path, wasm = directory / "input.blot", directory / "output.wasm"
        with (directory / "stderr.log").open("w") as error:
            process = subprocess.Popen([str(exe), "serve"], cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=error, text=True, bufsize=1)
            def request(label, text, expected=True, extra=None):
                path.write_text(text)
                (directory / f"{label}.blot").write_text(text)
                payload = {"input": str(path), "output": str(wasm), "package_root": str(directory), **(extra or {})}
                cpu, _, _ = usage(process.pid)
                start = time.perf_counter_ns()
                process.stdin.write(json.dumps(payload) + "\n")
                process.stdin.flush()
                line = process.stdout.readline()
                elapsed = time.perf_counter_ns() - start
                if not line:
                    raise RuntimeError(f"session exited: {directory / 'stderr.log'}")
                result = json.loads(line)
                cpu_after, rss, peak = usage(process.pid)
                assert result["ok"] == expected, (label, result, directory)
                sample = {"scale": scale, "round": round_id, "case": label, "wall_ms": elapsed / 1e6,
                          "cpu_ms": cpu_after - cpu, "rss_kib": rss, "peak_rss_kib": peak,
                          "source_sha256": hashlib.sha256(text.encode()).hexdigest(), "response": result}
                if wasm.exists():
                    sample["wasm_sha256"] = hashlib.sha256(wasm.read_bytes()).hexdigest()
                    (directory / f"{label}.wasm").write_bytes(wasm.read_bytes())
                samples.append(sample)
                (out / "results.json").write_text(json.dumps({"metadata": metadata, "samples": samples}, indent=2))
                return sample
            try:
                request("fresh", source(scale))
                request("unchanged", source(scale))
                request("body-edit", source(scale, delta=2))
                request("interface-edit", source(scale, delta=2, depth=2))
                stable = request("static-edit", source(scale, delta=2, depth=2, static=6))
                failed = request("rejected-edit", source(scale, bad=True), expected=False)
                assert stable["wasm_sha256"] == failed["wasm_sha256"]
                request("valid-revert", source(scale, delta=2, depth=2, static=6))
                request("source-origins", source(scale, delta=2, depth=2, static=6, comment="// moved origins\n\n"))
                # ABI geometry uses a separate complete source revision.
                bridge = directory / "bridge.json"
                bridge_source = (root / "examples/bridge_identity.blot").read_text()
                config = json.loads((root / "examples/bridge_identity.json").read_text())
                bridge.write_text(json.dumps(config))
                request("bridge-first", bridge_source, extra={"bridge_config": str(bridge)})
                config["input_maxima"], config["output_capacity"] = [2], 2
                bridge.write_text(json.dumps(config))
                request("abi-edit", bridge_source, extra={"bridge_config": str(bridge)})
            finally:
                process.stdin.close()
                process.wait(timeout=30)
                assert process.returncode == 0
        print(f"measured retained scale={scale} round={round_id}", flush=True)

summary = []
for scale in scales:
    for case in dict.fromkeys(s["case"] for s in samples):
        group = [s for s in samples if s["scale"] == scale and s["case"] == case]
        times = [s["wall_ms"] for s in group]
        summary.append({"scale": scale, "case": case, "samples": len(group), "median_ms": statistics.median(times),
                        "min_ms": min(times), "max_ms": max(times), "median_rss_kib": statistics.median(s["rss_kib"] for s in group),
                        "median_completed_bodies": statistics.median(s["response"]["completed_bodies"] for s in group),
                        "median_reused_bodies": statistics.median(s["response"]["reused_bodies"] for s in group)})
(out / "summary.json").write_text(json.dumps({"metadata": metadata, "summary": summary}, indent=2))
