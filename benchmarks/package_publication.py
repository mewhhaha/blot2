"""Freeze the publication follow-up to the immutable parity investigation."""
import argparse
from pathlib import Path
import shutil
import tarfile

from package_parity import comparisons, digest, read, write

ROOT = Path(__file__).resolve().parent.parent
BASELINE = "96ad70d96ecc03847508fcf4f49fcd3885fdbccd647e9d96cb3aeca25fbdd420"
LEGACY = "fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="benchmarks/results/publication")
    destination = ROOT / parser.parse_args().out
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit("refusing to overwrite published evidence")
    qualification_path = ROOT / "test-results/qualification.json"
    q = read(qualification_path)
    compiler_hash = digest(ROOT / "build/blot")
    assert q["status"] == "passed" and q["compiler_mode"] == "--release"
    assert q["compiler_sha256"] == compiler_hash
    for path, expected in q["inputs"].items():
        assert digest(ROOT / path) == expected, path
    for path, expected in q["evidence"].items():
        assert digest(ROOT / "test-results" / path) == expected, path
    assert "BLOT_TEST_COMPLETE 104\n" in (ROOT / "test-results/native.log").read_text()
    assert "85 passed | 0 failed" in (ROOT / "test-results/deno.log").read_text()
    assert digest(ROOT / "build/parity-before-publication/blot") == BASELINE
    prior_manifest = ROOT / "benchmarks/results/parity/manifest.json"
    assert read(prior_manifest)["compiler_sha256"] == BASELINE
    results = {}
    directories = []
    for name, count, baseline in [("final", 264, LEGACY), ("chains", 33, LEGACY), ("k1", 96, BASELINE)]:
        directory = ROOT / "build" / ("bench-publication-" + name)
        directories.append(directory)
        data = read(directory / "results.json")
        m, samples = data["metadata"], data["samples"]
        assert len(samples) == count and all(s["exit_code"] == 0 for s in samples)
        assert m["candidate_sha256"] == compiler_hash and m["baseline_sha256"] == baseline
        assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark.ts")
        assert m["qualification"]["input_manifest_sha256"] == q["input_manifest_sha256"]
        for s in samples:
            if s["compiler"] != "candidate" or s["round"] < 0:
                continue
            peer = next(t for t in samples if t["compiler"] == "baseline" and
                        (t["family"], t["scale"], t["round"]) == (s["family"], s["scale"], s["round"]))
            assert all(s[k] == peer[k] for k in ("checksum", "runtime_checksum", "runtime_calls", "runtime_warmup_calls"))
            if name == "k1":
                assert s["wasm_sha256"] == peer["wasm_sha256"], "publication changed emitted bytes"
        results[name] = {"metadata": m, "samples": len(samples), "comparisons": comparisons(data)}
    directory = ROOT / "build/bench-publication-sessions"
    directories.append(directory)
    data = read(directory / "results.json")
    m, samples = data["metadata"], data["samples"]
    assert len(samples) == 300 and len(m["runs"]) == 10
    assert m["compiler_sha256"] == {"baseline": BASELINE, "candidate": compiler_hash}
    assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark_sessions.py")
    assert all(s["response"]["ok"] == (s["case"] != "rejected-edit") for s in samples)
    for run in m["runs"]:
        assert run["metadata"]["candidate_sha256"] == m["compiler_sha256"][run["compiler"]]
    results["sessions"] = {"metadata": m, "samples": 300, "comparisons": comparisons(data, True)}
    telemetry = ROOT / "build/publication-runtime-telemetry.json"
    assert read(telemetry)["compiler_sha256"] == compiler_hash
    assert read(telemetry)["samples"] == read(ROOT / "benchmarks/results/parity/runtime-telemetry.json")["samples"]
    sync = read(ROOT / "build/parity-sync-attribution/results.json")
    assert sync["compiler_sha256"] == BASELINE and len(sync["samples"]) == 10
    assert len({s["wasm_sha256"] for s in sync["samples"]}) == 1
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(qualification_path, destination / "qualification.json")
    shutil.copy2(telemetry, destination / "runtime-telemetry.json")
    for name, value in results.items():
        write(destination / (name + ".json"), value)
    selected = {ROOT / path for path in q["inputs"]}
    selected.update(ROOT / "test-results" / path for path in q["evidence"])
    selected.update({qualification_path, telemetry, ROOT / "test-results/parity-publication-gate.log",
                     ROOT / "benchmarks/package_publication.py", ROOT / "benchmarks/package_parity.py",
                     ROOT / "docs/CONTRACT.md", ROOT / "build/parity-before-publication/qualification.json",
                     ROOT / "build/parity-sync-profile.c", ROOT / "build/parity-sync-profile.stderr",
                     ROOT / "build/publication-host-observation.json"})
    directories.append(ROOT / "build/parity-sync-attribution")
    for directory in directories:
        selected.update(p for p in directory.rglob("*") if p.is_file() and
                        p.suffix in {".json", ".log", ".stdout", ".stderr", ".blot", ".py"})
    archive = destination / "raw-evidence.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for path in sorted(selected):
            bundle.add(path, arcname=str(path.relative_to(ROOT)), recursive=False)
    write(destination / "manifest.json", {
        "format": "K1-PUBLICATION-EVIDENCE-1", "base_commit": q["base_commit"],
        "compiler_sha256": compiler_hash, "previous_k1_sha256": BASELINE, "legacy_sha256": LEGACY,
        "input_manifest_sha256": q["input_manifest_sha256"], "qualified_inputs": len(q["inputs"]),
        "sample_count": sum(r["samples"] for r in results.values()),
        "prior_package": str(prior_manifest.relative_to(ROOT)), "prior_manifest_sha256": digest(prior_manifest),
        "archive": archive.name, "archive_sha256": digest(archive),
        "archive_files": {str(p.relative_to(ROOT)): digest(p) for p in sorted(selected)},
        "files": {p.name: digest(p) for p in sorted(destination.iterdir()) if p.is_file()},
        "scope": "Generated Wasm uses atomic buffered publication without durable-storage acknowledgement. "
                 "Five counterbalanced pairs; all samples retained. Fresh compile/runtime against legacy, "
                 "retained sessions against the prior qualified K1. Prior/new K1 Wasm bytes and guest storage counters agree. "
                 "Host frequency/load/cache uncontrolled; no universal performance parity or gdev claim.",
    })
    print(f"packaged {len(selected)} files, 693 samples under {destination.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
