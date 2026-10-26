"""Freeze one bounded runtime pass and its isolated-engine kernel comparisons."""
import argparse
from pathlib import Path
import shutil
import tarfile
from package_parity import comparisons, digest, read, write

ROOT = Path(__file__).resolve().parent.parent
BASELINE = "ca49141eea94f5f3e1cb3d87930bb41b5409e5dedc777b991c6ed6b2eebcf527"
BASE_COMMIT = "900ede209ca16b9728347fbcea58d44228a3b16f"


def paired(data, keys):
    samples = data["samples"]
    assert all(s["exit_code"] == 0 for s in samples)
    for sample in samples:
        if sample["compiler"] != "candidate":
            continue
        key = tuple(sample[k] for k in (*keys, "round"))
        peers = [s for s in samples if s["compiler"] == "baseline" and
                 tuple(s[k] for k in (*keys, "round")) == key]
        assert len(peers) == 1, key
        other = peers[0]
        fields = ["expected"] if keys == ("workload",) else ["checksum"]
        if sample["round"] >= 0:
            fields += ["runtime_checksum", "runtime_calls", "runtime_warmup_calls"]
        assert all(sample[k] == other[k] for k in fields), key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="benchmarks/results/runtime")
    dest = ROOT / parser.parse_args().out
    if dest.exists() and any(dest.iterdir()):
        raise SystemExit("refusing to overwrite published evidence")
    qpath = ROOT / "test-results/qualification.json"
    q = read(qpath)
    compiler = digest(ROOT / "build/blot")
    assert q["status"] == "passed" and q["compiler_mode"] == "--release"
    assert q["compiler_sha256"] == compiler and q["base_commit"] == BASE_COMMIT
    for path, sha in q["inputs"].items():
        assert digest(ROOT / path) == sha, path
    for path, sha in q["evidence"].items():
        assert digest(ROOT / "test-results" / path) == sha, path
    baseline = ROOT / "build/runtime-pass-baseline"
    prior = read(baseline / "qualification.json")
    assert prior["status"] == "passed" and prior["compiler_sha256"] == BASELINE
    assert digest(baseline / "blot") == BASELINE
    for path, sha in prior["inputs"].items():
        assert digest(baseline / "inputs" / path) == sha, path
    for path, sha in prior["evidence"].items():
        assert digest(baseline / "evidence" / path) == sha, path
    results, directories = {}, []
    for engine in ("default", "optimizing"):
        directory = ROOT / "build" / ("bench-runtime-pass-" + engine)
        directories.append(directory)
        data = read(directory / "results.json")
        m = data["metadata"]
        assert len(data["samples"]) == 60
        assert m["candidate_sha256"] == compiler and m["baseline_sha256"] == BASELINE
        assert m["candidate_opt"] == m["baseline_opt"] == "off"
        assert m["qualification"] == q["input_manifest_sha256"]
        assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark_workloads.ts")
        assert m["runtime_worker_sha256"] == digest(ROOT / "scripts/benchmark_runtime_worker.ts")
        assert m["reference_models_sha256"] == digest(ROOT / "scripts/runtime_workloads.ts")
        paired(data, ("workload",))
        normalized = {"samples": [dict(s, family=s["workload"], scale=s["kernel_iterations_per_call"])
                                   for s in data["samples"]]}
        results[engine] = {"metadata": m, "samples": 60, "comparisons": comparisons(normalized)}
    for name, count in (("compile", 96), ("compile-chains", 12)):
        directory = ROOT / "build" / ("bench-runtime-pass-" + name)
        directories.append(directory)
        data = read(directory / "results.json")
        m = data["metadata"]
        assert len(data["samples"]) == count
        assert m["candidate_sha256"] == compiler and m["baseline_sha256"] == BASELINE
        assert m["candidate_opt"] == m["baseline_opt"] == "off"
        assert m["qualification"]["input_manifest_sha256"] == q["input_manifest_sha256"]
        assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark.ts")
        paired(data, ("family", "scale"))
        results[name] = {"metadata": m, "samples": count, "comparisons": comparisons(data)}
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(qpath, dest / "qualification.json")
    for name, data in results.items():
        write(dest / (name + ".json"), data)
    selected = {ROOT / p for p in q["inputs"]}
    selected.update(ROOT / "test-results" / p for p in q["evidence"])
    selected.update({qpath, ROOT / "test-results/runtime-pass-gate.log", ROOT / "docs/CONTRACT.md",
                     ROOT / "benchmarks/package_runtime.py", ROOT / "benchmarks/package_parity.py",
                     ROOT / "build/run_runtime_pass.py", ROOT / "build/runtime-pass-measurements.json",
                     ROOT / "build/runtime-pass-host-observation.json"})
    directories += [baseline, ROOT / "benchmarks/workloads", ROOT / "build/runtime-pass-attribution"]
    for directory in directories:
        selected.update(p for p in directory.rglob("*") if p.is_file() and
                        (p.suffix in {".json", ".log", ".stdout", ".stderr", ".blot", ".py", ".txt"} or
                         "inputs" in p.relative_to(directory).parts))
    selected.update(ROOT.glob("build/runtime-pass-*.log"))
    archive = dest / "raw-evidence.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for path in sorted(selected):
            bundle.add(path, arcname=str(path.relative_to(ROOT)), recursive=False)
    previous = ROOT / "benchmarks/results/structural/manifest.json"
    write(dest / "manifest.json", {
        "format": "K1-RUNTIME-EVIDENCE-1", "base_commit": BASE_COMMIT,
        "compiler_sha256": compiler, "previous_k1_sha256": BASELINE,
        "input_manifest_sha256": q["input_manifest_sha256"], "qualified_inputs": len(q["inputs"]),
        "sample_count": sum(r["samples"] for r in results.values()),
        "prior_package": str(previous.relative_to(ROOT)), "prior_manifest_sha256": digest(previous),
        "archive": archive.name, "archive_sha256": digest(archive),
        "archive_files": {str(p.relative_to(ROOT)): digest(p) for p in sorted(selected)},
        "files": {p.name: digest(p) for p in sorted(dest.iterdir()) if p.is_file()},
        "scope": "One bounded pass: register-only phi scratch omission and four-byte payload copy lowering. "
                 "Five counterbalanced pairs of five loop kernels; fresh Deno process per artifact; default and optimizing-only engines separate. "
                 "Exact varying-seed references and checksums, compile CPU/RSS and separate phase builds. "
                 "Compile controls use short runtime checks only. All samples retained. No independent ablation, "
                 "new legacy/gdev comparison, syntax/ABI change or universal performance claim. Host placement/load/frequency/cache uncontrolled.",
    })
    print(f"packaged {len(selected)} files and {sum(r['samples'] for r in results.values())} samples")


if __name__ == "__main__":
    main()
