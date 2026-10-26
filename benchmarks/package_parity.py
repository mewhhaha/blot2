"""Archive the parity investigation, qualified inputs and all measured samples.

Historical packages remain immutable. Generated executables, C and Wasm are
excluded; their hashes and the sources needed to reproduce them are retained.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import statistics
import tarfile

ROOT = Path(__file__).resolve().parent.parent
LEGACY = "fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923"
PREVIOUS = "b54c172a659c9346604fb7dae5b8b76eb9852a96e9f962ce4ab858e5ab013292"
FIRST = "38a407389d943ab593271363281d1910636f69b5ef6dab101f46b713cf4cf9f4"


def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def stats(values):
    return {"median": statistics.median(values), "min": min(values), "max": max(values)}


def comparisons(results, sessions=False):
    samples = results["samples"]
    keys = ("case", "scale") if sessions else ("family", "scale")
    groups = sorted({tuple(s[k] for k in keys) for s in samples})
    rows = []
    for key in groups:
        row = dict(zip(keys, key))
        selected = [s for s in samples if tuple(s[k] for k in keys) == key and
                    (sessions or s["round"] >= 0)]
        metrics = ["wall_ms"] if sessions else ["wall_ms", "cpu_ms", "peak_rss_kib", "runtime_ns_per_call"]
        for metric in metrics:
            pair = {who: [s for s in selected if s["compiler"] == who] for who in ("baseline", "candidate")}
            round_key = "pair_round" if sessions else "round"
            paired = {who: {s[round_key]: s[metric] for s in group} for who, group in pair.items()}
            assert paired["baseline"].keys() == paired["candidate"].keys()
            row[metric] = {who: stats([s[metric] for s in group]) for who, group in pair.items()}
            # CPU sampling can round a short process to zero; omit that ratio.
            ratios = [paired["candidate"][i] / value for i, value in paired["baseline"].items() if value]
            row[metric]["paired_candidate_over_baseline"] = stats(ratios) if ratios else None
        rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="benchmarks/results/parity")
    args = parser.parse_args()
    destination = ROOT / args.out
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit("refusing to overwrite published evidence")
    qualification_path = ROOT / "test-results/qualification.json"
    qualification = read(qualification_path)
    compiler_hash = digest(ROOT / "build/blot")
    assert qualification["status"] == "passed" and qualification["compiler_mode"] == "--release"
    assert qualification["compiler_sha256"] == compiler_hash
    for path, expected in qualification["inputs"].items():
        assert digest(ROOT / path) == expected, path
    for path, expected in qualification["evidence"].items():
        assert digest(ROOT / "test-results" / path) == expected, path
    assert "BLOT_TEST_COMPLETE 104\n" in (ROOT / "test-results/native.log").read_text()
    assert "84 passed | 0 failed" in (ROOT / "test-results/deno.log").read_text()
    assert digest(ROOT / "build/parity-baseline/blot") == PREVIOUS
    assert digest(ROOT / "build/parity-first-candidate/blot") == FIRST
    first = read(ROOT / "build/parity-first-candidate/qualification.json")
    assert first["status"] == "passed" and first["compiler_sha256"] == FIRST
    for path, expected in first["inputs"].items():
        assert digest(ROOT / "build/parity-first-candidate/inputs" / path) == expected, path
    for path, expected in first["evidence"].items():
        assert digest(ROOT / "build/parity-first-candidate/evidence" / path) == expected, path

    # count includes separate instrumented K1 phase samples, never legacy phases.
    matrices = {
        "before": (264, PREVIOUS, LEGACY),
        "before-chains": (11, PREVIOUS, LEGACY),
        "after": (264, FIRST, LEGACY),
        "optimized-engine": (66, FIRST, LEGACY),
        "locals-probe": (32, "27331a5fae9f", FIRST),
        "final": (264, compiler_hash, LEGACY),
        "final-chains": (33, compiler_hash, LEGACY),
        "final-optimized-engine": (66, compiler_hash, LEGACY),
        "final-k1": (96, compiler_hash, PREVIOUS),
        "final-release-tier": (33, compiler_hash, LEGACY),
    }
    all_results = {}
    directories = []
    for name, (count, candidate, baseline) in matrices.items():
        directory = ROOT / "build" / ("bench-parity-" + name)
        directories.append(directory)
        results = read(directory / "results.json")
        metadata, samples = results["metadata"], results["samples"]
        assert len(samples) == count, (name, len(samples))
        assert metadata["candidate_sha256"].startswith(candidate) and metadata["baseline_sha256"] == baseline
        assert all(s["exit_code"] == 0 for s in samples)
        for s in samples:
            if s["compiler"] != "candidate" or s["round"] < 0:
                continue
            peer = next(t for t in samples if t["compiler"] == "baseline" and
                        (t["family"], t["scale"], t["round"]) == (s["family"], s["scale"], s["round"]))
            assert all(s[k] == peer[k] for k in ("checksum", "runtime_checksum", "runtime_calls", "runtime_warmup_calls"))
        if name.startswith("final"):
            assert metadata["qualification"]["input_manifest_sha256"] == qualification["input_manifest_sha256"]
            harness = "build/benchmark_tiers.ts" if name == "final-release-tier" else "scripts/benchmark.ts"
            assert metadata["harness_sha256"] == digest(ROOT / harness)
        all_results[name] = {"metadata": metadata, "samples": len(samples), "comparisons": comparisons(results)}

    directory = ROOT / "build/bench-parity-sessions"
    directories.append(directory)
    sessions = read(directory / "results.json")
    assert len(sessions["samples"]) == 300 and len(sessions["metadata"]["runs"]) == 10
    assert sessions["metadata"]["compiler_sha256"] == {"baseline": PREVIOUS, "candidate": compiler_hash}
    assert sessions["metadata"]["harness_sha256"] == digest(ROOT / "scripts/benchmark_sessions.py")
    assert all(s["response"]["ok"] == (s["case"] != "rejected-edit") for s in sessions["samples"])
    for run in sessions["metadata"]["runs"]:
        assert run["metadata"]["candidate_sha256"] == sessions["metadata"]["compiler_sha256"][run["compiler"]]
    all_results["sessions"] = {"metadata": sessions["metadata"], "samples": 300, "comparisons": comparisons(sessions, True)}
    telemetry = ROOT / "build/parity-runtime-telemetry.json"
    assert read(telemetry)["compiler_sha256"] == compiler_hash
    assert read(telemetry)["samples"] == read(ROOT / "benchmarks/results/k1-initial/runtime-telemetry.json")["samples"]

    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(qualification_path, destination / "qualification.json")
    shutil.copy2(telemetry, destination / "runtime-telemetry.json")
    for name, result in all_results.items():
        write(destination / (name + ".json"), result)
    selected = {ROOT / path for path in qualification["inputs"]}
    selected.update(ROOT / "test-results" / path for path in qualification["evidence"])
    selected.update({qualification_path, telemetry, ROOT / "test-results/parity-final-gate.log",
                     ROOT / "benchmarks/package_parity.py", ROOT / "build/parity-baseline/qualification.json",
                     ROOT / "build/benchmark_tiers.ts", ROOT / "build/parity-run-provenance.json",
                     ROOT / "build/parity-host-observation.json", ROOT / "build/parity-tier-code-comparison.json"})
    directories += [ROOT / "build/parity-first-candidate", ROOT / "build/parity-profile"]
    for directory in directories:
        selected.update(p for p in directory.rglob("*") if p.is_file() and
                        (p.suffix in {".json", ".log", ".stdout", ".stderr", ".blot", ".py", ".txt"} or
                         "inputs" in p.relative_to(directory).parts))
    archive = destination / "raw-evidence.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for path in sorted(selected):
            bundle.add(path, arcname=str(path.relative_to(ROOT)), recursive=False)
    manifest = {
        "format": "K1-PARITY-EVIDENCE-1", "base_commit": qualification["base_commit"],
        "compiler_sha256": compiler_hash, "legacy_sha256": LEGACY, "previous_k1_sha256": PREVIOUS,
        "first_candidate_sha256": FIRST, "input_manifest_sha256": qualification["input_manifest_sha256"],
        "qualified_inputs": len(qualification["inputs"]), "sample_count": sum(r["samples"] for r in all_results.values()),
        "archive": archive.name, "archive_sha256": digest(archive),
        "archive_files": {str(p.relative_to(ROOT)): digest(p) for p in sorted(selected)},
        "files": {p.name: digest(p) for p in sorted(destination.iterdir()) if p.is_file()},
        "scope": "Synthetic fresh compilation and Wasm runtime against legacy; retained sessions against prior K1. "
                 "All samples retained. Later matrices encountered high host load; paired ratios and ranges are supplied. "
                 "Engine control is separate from default-engine results. Debug local-compaction probe is runtime-only. "
                 "No gdev migration, compiler rebuild-time rerun, full parity claim or individual-change ablations.",
    }
    write(destination / "manifest.json", manifest)
    print(f"packaged {len(selected)} files, {manifest['sample_count']} samples under {destination.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
