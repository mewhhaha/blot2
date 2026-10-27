"""Package frozen qualification and raw measurements without generated binaries.

Run after the release gate and all commands in benchmarks/README.md. The archive
retains samples, generated source inputs and raw logs; executable/artifact hashes
remain in the records. It is evidence, not a portable executable distribution.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="benchmarks/results/k1-initial")
    args = parser.parse_args()
    destination = ROOT / args.out
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit("refusing to overwrite existing published evidence")
    qualification = read(ROOT / "test-results/qualification.json")
    compiler_hash = digest(ROOT / "build/blot")
    if qualification.get("status") != "passed" or qualification.get("compiler_sha256") != compiler_hash:
        raise SystemExit("current release candidate has no passing qualification")
    if qualification.get("compiler_mode") != "--release":
        raise SystemExit("performance publication requires the release candidate")
    for path, expected in qualification["inputs"].items():
        if digest(ROOT / path) != expected:
            raise SystemExit("qualified input changed: " + path)
    for path, expected in qualification["evidence"].items():
        if digest(ROOT / "test-results" / path) != expected:
            raise SystemExit("qualification evidence changed: " + path)

    directories = {
        "paired": "bench-k1-release",
        "sessions": "bench-sessions-release",
        "limits": "bench-limits-release",
        "iteration-debug": "bench-iteration-debug",
        "iteration-release": "bench-iteration-release",
    }
    sources = {name: ROOT / "build" / path for name, path in directories.items()}
    for name, directory in sources.items():
        results = read(directory / "results.json")
        summary = read(directory / "summary.json")
        if not results["samples"] or not summary["summary"] or results.get("issues"):
            raise SystemExit("incomplete/failed measurement: " + name)
        metadata = results["metadata"]
        if name.startswith("iteration-"):
            if metadata.get("probe") or not metadata.get("toolchain_unchanged"):
                raise SystemExit("unqualified compiler iteration: " + name)
            for row in metadata["source_files"]:
                if digest(ROOT / row["path"]) != row["sha256"]:
                    raise SystemExit("iteration source differs from candidate: " + row["path"])
        elif metadata.get("candidate_sha256") != compiler_hash:
            raise SystemExit("measured binary differs from qualified candidate: " + name)
    telemetry = ROOT / "build/runtime-telemetry.json"
    if read(telemetry)["compiler_sha256"] != compiler_hash:
        raise SystemExit("telemetry binary differs from candidate")

    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "test-results/qualification.json", destination / "qualification.json")
    shutil.copy2(telemetry, destination / "runtime-telemetry.json")
    selected = set()
    for name, directory in sources.items():
        shutil.copy2(directory / "summary.json", destination / (name + ".json"))
        for path in directory.rglob("*"):
            relative = path.relative_to(directory)
            # Iteration snapshots contain repeated compiler trees and generated C;
            # the exact source/intermediate/executable hashes are already recorded.
            if name.startswith("iteration-") and any(part in {"source", "source-snapshot", "goose-home"} for part in relative.parts):
                continue
            if path.is_file() and path.suffix in {".json", ".log", ".stderr", ".stdout", ".blot"}:
                selected.add(path)
    for path in (ROOT / "test-results").rglob("*"):
        if path.is_file() and path.suffix in {".json", ".log"}:
            selected.add(path)
    selected.add(telemetry)
    archive = destination / "raw-evidence.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for path in sorted(selected):
            bundle.add(path, arcname=str(path.relative_to(ROOT)), recursive=False)
    manifest = {
        "format": "K1-QUALIFICATION-EVIDENCE-1",
        "compiler_sha256": compiler_hash,
        "input_manifest_sha256": qualification["input_manifest_sha256"],
        "archive": archive.name,
        "archive_sha256": digest(archive),
        "archive_files": {str(path.relative_to(ROOT)): digest(path) for path in sorted(selected)},
        "exclusions": "Generated C, compiler/Wasm/Core binaries, caches, node_modules; their hashes are in raw records.",
    }
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
