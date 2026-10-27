"""Freeze the qualified K1 versus main comparison, including main provenance."""
import argparse
from pathlib import Path
import shutil
import tarfile
from package_parity import comparisons, digest, read, write

ROOT = Path(__file__).resolve().parent.parent
MAIN = "1e39b5d8a4268b9edf769c2813d5231abe1c963b"
LEGACY = "fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923"
CANDIDATE = "94b3d24012f8868a8eb7e8e6351edcfea9529c3d7de36845d10b0b2e47f032bd"


def check_pairs(data, keys):
    samples = data["samples"]
    groups = {tuple(s[k] for k in keys) for s in samples}
    for key in groups:
        selected = [s for s in samples if tuple(s[k] for k in keys) == key]
        identities = [(s["compiler"], s["round"]) for s in selected]
        expected = [(who, r) for who in ("baseline", "candidate") for r in range(5)]
        assert sorted(identities) == sorted(expected + [("candidate", -1)]), key
        for r in range(5):
            pair = {s["compiler"]: s for s in selected if s["round"] == r}
            fields = ["expected"] if keys == ("workload",) else ["checksum"]
            fields += ["runtime_checksum", "runtime_calls", "runtime_warmup_calls"]
            assert all(pair["candidate"][f] == pair["baseline"][f] for f in fields), (key, r)
    for s in samples:
        assert s["exit_code"] == 0
        assert digest(Path(s["command"][2])) == s["source_sha256"]
        command = s["command"]
        wasm = command[command.index("-o") + 1] if "-o" in command else command[3]
        assert digest(Path(wasm)) == s["wasm_sha256"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="benchmarks/results/main-comparison")
    dest = ROOT / parser.parse_args().out
    if dest.exists() and any(dest.iterdir()):
        raise SystemExit("refusing to overwrite published evidence")
    qpath = ROOT / "test-results/qualification.json"
    q = read(qpath)
    assert q["status"] == "passed" and q["compiler_mode"] == "--release"
    assert q["compiler_sha256"] == digest(ROOT / "build/blot") == CANDIDATE
    for path, sha in q["inputs"].items():
        assert digest(ROOT / path) == sha, path
    for path, sha in q["evidence"].items():
        assert digest(ROOT / "test-results" / path) == sha, path
    provenance_dir = ROOT / "build/main-comparison-provenance"
    provenance = read(provenance_dir / "provenance.json")
    assert provenance["main_revision"] == provenance["remote_main_revision"] == MAIN
    assert provenance["legacy_compiler_sha256"] == digest(Path(provenance["legacy_compiler"])) == LEGACY
    assert provenance["candidate_compiler_sha256"] == CANDIDATE
    for blob in provenance["main_blobs"].values():
        assert digest(provenance_dir / blob["copy"]) == blob["sha256"]
    legacy_q = read(provenance_dir / "main-runtime-memory.json")["qualification"]
    assert legacy_q["gate_success"] and legacy_q["compiler_sha256"] == LEGACY
    assert LEGACY in (provenance_dir / "main-CONTINUE.md").read_text()

    matrices = {"default": ("runtime", 55), "optimizing": ("optimizing", 55),
                "compile": ("compile", 88), "compile-chains": ("chains", 11)}
    results, directories = {}, [provenance_dir]
    for name, (folder, count) in matrices.items():
        directory = ROOT / "build" / ("bench-main-" + folder)
        directories.append(directory)
        data = read(directory / "results.json")
        m = data["metadata"]
        assert len(data["samples"]) == count and m["rounds"] == 5
        assert m["candidate_sha256"] == CANDIDATE and m["baseline_sha256"] == LEGACY
        assert m["candidate_opt"] == "off" and m["baseline_opt"] == "legacy-default"
        assert m["baseline_revision"] == MAIN
        kernels = name in ("default", "optimizing")
        if kernels:
            assert m["engine"] == name and m["warmup_calls"] == m["timed_calls"] == 20000
            assert m["qualification"] == q["input_manifest_sha256"]
            assert m["harness_sha256"] == digest(ROOT / "benchmarks/compare_main.ts")
            assert m["runtime_worker_sha256"] == digest(ROOT / "benchmarks/main_runtime_worker.ts")
            assert m["reference_models_sha256"] == digest(ROOT / "scripts/runtime_workloads.ts")
            check_pairs(data, ("workload",))
            assert all(s["ownership_hooks"] == (s["compiler"] == "baseline" and
                       s["workload"] == "generic_pair") for s in data["samples"])
            data = {"samples": [dict(s, family=s["workload"], scale=s["kernel_iterations_per_call"])
                                for s in data["samples"]]}
        else:
            assert m["qualification"]["input_manifest_sha256"] == q["input_manifest_sha256"]
            assert m["harness_sha256"] == digest(ROOT / "scripts/benchmark.ts")
            check_pairs(data, ("family", "scale"))
        results[name] = {"metadata": m, "samples": count, "comparisons": comparisons(data)}
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(qpath, dest / "qualification.json")
    shutil.copy2(provenance_dir / "provenance.json", dest / "provenance.json")
    for name, data in results.items():
        write(dest / (name + ".json"), data)
    selected = {ROOT / p for p in q["inputs"]}
    selected.update(ROOT / "test-results" / p for p in q["evidence"])
    selected.update({qpath, ROOT / "benchmarks/compare_main.ts", ROOT / "benchmarks/main_runtime_worker.ts",
                     ROOT / "benchmarks/package_main.py", ROOT / "benchmarks/package_parity.py"})
    directories += [ROOT / "benchmarks/workloads", ROOT / "benchmarks/workloads-main"]
    for directory in directories:
        selected.update(p for p in directory.rglob("*") if p.is_file() and
                        p.suffix in {".json", ".log", ".stdout", ".stderr", ".blot", ".md", ".txt"})
    archive = dest / "raw-evidence.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for path in sorted(selected):
            bundle.add(path, arcname=str(path.relative_to(ROOT)), recursive=False)
    write(dest / "manifest.json", {
        "format": "K1-MAIN-COMPARISON-EVIDENCE-1", "main_revision": MAIN,
        "compiler_sha256": CANDIDATE, "legacy_sha256": LEGACY,
        "input_manifest_sha256": q["input_manifest_sha256"], "qualified_inputs": len(q["inputs"]),
        "sample_count": sum(r["samples"] for r in results.values()),
        "archive": archive.name, "archive_sha256": digest(archive),
        "archive_files": {str(p.relative_to(ROOT)): digest(p) for p in sorted(selected)},
        "files": {p.name: digest(p) for p in sorted(dest.iterdir()) if p.is_file()},
        "scope": "Fresh measurements against main 1e39b5d using its hash-matched installed release. "
                 "Five counterbalanced pairs, five loop kernels in fresh engine processes, "
                 "default and optimizing-only V8 separate, nine fresh-process compilation families. "
                 "Exact reference/checksum checks and required ownership boundaries included. "
                 "K1 --opt=off; main default pipeline, no prelude, one frontend/semantic worker. "
                 "All 209 records retained, including 19 separately instrumented phase samples. "
                 "Compile-suite runtime sweeps are correctness controls, not runtime evidence. "
                 "No compiler changes, gdev migration, retained-edit or compiler rebuild-time measurement. "
                 "CPU placement/frequency/load/cache uncontrolled; paired ranges are not confidence intervals.",
    })
    print(f"packaged {len(selected)} files and {sum(r['samples'] for r in results.values())} records")


if __name__ == "__main__":
    main()
