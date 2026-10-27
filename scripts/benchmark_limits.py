"""Measure operation-boundary admission and source-less required-artifact restart.

Formal runs require a frozen, qualified compiler. --probe uses 16 operations
only; it is neither near-limit nor performance qualification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import signal
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def machine_metadata():
    cpu = Path("/proc/cpuinfo")
    return {"timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "platform": platform.platform(), "python": sys.version,
            "cpu": next((line.split(":", 1)[1].strip() for line in cpu.read_text().splitlines()
                         if line.startswith("model name")), "unknown") if cpu.exists() else "unknown",
            "logical_cpus": os.cpu_count(), "load_average_start": list(os.getloadavg()),
            "memory_total_kib": int(next((line.split()[1] for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemTotal:")), "0")),
            "filesystem_cache": "uncontrolled; fresh means process/intermediates, not cold OS caches",
            "rss_semantics": "Linux wait4 ru_maxrss: largest individual child/descendant RSS, not simultaneous process-tree sum"}


def measure_child(request_file):
    request = json.loads(Path(request_file).read_text())
    with Path(request["stdout"]).open("wb") as out, Path(request["stderr"]).open("wb") as error:
        started = time.perf_counter_ns()
        result = subprocess.run(request["command"], cwd=request["cwd"], stdout=out, stderr=error)
        elapsed = time.perf_counter_ns() - started
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    print(json.dumps({"exit_code": result.returncode, "wall_ms": elapsed / 1e6,
                      "user_cpu_ms": usage.ru_utime * 1000, "system_cpu_ms": usage.ru_stime * 1000,
                      "cpu_ms": (usage.ru_utime + usage.ru_stime) * 1000,
                      "peak_rss_kib": usage.ru_maxrss, "timed_out": False}))


def stop_worker(worker):
    try:
        os.killpg(worker.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        worker.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(worker.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        worker.communicate()


def measure(command, cwd, directory, label, timeout, env=None):
    """One fresh collector per sample, so RSS never inherits previous peaks."""
    directory = Path(directory)
    request_file = directory / f"{label}.request.json"
    stdout, stderr = directory / f"{label}.stdout.log", directory / f"{label}.stderr.log"
    request = {"command": [str(arg) for arg in command], "cwd": str(cwd),
               "stdout": str(stdout), "stderr": str(stderr)}
    write_json(request_file, request)
    worker = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--measure-child", str(request_file)],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, start_new_session=True)
    started = time.perf_counter_ns()
    try:
        raw, error = worker.communicate(timeout=timeout)
        if worker.returncode != 0:
            raise RuntimeError(f"measurement collector failed: {error.decode(errors='replace')}")
        result = json.loads(raw)
    except subprocess.TimeoutExpired:
        stop_worker(worker)
        result = {"exit_code": None, "wall_ms": (time.perf_counter_ns() - started) / 1e6,
                  "cpu_ms": None, "user_cpu_ms": None, "system_cpu_ms": None,
                  "peak_rss_kib": None, "timed_out": True}
    except BaseException:
        stop_worker(worker)
        raise
    result.update({"command": request["command"], "cwd": request["cwd"],
                   "stdout": str(stdout), "stderr": str(stderr)})
    text = stderr.read_text(errors="replace") if stderr.exists() else ""
    result["diagnostics"] = list(dict.fromkeys(re.findall(r"\bk1_[a-z_]+\b", text)))
    phases = []
    for line in text.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and value.get("edition") == "k1":
            phases.append(value)
    result["phase_work"] = phases[-1] if phases else None
    write_json(directory / f"{label}.measurement.json", result)
    return result


def fresh_directory(path):
    path = Path(path).resolve()
    if path.exists() and any(path.iterdir()):
        raise ValueError(f"refusing to overwrite a nonempty evidence directory: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path


def summary_rows(samples, dimensions):
    groups = {}
    for sample in samples:
        key = tuple(sample[name] for name in dimensions)
        groups.setdefault(key, []).append(sample)
    result = []
    for key, rows in groups.items():
        row = dict(zip(dimensions, key))
        row.update({"samples": len(rows), "exit_codes": [item["exit_code"] for item in rows],
                    "timeouts": sum(item["timed_out"] for item in rows)})
        for quantity in ["wall_ms", "cpu_ms", "peak_rss_kib"]:
            values = [item[quantity] for item in rows if item[quantity] is not None]
            if values:
                row[quantity] = {"median": statistics.median(values), "min": min(values), "max": max(values)}
        result.append(row)
    return result


def operation_source(operations):
    # Unit statements emit one operation each. Return adds a literal + terminator.
    return ("pub let f: Unit -> U32 ! {} resources {depth:1,frame:0} = fn () => do:\n"
            + "  ()\n" * (operations - 2) + "  return 42\n")


def execute_checksum(path, deno):
    script = """const module = await WebAssembly.compile(await Deno.readFile(Deno.args[0]));
if (WebAssembly.Module.imports(module).length) throw new Error('unexpected imports');
const instance = await WebAssembly.instantiate(module), f = instance.exports.f;
if (typeof f !== 'function') throw new Error('missing scalar export');
let checksum = 2166136261;
for (let i = 0; i < 16; i++) { const value = f(); if (value !== 42) throw new Error('wrong result'); checksum = Math.imul(checksum ^ value, 16777619) >>> 0; }
console.log(JSON.stringify({calls:16, result:42, checksum}));"""
    result = subprocess.run([deno, "eval", "--ext=ts", script, str(path)], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(f"Wasm checksum failed: {result.stderr}")
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default="build/blot")
    parser.add_argument("--build-label", required=True)
    parser.add_argument("--operations", default="8192,32768,65536,65537")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--out", default="build/bench-limits")
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    operations = [16] if args.probe else [int(value) for value in args.operations.split(",")]
    rounds = 1 if args.probe else args.rounds
    if not 1 <= rounds <= 100 or not operations or any(not 2 <= value <= 65537 for value in operations) or args.timeout <= 0:
        parser.error("invalid rounds, operation counts or timeout")
    compiler = (ROOT / args.compiler).resolve()
    if not compiler.is_file():
        parser.error(f"compiler does not exist: {compiler}")
    deno = shutil.which("deno")
    if not deno:
        parser.error("Deno is required for executed-Wasm checksums")
    out = fresh_directory(ROOT / args.out)
    metadata = {**machine_metadata(), "format": "K1-LIMIT-BENCHMARK-1", "probe": args.probe,
                "compiler": str(compiler), "candidate_sha256": sha256(compiler), "build_label": args.build_label,
                "compiler_version": subprocess.run([str(compiler), "--version"], capture_output=True, text=True, check=True).stdout.strip(),
                "harness_sha256": sha256(__file__),
                "rounds": rounds, "operations": operations, "policy": "K1-SEM-POLICY-1",
                "deno_version": subprocess.run([deno, "--version"], capture_output=True, text=True, check=True).stdout.strip(),
                "instrumentation": "timing samples omit --timings; one separate phase/work sample per scale",
                "workload": "one function of Unit operations; admission/artifact volume, not guest instruction throughput",
                "source_less": "original module removed before fresh-process inspect and rebuild",
                "artifact_phase_limit": "inspect/rebuild CLI lacks per-phase/work clocks; whole-process measurements are recorded"}
    samples, issues = [], []

    def save():
        write_json(out / "results.json", {"metadata": metadata, "samples": samples, "issues": issues})
        write_json(out / "summary.json", {"metadata": metadata, "summary": summary_rows(samples, ["operations", "case"]), "issues": issues})

    for count in operations:
        text = operation_source(count)
        archive = out / f"source-{count}.blot"
        archive.write_text(text)
        for round_id in range(rounds):
            directory = out / f"ops-{count}-round-{round_id}"
            directory.mkdir()
            source, artifact = directory / "input.blot", directory / "checked.bk1"
            wasm, rebuilt = directory / "source.wasm", directory / "rebuilt.wasm"
            source.write_text(text)

            def run(case, command, artifact_clock=False):
                sample = measure(command, ROOT, directory, case, args.timeout)
                sample.update({"operations": count, "round": round_id, "case": case,
                               "source_sha256": sha256(archive), "source_bytes": archive.stat().st_size,
                               "phase_work_available": sample["phase_work"] is not None})
                for name, path in [("core", artifact), ("wasm", wasm), ("rebuilt", rebuilt)]:
                    if path.exists():
                        sample[name + "_bytes"] = path.stat().st_size
                        sample[name + "_sha256"] = sha256(path)
                if artifact_clock:
                    sample["source_present"] = source.exists()
                samples.append(sample)
                save()
                return sample

            common = [str(source), f"--package-root={directory}", "--opt=off"]
            check = run("source-check", [compiler, "check", *common])
            expected = count <= 65536
            if check["timed_out"] or (check["exit_code"] == 0) != expected or (not expected and "k1_core_limit" not in check["diagnostics"]):
                issues.append({"operations": count, "round": round_id, "case": "source-check", "reason": "unexpected source admission outcome"})
                save()
                continue
            if not expected:
                continue
            attribution_hash = None
            if round_id == 0:
                attributed = directory / "attribution.wasm"
                phase = run("source-attribution", [compiler, "build", *common, "-o", attributed, "--timings"])
                if phase["exit_code"] == 0:
                    attribution_hash = sha256(attributed)
                    phase["wasm_sha256"] = attribution_hash
                    phase["wasm_bytes"] = attributed.stat().st_size
                if phase["exit_code"] != 0 or phase["phase_work"] is None:
                    issues.append({"operations": count, "case": "source-attribution", "reason": "missing build attribution"})
            built = run("source-build-artifact", [compiler, "build", *common, "-o", wasm, f"--emit-core={artifact}"])
            if built["exit_code"] != 0:
                if "k1_artifact_limit" not in built["diagnostics"]:
                    issues.append({"operations": count, "round": round_id, "case": "source-build-artifact", "reason": "unexpected build failure"})
                built["artifact_restart_skipped"] = "artifact exceeds fixed admission cap" if "k1_artifact_limit" in built["diagnostics"] else "source build failed"
                save()
                continue
            original_hash = sha256(wasm)
            built["execution"] = execute_checksum(wasm, deno)
            if attribution_hash is not None and attribution_hash != original_hash:
                issues.append({"operations": count, "case": "source-attribution", "reason": "instrumented build changed executable bytes"})
            source.unlink()
            inspection = run("required-artifact-restart", [compiler, "inspect", artifact], True)
            if inspection["exit_code"] != 0:
                issues.append({"operations": count, "round": round_id, "case": "required-artifact-restart", "reason": "source-less admission failed"})
                save()
                continue
            match = re.search(r"(\d+) functions, (\d+) operations", Path(inspection["stdout"]).read_text())
            inspection["inspected_functions"] = int(match[1]) if match else None
            inspection["inspected_operations_excluding_terminators"] = int(match[2]) if match else None
            if not match or int(match[1]) != 1 or int(match[2]) != count - 1:
                issues.append({"operations": count, "case": "required-artifact-restart", "reason": "unexpected Core inventory"})
            restarted = run("required-artifact-rebuild", [compiler, "rebuild", artifact, "-o", rebuilt, "--opt=off"], True)
            restarted["same_wasm_as_source"] = restarted["exit_code"] == 0 and sha256(rebuilt) == original_hash
            if restarted["exit_code"] == 0:
                restarted["execution"] = execute_checksum(rebuilt, deno)
                restarted["same_execution_as_source"] = restarted["execution"] == built["execution"]
            else:
                restarted["same_execution_as_source"] = False
            if not restarted["same_execution_as_source"]:
                issues.append({"operations": count, "round": round_id, "case": "required-artifact-rebuild", "reason": "rebuild failed or executed checksum differs"})
            save()
            print(f"measured operations={count} round={round_id}", flush=True)
    metadata["candidate_unchanged"] = sha256(compiler) == metadata["candidate_sha256"]
    if not metadata["candidate_unchanged"]:
        issues.append({"reason": "compiler executable changed during measurement"})
    save()
    print(out / "summary.json")
    return 1 if issues else 0


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--measure-child":
        measure_child(sys.argv[2])
    else:
        raise SystemExit(main())
