"""Freeze the Sol review gate and before/after measurements, without binaries.

Expected inputs are the directories in SOL_REVIEW.md. Existing published output
is never overwritten. Raw sources, logs, harnesses and qualified compiler inputs
are archived so an uncommitted candidate is still identified by exact content.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parent.parent
BASELINE = "7b61cff1941de683e99269dc2a3c30cc137201d9bca8f98e90a8d0bbc02366b2"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="benchmarks/results/sol-review")
    args = parser.parse_args()
    destination = ROOT / args.out
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit("refusing to overwrite published evidence")
    qualification_path = ROOT / "test-results/qualification.json"
    qualification = read(qualification_path)
    compiler_hash = digest(ROOT / "build/blot")
    assert qualification["status"] == "passed"
    assert qualification["compiler_mode"] == "--release"
    assert qualification["compiler_sha256"] == compiler_hash
    for path, expected in qualification["inputs"].items():
        assert digest(ROOT / path) == expected, path
    for path, expected in qualification["evidence"].items():
        assert digest(ROOT / "test-results" / path) == expected, path
    assert digest(ROOT / "build/review-baseline/blot") == BASELINE
    directories = {"paired": ROOT / "build/bench-sol-paired",
                   "chains": ROOT / "build/bench-sol-chains",
                   "sessions": ROOT / "build/bench-sol-sessions"}
    for name, directory in directories.items():
        results = read(directory / "results.json")
        summary = read(directory / "summary.json")
        metadata, samples = results["metadata"], results["samples"]
        assert len(samples) == {"paired": 288, "chains": 36, "sessions": 300}[name]
        assert all(row["samples"] == 5 for row in summary["summary"])
        if name == "sessions":
            assert metadata["compiler_sha256"] == {"baseline": BASELINE, "candidate": compiler_hash}
            assert metadata["harness_sha256"] == digest(ROOT / "scripts/benchmark_sessions.py")
            assert len(metadata["runs"]) == 10
            assert all(s["response"]["ok"] == (s["case"] != "rejected-edit") for s in samples)
            for run in metadata["runs"]:
                assert run["metadata"]["candidate_sha256"] == metadata["compiler_sha256"][run["compiler"]]
        else:
            assert metadata["candidate_sha256"] == compiler_hash
            assert metadata["baseline_sha256"] == BASELINE and metadata["baseline_kind"] == "k1"
            assert metadata["harness_sha256"] == digest(ROOT / "scripts/benchmark.ts")
            assert metadata["qualification"]["input_manifest_sha256"] == qualification["input_manifest_sha256"]
            assert all(s["exit_code"] == 0 for s in samples)
            for s in samples:
                if s["compiler"] != "candidate":
                    continue
                peer = next(t for t in samples if t["compiler"] == "baseline" and
                            (t["family"], t["scale"], t["round"]) == (s["family"], s["scale"], s["round"]))
                assert peer["checksum"] == s["checksum"]
                if s["round"] >= 0:
                    assert s["runtime_checksum"] == peer["runtime_checksum"]
                    assert s["runtime_calls"] == peer["runtime_calls"]
                    assert s["runtime_warmup_calls"] == peer["runtime_warmup_calls"]
    telemetry = ROOT / "build/sol-runtime-telemetry.json"
    assert read(telemetry)["compiler_sha256"] == compiler_hash
    assert read(telemetry)["samples"] == read(ROOT / "benchmarks/results/k1-initial/runtime-telemetry.json")["samples"]
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(qualification_path, destination / "qualification.json")
    shutil.copy2(telemetry, destination / "runtime-telemetry.json")
    for name, directory in directories.items():
        shutil.copy2(directory / "summary.json", destination / (name + ".json"))
    # Include qualified source inputs, not generated C, executables or Wasm/Core.
    selected = {ROOT / path for path in qualification["inputs"]}
    selected.update(ROOT / "test-results" / path for path in qualification["evidence"])
    selected.update({qualification_path, telemetry, ROOT / "test-results/sol-review-gate.log",
                     ROOT / "benchmarks/package_review.py", ROOT / "build/review-baseline/provenance.json",
                     ROOT / "build/review-baseline/qualification.json"})
    for directory in directories.values():
        selected.update(path for path in directory.rglob("*") if path.is_file() and
                        path.suffix in {".json", ".log", ".stdout", ".stderr", ".blot", ".py"})
    archive = destination / "raw-evidence.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for path in sorted(selected):
            bundle.add(path, arcname=str(path.relative_to(ROOT)), recursive=False)
    manifest = {
        "format": "K1-SOL-REVIEW-EVIDENCE-1", "base_commit": qualification["base_commit"],
        "compiler_sha256": compiler_hash, "baseline_sha256": BASELINE,
        "input_manifest_sha256": qualification["input_manifest_sha256"],
        "archive": archive.name, "archive_sha256": digest(archive),
        "archive_files": {str(p.relative_to(ROOT)): digest(p) for p in sorted(selected)},
        "files": {p.name: digest(p) for p in sorted(destination.iterdir()) if p.is_file()},
        "scope": "Four reviewed changes measured together; no individual-change ablations. "
                 "Current source content is pinned by the qualification manifest, not base_commit. "
                 "Five counterbalanced rounds; all samples retained. CPU/frequency/cache uncontrolled. "
                 "Compiler rebuild-time and operation-limit matrices were not rerun for this review.",
    }
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"packaged {len(selected)} files under {destination.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
