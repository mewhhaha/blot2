#!/usr/bin/env python3
"""Fresh-process measurements; raw samples retain compiler/CPU/RSS boundaries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "zig-native/zig-out/bin/blotc")
    parser.add_argument("--output", type=Path, default=ROOT / "build/zig-native-first-benchmark/final")
    parser.add_argument("--samples", type=int, default=7)
    options = parser.parse_args()
    if options.samples < 1:
        parser.error("--samples must be positive")
    compiler = options.compiler.resolve()
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    inputs = []
    for count in (16, 64, 256, 1024):
        source = (
            "const twice = fn value => @u32.add value value\n"
            "entry const answer = fn () -> U32 => do:\n"
            + "".join(f"  let value_{i} = twice {i}\n" for i in range(count))
            + f"  return value_{count - 1}\n"
        )
        path = output / f"calls-{count}.blot"
        path.write_text(source)
        inputs.append((f"calls-{count}", ["build", str(path), str(output / f"calls-{count}.wasm")]))
    gdev = ROOT.parent / "gdev/src/main.blot"
    if gdev.exists():
        inputs.append(("gdev-frontend", ["parse-project", str(gdev), "--std-root", str(ROOT / "std"), "--alias", f"gdev/={ROOT.parent / 'gdev/packages'}"]))
    rows = []
    for iteration in range(options.samples):
        # Alternate ordering to reduce one-way cache/load bias.
        for name, arguments in inputs if iteration % 2 == 0 else reversed(inputs):
            command = [str(compiler), *arguments]
            stdout_path = output / f"{name}-{iteration}.stdout"
            stderr_path = output / f"{name}-{iteration}.stderr"
            sampled_native_hwm = None
            start = time.perf_counter_ns()
            with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
                process = subprocess.Popen(command, cwd=ROOT, stdout=stdout, stderr=stderr)
                while True:
                    pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                    if pid:
                        process.returncode = os.waitstatus_to_exitcode(status)
                        break
                    # wait4's lifetime maximum may include the Python fork
                    # before exec. VmHWM belongs to the current native image.
                    try:
                        if os.readlink(f"/proc/{process.pid}/exe") == str(compiler):
                            status_text = Path(f"/proc/{process.pid}/status").read_text()
                            for line in status_text.splitlines():
                                if line.startswith("VmHWM:"):
                                    sampled_native_hwm = max(sampled_native_hwm or 0, int(line.split()[1]))
                    except (FileNotFoundError, ProcessLookupError):
                        pass
                    if time.perf_counter_ns() - start > 30_000_000_000:
                        process.kill()
                        _, status, _ = os.wait4(process.pid, 0)
                        process.returncode = os.waitstatus_to_exitcode(status)
                        raise TimeoutError(f"{name}: compiler exceeded 30 seconds")
                    time.sleep(0.0005)
            wall_ms = (time.perf_counter_ns() - start) / 1e6
            compiler_stdout = stdout_path.read_text()
            compiler_stderr = stderr_path.read_text()
            records = [json.loads(line) for line in compiler_stdout.splitlines()]
            if process.returncode != 0 or not records or not records[-1].get("success"):
                raise RuntimeError(f"{name}: {compiler_stdout}\n{compiler_stderr}")
            rows.append({"workload": name, "iteration": iteration, "command": command,
                         "wall_ms": wall_ms, "user_cpu_s": usage.ru_utime,
                         "system_cpu_s": usage.ru_stime, "child_lifetime_peak_rss_kib": usage.ru_maxrss,
                         "sampled_native_hwm_kib": sampled_native_hwm,
                         "records": records, "stderr": compiler_stderr})
    summaries = []
    for name, _ in inputs:
        group = [row for row in rows if row["workload"] == name]
        summaries.append({"workload": name, "samples": len(group),
                          "median_process_wall_ms": statistics.median(row["wall_ms"] for row in group),
                          "median_compiler_ms": statistics.median(row["records"][-1]["total_us"] / 1000 for row in group),
                          "max_requested_peak_bytes": max(row["records"][-1]["memory"]["peak_bytes"] for row in group),
                          "max_child_lifetime_peak_rss_kib": max(row["child_lifetime_peak_rss_kib"] for row in group),
                          "max_sampled_native_hwm_kib": max((row["sampled_native_hwm_kib"] or 0 for row in group), default=0) or None})
    report = {"compiler": str(compiler), "compiler_sha256": digest(compiler),
              "boundary": "Every sample is a fresh process; OS file caches may be warm. Compiler timings exclude process startup. Process wall includes spawning, /proc sampling and up to 0.5ms polling delay. Per-child CPU/lifetime RSS comes from Unix wait4 (Linux RSS in KiB); lifetime RSS may include Python's fork before exec. Sampled native VmHWM only observes the compiler image and is a lower bound if execution ends before the next sample. No incremental compiler cache is used. gdev-frontend only loads, lexes and parses source.",
              "implementation": {str(path.relative_to(ROOT)): digest(path) for path in sorted((ROOT / "zig-native/src").glob("*.zig"))},
              "summary": summaries, "samples": rows}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summaries, indent=2))


if __name__ == "__main__":
    main()
