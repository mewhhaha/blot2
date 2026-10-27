"""Measure rebuilding the Goose Blot compiler in isolated source snapshots.

Each round measures fresh intermediates, an unchanged rebuild and a comment edit.
Debug/release samples and separate Goose/C attribution remain distinct. --probe
builds a tiny program through the same paths, never the compiler benchmark itself.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

from benchmark_limits import (ROOT, fresh_directory, machine_metadata, measure,
                              sha256, summary_rows, write_json)

PIN = "a108677d300cb0e8bbb842c35a353abe67a20c6c"


def file_manifest(directory, paths):
    return [{"path": str(path), "bytes": (directory / path).stat().st_size,
             "sha256": sha256(directory / path)} for path in paths]


def manifest_hash(manifest):
    return hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def tool_version(command):
    result = subprocess.run([str(item) for item in command], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(f"tool failed: {command}\n{result.stderr}")
    return (result.stdout + result.stderr).strip()


def resolve_tool(value):
    path = shutil.which(value)
    if path is None:
        path = str((ROOT / value).resolve())
    result = Path(path).resolve()
    if not result.is_file() or not os.access(result, os.X_OK):
        raise ValueError(f"tool is not executable: {result}")
    return result


def generated_c(home):
    found = sorted((home / "build" / "prog").glob("*/*.c"))
    if len(found) != 1:
        raise RuntimeError(f"expected one generated C translation unit in {home}: {found}")
    return found[0]


def backend_command(sample, clang, snapshot, home):
    candidates = []
    for log in [sample["stdout"], sample["stderr"]]:
        for line in Path(log).read_text(errors="replace").splitlines():
            try:
                argv = shlex.split(line)
            except ValueError:
                continue
            if argv and (argv[0] == str(clang) or argv[0] == clang.name):
                candidates.append(argv)
    if len(candidates) != 1:
        raise RuntimeError(f"expected one standalone clang command, found {len(candidates)}")
    command = candidates[0]
    if "-o" not in command:
        raise RuntimeError("clang dry-run command has no output")
    output = Path(command[command.index("-o") + 1]).resolve()
    if not output.is_relative_to(snapshot):
        raise RuntimeError(f"clang output escapes isolated snapshot: {output}")
    cfiles = [Path(arg).resolve() for arg in command[1:] if arg.endswith(".c")]
    if len(cfiles) != 1 or not cfiles[0].is_relative_to(home) or not cfiles[0].is_file():
        raise RuntimeError("clang input is not the freshly generated isolated C file")
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", default=os.environ.get("GOOSE", ".tools/goose/build/goose"))
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--stdlib")
    parser.add_argument("--modes", default="debug,release")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--out", default="build/bench-iteration")
    parser.add_argument("--build-label", required=True)
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    modes = args.modes.split(",")
    rounds = 1 if args.probe else args.rounds
    if not 1 <= rounds <= 100 or not modes or any(mode not in ["debug", "release"] for mode in modes) or len(set(modes)) != len(modes) or args.timeout <= 0:
        parser.error("invalid modes, rounds or timeout")
    goose, clang = resolve_tool(args.goose), resolve_tool(args.cc)
    goose_version, clang_version = tool_version([goose, "version"]), tool_version([clang, "--version"])
    if PIN[:7] not in goose_version:
        parser.error(f"expected pinned Goose {PIN}, found {goose_version}")
    if "clang version" not in clang_version.lower():
        parser.error("this harness requires the existing clang driver")
    if args.stdlib:
        stdlib = (ROOT / args.stdlib).resolve()
    else:
        choices = [goose.parent.parent / "stdlib", goose.parent / "stdlib"]
        stdlib = next((path for path in choices if (path / "std.goose").is_file()), None)
        if stdlib is None:
            parser.error("cannot locate pinned Goose standard library; supply --stdlib")
    if not (stdlib / "std.goose").is_file():
        parser.error(f"invalid standard library: {stdlib}")
    out = fresh_directory(ROOT / args.out)
    paths = sorted({Path("blot.goose"), Path("examples/identity.blot"),
                    *(path.relative_to(ROOT) for path in (ROOT / "src").rglob("*.goose")),
                    *(path.relative_to(ROOT) for path in (ROOT / "src").rglob("*.h"))}, key=str)
    initial = file_manifest(ROOT, paths)
    base = out / "source-snapshot"
    for path in paths:
        target = base / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, target)
    captured = file_manifest(base, paths)
    if captured != initial or file_manifest(ROOT, paths) != initial:
        raise RuntimeError("compiler source changed while snapshotting; retry after source freeze")
    if args.probe:
        (base / "blot.goose").write_text('import std;\nfn main() { print("iteration harness probe"); }\n')
        captured = file_manifest(base, paths)
    stdlib_paths = sorted((path.relative_to(stdlib) for path in stdlib.rglob("*.goose")), key=str)
    stdlib_manifest = file_manifest(stdlib, stdlib_paths)
    metadata = {**machine_metadata(), "format": "K1-COMPILER-ITERATION-1", "probe": args.probe,
                "build_label": args.build_label, "rounds": rounds, "modes": modes,
                "harness_sha256": sha256(__file__), "measurement_helper_sha256": sha256(ROOT / "scripts/benchmark_limits.py"),
                "compiler_source_sha256": manifest_hash(initial),
                "goose_pin": PIN, "goose_path": str(goose), "goose_version": goose_version,
                "goose_sha256": sha256(goose), "clang_path": str(clang), "clang_version": clang_version,
                "clang_sha256": sha256(clang), "stdlib": str(stdlib),
                "stdlib_sha256": manifest_hash(stdlib_manifest), "source_sha256": manifest_hash(captured),
                "source_files": captured, "fresh_scope": "empty isolated GOOSE_HOME and absent compiler executable",
                "edit": "append a comment to src/frontend.goose (blot.goose in probe mode), without changing semantics",
                "flags": "--standalone --offline --cc <existing clang>; --debug only for debug configuration",
                "attribution": "separate --dry-run frontend/typecheck/C-generation sample and exact printed clang argv replay; do not subtract unrelated whole-build samples",
                "interpretation": "repeated invokes the same Goose build command with existing intermediates; it does not assume incremental compilation"}
    write_json(out / "stdlib-files.json", stdlib_manifest)
    samples, issues = [], []

    def save():
        write_json(out / "results.json", {"metadata": metadata, "samples": samples, "issues": issues})
        write_json(out / "summary.json", {"metadata": metadata, "summary": summary_rows(samples, ["mode", "case"]), "issues": issues})

    for mode in modes:
        for round_id in range(rounds):
            directory = out / f"{mode}-round-{round_id}"
            directory.mkdir()
            snapshot, home = directory / "source", directory / "goose-home"
            shutil.copytree(base, snapshot)
            home.mkdir()
            env = {**os.environ, "GOOSE_HOME": str(home), "GOOSE_STDLIB": str(stdlib), "GOOSE_PROGRESS": "plain", "NO_COLOR": "1"}
            executable = snapshot / "build" / "blot"
            command = [goose, "build", "blot.goose", "-o", executable, "--cc", clang,
                       "--standalone", "--offline", "--stdlib", stdlib, "--include", snapshot / "src" / "platform.h", "-q"]
            if mode == "debug":
                command.append("--debug")
            previous_c_hash = None

            def run(case, argv):
                nonlocal previous_c_hash
                source_hash = manifest_hash(file_manifest(snapshot, paths))
                sample = measure(argv, snapshot, directory, case, args.timeout, env)
                sample.update({"mode": mode, "round": round_id, "case": case, "source_sha256": source_hash,
                               "goose_home": str(home), "snapshot": str(snapshot)})
                if sample["exit_code"] == 0:
                    cfile = generated_c(home)
                    sample.update({"generated_c_bytes": cfile.stat().st_size, "generated_c_sha256": sha256(cfile)})
                    sample["generated_c_same_as_previous"] = previous_c_hash == sample["generated_c_sha256"] if previous_c_hash else None
                    previous_c_hash = sample["generated_c_sha256"]
                    if executable.exists():
                        sample.update({"compiler_bytes": executable.stat().st_size, "compiler_sha256": sha256(executable)})
                    if case != "attribution-goose-frontend":
                        if not executable.exists():
                            issues.append({"mode": mode, "round": round_id, "case": case, "reason": "no built executable"})
                        else:
                            verify = subprocess.run([str(executable), "--version"], cwd=snapshot, env=env, capture_output=True, text=True, timeout=30)
                            sample["verification_output"] = verify.stdout.strip()
                            expected = "iteration harness probe" if args.probe else "blot k1-dev"
                            if verify.returncode != 0 or expected not in verify.stdout:
                                issues.append({"mode": mode, "round": round_id, "case": case, "reason": "built compiler smoke check failed"})
                else:
                    issues.append({"mode": mode, "round": round_id, "case": case, "reason": "build failed or timed out"})
                samples.append(sample)
                save()
                return sample

            fresh = run("fresh", command)
            if fresh["exit_code"] != 0:
                continue
            repeated = run("unchanged", command)
            if repeated["exit_code"] != 0:
                continue
            edited = snapshot / ("blot.goose" if args.probe else "src/frontend.goose")
            with edited.open("a") as file:
                file.write(f"\n// ordinary compiler iteration benchmark comment {round_id}\n")
            changed = run("comment-edit", command)
            if changed["exit_code"] != 0:
                continue
            if round_id == 0:
                frontend = run("attribution-goose-frontend", [*command, "--dry-run", "-v"])
                if frontend["exit_code"] == 0:
                    try:
                        backend = backend_command(frontend, clang, snapshot, home)
                    except RuntimeError as error:
                        issues.append({"mode": mode, "case": "attribution-c-backend", "reason": str(error)})
                    else:
                        run("attribution-c-backend", backend)
            save()
            print(f"measured mode={mode} round={round_id}", flush=True)
    metadata["toolchain_unchanged"] = (sha256(goose) == metadata["goose_sha256"] and sha256(clang) == metadata["clang_sha256"]
                                       and manifest_hash(file_manifest(stdlib, stdlib_paths)) == metadata["stdlib_sha256"])
    if not metadata["toolchain_unchanged"]:
        issues.append({"reason": "toolchain changed during measurement"})
    save()
    print(out / "summary.json")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
