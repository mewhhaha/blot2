"""Freeze the structural compiler and bounded-inlining measurements.

Historical evidence is immutable. Executables, generated C and Wasm are omitted;
source inputs, tool identities, raw records and content hashes remain available.
"""
import argparse
from pathlib import Path
import shutil
import tarfile

from package_parity import comparisons, digest, read, write

ROOT = Path(__file__).resolve().parent.parent
PREVIOUS = "f84aa746934c4b9ef5cc818bf7402f19f07beffb63b558000d30c0cccdbdb14a"
LEGACY = "fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923"


def check_pairs(data, *, identical_wasm=False, workload=False):
    keys = ("workload",) if workload else ("family", "scale")
    samples = data["samples"]
    assert all(s["exit_code"] == 0 for s in samples)
    for s in samples:
        if s["compiler"] != "candidate":
            continue
        key = tuple(s[k] for k in (*keys, "round"))
        peers = [t for t in samples if t["compiler"] == "baseline" and
                 tuple(t[k] for k in (*keys, "round")) == key]
        if s["round"] < 0 and data["metadata"].get("baseline_kind") == "legacy":
            assert not peers  # Legacy has no matching phase-counter protocol.
            continue
        assert len(peers) == 1, key
        peer = peers[0]
        fields = ["expected"] if workload else ["checksum"]
        if s["round"] >= 0:
            fields += ["runtime_checksum"]
            if not workload:
                fields += ["runtime_calls", "runtime_warmup_calls"]
        assert all(s[k] == peer[k] for k in fields), key
        if identical_wasm:
            assert s["wasm_sha256"] == peer["wasm_sha256"], key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="benchmarks/results/structural")
    destination = ROOT / parser.parse_args().out
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit("refusing to overwrite published evidence")
    qpath = ROOT / "test-results/qualification.json"
    q = read(qpath)
    compiler_hash = digest(ROOT / "build/blot")
    assert q["status"] == "passed" and q["compiler_mode"] == "--release"
    assert q["compiler_sha256"] == compiler_hash
    for path, expected in q["inputs"].items():
        assert digest(ROOT / path) == expected, path
    for path, expected in q["evidence"].items():
        assert digest(ROOT / "test-results" / path) == expected, path
    prior = read(ROOT / "build/structural-baseline/qualification.json")
    assert prior["status"] == "passed" and prior["compiler_sha256"] == PREVIOUS
    assert digest(ROOT / "build/structural-baseline/blot") == PREVIOUS
    for path, expected in prior["inputs"].items():
        assert digest(ROOT / "build/structural-baseline/inputs" / path) == expected, path
    ablations = {name: read(ROOT / "build/structural-attribution" / (name + ".json"))
                 for name in ("context", "tarjan")}
    for name, ablation in ablations.items():
        for path, expected in ablation["source_inputs"].items():
            overlay = ROOT / "build/structural-attribution" / (name + "-overlay") / path
            source = overlay if overlay.exists() else ROOT / "build/structural-baseline/inputs" / path
            assert digest(source) == expected, (name, path)
        assert not ablation["wasm_mismatches"]
    matrices = {
        "context": (96, ablations["context"]["compiler_sha256"], PREVIOUS, True),
        "tarjan": (36, ablations["tarjan"]["compiler_sha256"], PREVIOUS, True),
        "k1": (288, compiler_hash, PREVIOUS, True),
        "k1-chains": (36, compiler_hash, PREVIOUS, True),
        "legacy": (264, compiler_hash, LEGACY, False),
        "legacy-chains": (33, compiler_hash, LEGACY, False),
        "inline": (48, compiler_hash, compiler_hash, False),
        "inline-chains": (12, compiler_hash, compiler_hash, False),
    }
    results, directories = {}, []
    for name, (count, candidate, baseline, identical) in matrices.items():
        directory = ROOT / "build" / ("bench-structural-" + name)
        directories.append(directory)
        data = read(directory / "results.json")
        m = data["metadata"]
        assert len(data["samples"]) == count, (name, len(data["samples"]))
        assert m["candidate_sha256"] == candidate and m["baseline_sha256"] == baseline
        assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark.ts")
        if name not in ablations:
            assert m["qualification"]["input_manifest_sha256"] == q["input_manifest_sha256"]
        check_pairs(data, identical_wasm=identical)
        results[name] = {"metadata": m, "samples": count, "comparisons": comparisons(data)}
    for mode in ("default", "optimizing"):
        name = "inline-control-" + mode
        directory = ROOT / "build" / ("bench-structural-" + name)
        directories.append(directory)
        data = read(directory / "results.json")
        assert len(data["samples"]) == 20 and len(data["metadata"]["runs"]) == 5
        for run in data["metadata"]["runs"]:
            m = run["metadata"]
            assert m["candidate_sha256"] == m["baseline_sha256"] == compiler_hash
            assert m["qualification"]["input_manifest_sha256"] == q["input_manifest_sha256"]
            assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark.ts")
        check_pairs(data)
        results[name] = {"metadata": data["metadata"], "samples": 20, "comparisons": comparisons(data)}
    directory = ROOT / "build/bench-structural-workloads"
    directories.append(directory)
    data = read(directory / "results.json")
    m = data["metadata"]
    assert len(data["samples"]) == 24
    assert m["candidate_sha256"] == m["baseline_sha256"] == compiler_hash
    assert m["candidate_opt"] == "release" and m["baseline_opt"] == "fast"
    assert m["qualification"] == q["input_manifest_sha256"]
    assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark_workloads.ts")
    check_pairs(data, workload=True)
    normalized = {"samples": [dict(s, family=s["workload"], scale=s["kernel_iterations_per_call"])
                               for s in data["samples"]]}
    results["workloads"] = {"metadata": m, "samples": 24, "comparisons": comparisons(normalized)}
    directory = ROOT / "build/bench-structural-sessions"
    directories.append(directory)
    data = read(directory / "results.json")
    m, samples = data["metadata"], data["samples"]
    assert len(samples) == 300 and len(m["runs"]) == 10
    assert m["compiler_sha256"] == {"baseline": PREVIOUS, "candidate": compiler_hash}
    assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark_sessions.py")
    assert all(s["response"]["ok"] == (s["case"] != "rejected-edit") for s in samples)
    for run in m["runs"]:
        assert run["metadata"]["candidate_sha256"] == m["compiler_sha256"][run["compiler"]]
    results["sessions"] = {"metadata": m, "samples": 300, "comparisons": comparisons(data, True)}

    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(qpath, destination / "qualification.json")
    for name, value in results.items():
        write(destination / (name + ".json"), value)
    selected = {ROOT / path for path in q["inputs"]}
    selected.update(ROOT / "test-results" / path for path in q["evidence"])
    selected.update({qpath, ROOT / "test-results/structural-gate.log",
                     ROOT / "benchmarks/package_structural.py", ROOT / "benchmarks/package_parity.py",
                     ROOT / "docs/CONTRACT.md", ROOT / "build/run_structural.py", ROOT / "build/run_inline_control.py",
                     ROOT / "build/structural-measurements.json", ROOT / "build/structural-host-observation.json"})
    directories += [ROOT / "build/structural-baseline", ROOT / "build/structural-attribution",
                    ROOT / "build/structural-profile", ROOT / "benchmarks/workloads"]
    for directory in directories:
        selected.update(p for p in directory.rglob("*") if p.is_file() and
                        (p.suffix in {".json", ".log", ".stdout", ".stderr", ".blot", ".py", ".txt", ".goose"}
                         or "inputs" in p.relative_to(directory).parts))
    selected.update(ROOT.glob("build/structural-*.log"))
    archive = destination / "raw-evidence.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for path in sorted(selected):
            bundle.add(path, arcname=str(path.relative_to(ROOT)), recursive=False)
    previous_manifest = ROOT / "benchmarks/results/publication/manifest.json"
    count = sum(r["samples"] for r in results.values())
    write(destination / "manifest.json", {
        "format": "K1-STRUCTURAL-EVIDENCE-1", "base_commit": q["base_commit"],
        "compiler_sha256": compiler_hash, "previous_k1_sha256": PREVIOUS, "legacy_sha256": LEGACY,
        "input_manifest_sha256": q["input_manifest_sha256"], "qualified_inputs": len(q["inputs"]),
        "sample_count": count, "prior_package": str(previous_manifest.relative_to(ROOT)),
        "prior_manifest_sha256": digest(previous_manifest),
        "archive": archive.name, "archive_sha256": digest(archive),
        "archive_files": {str(p.relative_to(ROOT)): digest(p) for p in sorted(selected)},
        "files": {p.name: digest(p) for p in sorted(destination.iterdir()) if p.is_file()},
        "scope": "Five counterbalanced pairs, all samples retained. Isolated validator-view and Tarjan ablations "
                 "are compile-time controls with focused qualification only; final combined candidate has the full gate. "
                 "Default-engine final synthetic runtime includes JS/Wasm calls; loop kernels use varying seeds and exact references. "
                 "Retained sessions use optimization off. Prior/new off-tier K1 Wasm bytes agree. "
                 "The diamond runtime regression prompted fresh-engine/default and no-liftoff controls; all original samples retained. "
                 "Host placement/frequency/load/cache uncontrolled. No universal parity, gdev or compiler rebuild-time claim.",
    })
    print(f"packaged {len(selected)} files, {count} samples under {destination.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
