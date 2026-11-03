#!/usr/bin/env python3
"""Paired uncached builds and checked warmed kernels against Goose direct Wasm.

Uses the sibling repository's pinned LangArena catalog/inputs and original direct
sources. Unsupported/unported cells remain visible. Kernels run in the same
Node/V8, with upstream preparation and stateful warmup outside the guest clocks.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import platform
import random
import shutil
import signal
import statistics
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

from reference import PROFILES, checksum

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CASES = {
    "fannkuch": ("CLBG::Fannkuchredux", "fannkuch.goose", "fannkuch.blot"),
    "crc32": ("Hash::CRC32", "hash_crc32.goose", "crc32.blot"),
    "custom_hash": ("Hash::SHA256", "hash_sha256.goose", "custom_hash.blot"),
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fingerprint_tree(directory):
    return {
        str(p.relative_to(directory)): sha(p)
        for p in sorted(Path(directory).rglob("*"))
        if p.is_file()
    }


def summary(values):
    if not values:
        return None
    values = sorted(values)
    median = statistics.median(values)

    def percentile(fraction):
        position = (len(values) - 1) * fraction
        left = int(position)
        right = min(left + 1, len(values) - 1)
        return values[left] + (values[right] - values[left]) * (position - left)

    return {
        "n": len(values),
        "median": median,
        "mad": statistics.median(abs(v - median) for v in values),
        "min": values[0],
        "max": values[-1],
        "p25": percentile(0.25),
        "p75": percentile(0.75),
        "samples": values,
    }


def write_results(output, report):
    """Keep portable evidence without embedding large allocation profiles/logs."""
    compact = {
        k: v
        for k, v in report.items()
        if k not in ["build_observations", "runtime_observations", "qualifications"]
    }
    compact["raw_report_sha256"] = sha(output / "report.json")
    compact["build_observations"] = []
    for row in report["build_observations"]:
        item = {
            k: v
            for k, v in row.items()
            if k not in ["stdout", "stderr", "driver_stats"]
        }
        stats = row.get("driver_stats", {})
        if row["backend"] == "blot":
            item["driver_stats"] = {k: v for k, v in stats.items() if k != "stats"}
            item["phase_profile"] = dict(stats.get("stats", {}).get("phaseProfile", {}))
            # Only phase timings; large normalization counters remain in raw data.
            item["phase_profile"].pop("checking", None)
        else:
            item["driver_stats"] = {
                k: v for k, v in stats.items() if k != "backend_stats"
            }
            item["backend_stats"] = {
                k: v
                for k, v in stats.get("backend_stats", {}).items()
                if k != "function_info"
            }
        compact["build_observations"].append(item)
    for field in ["runtime_observations", "qualifications"]:
        compact[field] = [
            {k: v for k, v in row.items() if k not in ["stdout", "stderr"]}
            for row in report[field]
        ]
    (output / "summary.json").write_text(json.dumps(compact, indent=2) + "\n")
    profile_mode = report["configuration"]["profile_backend"]
    lines = [
        "# Blot / Goose direct Wasm",
        "",
        f"Status: {report['status']}. Node {report['environment']['node']['node']}; V8 {report['environment']['node']['v8']}. Blot compiler profiling: {profile_mode}.",
        "",
        "Cold builds are fresh uncached driver processes; medians include startup. Runtime rows use identical parameters and checked checksums, with preparation and warmup outside the kernel clock.",
        "",
        "| Case | Build Blot / Goose (ms) | Wasm Blot / Goose (B) |",
        "| --- | ---: | ---: |",
    ]

    def find(rows, **fields):
        return next(r for r in rows if all(r.get(k) == v for k, v in fields.items()))

    for short in report["cases"]:
        blot = find(report["build_summary"], case=short, backend="blot", phase="cold")
        goose = find(report["build_summary"], case=short, backend="goose", phase="cold")
        if blot["wall_ms"] and goose["wall_ms"]:
            lines.append(
                f"| {short} | {blot['wall_ms']['median']:.2f} / {goose['wall_ms']['median']:.2f} | {blot['wasm_bytes']} / {goose['wasm_bytes']} |"
            )
    lines += [
        "",
        "| Profile / case | Kernel Blot / Goose (ms) | Paired Blot / Goose |",
        "| --- | ---: | ---: |",
    ]
    for row in report["paired_runtime"]:
        display = []
        for backend in ["blot", "goose"]:
            cell = find(
                report["runtime_summary"],
                case=row["case"],
                backend=backend,
                profile=row["profile"],
            )
            value = "unavailable"
            if cell["kernel_ms"]:
                value = f"{cell['kernel_ms']['median']:.3f}"
            display.append(value)
        ratio = row["reason"]
        if row["ratio"]:
            ratio = f"{row['ratio']['median']:.2f}x ({row['ratio']['n']} pairs)"
        lines.append(
            f"| {row['profile']} / {row['case']} | {' / '.join(display)} | {ratio} |"
        )
    lines += [
        "",
        "Bounded uses production problem sizes with explicitly reduced repetition counts. It is not an official LangArena production score. Blot hash inputs have 4x Goose's element payload bytes (U32 vs U8); owner and arena overhead are separate. Results compare the complete translated programs and their ABI costs. Three of seven adapted tasks are ported; the 50-task catalog is not covered. Process wall includes the common TypeScript runner for both backends. V8 only; no Wasmtime result.",
        "",
        "Failures:",
    ]
    lines += [f"- {r}" for r in report["failures"]]
    if not report["failures"]:
        lines.append("- None.")
    lines += ["", "Warnings:"] + [f"- {w}" for w in report["warnings"]]
    (output / "report.md").write_text("\n".join(lines) + "\n")


def execute(command, directory, timeout):
    directory.mkdir(parents=True, exist_ok=True)
    command = list(map(str, command))
    (directory / "command.json").write_text(json.dumps(command, indent=2) + "\n")
    start = time.perf_counter_ns()
    process = subprocess.Popen(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    status = "passed"
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        status = "timeout"
        if isinstance(sys.exc_info()[1], KeyboardInterrupt):
            raise
    elapsed_ms = (time.perf_counter_ns() - start) / 1e6
    (directory / "stdout").write_bytes(stdout)
    (directory / "stderr").write_bytes(stderr)
    if status == "passed" and process.returncode:
        status = "failed"
    return {
        "status": status,
        "returncode": process.returncode,
        "wall_ms": elapsed_ms,
        "stdout": stdout.decode(errors="replace"),
        "stderr": stderr.decode(errors="replace"),
        "logs": str(directory),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--goose-root", type=Path, default=ROOT.parent / "goose-to-wasm"
    )
    parser.add_argument("--goose", type=Path)
    parser.add_argument(
        "--blotc", type=Path, default=ROOT / "zig-native/zig-out/bin/blotc"
    )
    parser.add_argument("--node", type=Path, default=Path("node"))
    parser.add_argument("--deno", default="deno")
    parser.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES))
    parser.add_argument(
        "--profiles",
        nargs="+",
        choices=["test", "bounded", "run"],
        default=["test", "bounded"],
    )
    parser.add_argument("--compile-samples", type=int, default=5)
    parser.add_argument(
        "--profile-backend",
        action="store_true",
        help="instrument Blot compiler; diagnostic compile timings only",
    )
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument(
        "--warmups",
        type=int,
        default=1,
        help="whole-process warmups; kernel warmups remain official",
    )
    parser.add_argument("--timeout-seconds", type=float, default=30)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if (
        args.compile_samples < 1
        or args.samples < 1
        or args.warmups < 0
        or not 0 < args.timeout_seconds <= 30
    ):
        parser.error("invalid sample count or timeout; each child is capped at 30s")
    goose_root = args.goose_root.resolve()
    goose = (args.goose or goose_root / "build/bin/goose").resolve()
    blot = args.blotc.resolve()
    node_path = shutil.which(str(args.node))
    if node_path is None:
        parser.error("Node executable not found; supply --node PATH")
    node = Path(node_path).resolve()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output must be new or empty")
    output.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location(
        "goose_arena_reference", goose_root / "bench/langarena.py"
    )
    arena = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(arena)
    manifest = arena.load_manifest()
    catalog = {c["name"]: c for c in manifest["cases"]}
    frozen = output / "frozen"
    for backend, executable in [("goose", goose), ("blot", blot)]:
        destination = frozen / backend / "bin" / executable.name
        destination.parent.mkdir(parents=True)
        shutil.copy2(executable, destination)
        if sha(executable) != sha(destination):
            raise RuntimeError("compiler changed while freezing")
    goose_copy = frozen / "goose/bin" / goose.name
    blot_copy = frozen / "blot/bin" / blot.name
    shutil.copytree(goose.parent / "stdlib", goose_copy.parent / "stdlib")
    shutil.copy2(
        blot.parent.parent / "compiler-identity.bin",
        blot_copy.parent.parent / "compiler-identity.bin",
    )
    goose_runner = frozen / "run_wasm.mjs"
    shutil.copy2(goose_root / "scripts/run_wasm.mjs", goose_runner)
    version = subprocess.check_output(
        [node, "-p", "JSON.stringify(process.versions)"], text=True
    ).strip()
    cases = {}
    for short in args.cases:
        task, goose_name, blot_name = CASES[short]
        catalog_case = dict(catalog[task])
        bounded = next(r for r in PROFILES["bounded"] if r[0] == short)
        _, parameter, iterations, warmups, _ = bounded
        catalog_case["bounded"] = {
            catalog_case["port"]["fields"][0]: parameter,
            "iterations": iterations,
            "warmup_iterations": warmups,
            "checksum": checksum(short, parameter, iterations, warmups),
        }
        for profile in ["test", "run", "bounded"]:
            config = catalog_case[profile]
            assert (
                checksum(
                    short,
                    config[catalog_case["port"]["fields"][0]],
                    config["iterations"],
                    arena.warmup_count(config),
                )
                == config["checksum"]
            ), "independent oracle mismatch"
        row = {"task": task, "catalog": catalog_case, "sources": {}}
        for backend in ["goose", "blot"]:
            folder = output / "sources" / short / backend
            folder.mkdir(parents=True)
            if backend == "goose":
                file = folder / goose_name
                shutil.copy2(goose_root / "bench/langarena/ports" / goose_name, file)
                shutil.copy2(
                    goose_root / "bench/langarena/ports/common.goose",
                    folder / "common.goose",
                )
            else:
                file = folder / blot_name
                shutil.copy2(HERE / "ports" / blot_name, file)
            row["sources"][backend] = str(file)
        cases[short] = row
    tracked = [
        Path(__file__),
        HERE / "reference.py",
        HERE / "runtime.ts",
        HERE / "build_blot.ts",
        goose_root / "scripts/goose_wasm.py",
        goose_root / "oracle/goose_wasm.py",
        goose_root / "bench/langarena.py",
        goose_root / "bench/langarena/manifest.json",
        goose_root / "bench/langarena/test.json",
        goose_root / "bench/langarena/run.json",
        goose_root / "bench/langarena/ports/common.goose",
    ]
    tracked += list((HERE / "ports").glob("*.blot"))
    tracked += list((ROOT / "compiler").glob("*.ts"))
    tracked += list((ROOT / "std").rglob("*.blot"))
    report = {
        "schema": "blot-goose-comparison-v1",
        "status": "incomplete",
        "started_utc": datetime.now(UTC).isoformat(),
        "configuration": {
            "compile_samples": args.compile_samples,
            "profile_backend": args.profile_backend,
            "runtime_samples": args.samples,
            "process_warmups": args.warmups,
            "profiles": args.profiles,
            "timeout_seconds": args.timeout_seconds,
            "seed": 771923,
            "node_flags": ["--experimental-transform-types"],
        },
        "environment": {
            "platform": platform.platform(),
            "cpu": next(
                (
                    l.split(":", 1)[1].strip()
                    for l in Path("/proc/cpuinfo").read_text().splitlines()
                    if l.startswith("model name")
                ),
                "unknown",
            ),
            "affinity": sorted(os.sched_getaffinity(0)),
            "node": json.loads(version),
            "node_path": str(node),
            "python": sys.version,
            "deno": subprocess.check_output([args.deno, "--version"], text=True),
            "goose_checkout_head": subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=goose_root, text=True
            ).strip(),
            "goose_checkout_status": subprocess.check_output(
                ["git", "status", "--short"], cwd=goose_root, text=True
            ).splitlines(),
            "compiler_sha256": {"blot": sha(blot_copy), "goose": sha(goose_copy)},
            "goose_stdlib": fingerprint_tree(goose_copy.parent / "stdlib"),
            "goose_toolchain": json.loads((goose_root / "toolchain.json").read_text()),
            "input_sha256": {str(f): sha(f) for f in tracked},
        },
        "coverage": {
            "reference_catalog_tasks": 50,
            "reference_adapted_tasks": 7,
            "selected_ports": len(cases),
            "unported": [
                c["name"]
                for c in manifest["cases"]
                if c["port"] and c["name"] not in [v[0] for v in CASES.values()]
            ],
            "not_selected": [s for s in CASES if s not in args.cases],
            "engines": ["V8"],
            "note": "Shared translated algorithms, not identical source or a full-language/50-task claim.",
        },
        "method": {
            "cold_build": "Fresh driver and compiler per sample; cache disabled. OS and installed-library caches retained. Source staging outside timer. Complete wall and native build phases retained.",
            "runtime": "Same Node/V8 and flags for both. test/run use official inputs/iterations/warmups. bounded retains production problem sizes with reduced counts recorded per case. Same state retained after warmup. Preparation, startup, engine compilation and output outside clock; no per-element host calls. Two Blot clock packet crossings versus two Goose scalar imports are part of their ABI costs. Common process wall includes parsing the Blot TypeScript guest host for both backends; it is not Goose's standalone runner startup score.",
            "representation": "Goose hash data is U8; Blot stores identical 0..255 values in U32, 4x element payload bytes; owner and arena overhead are separate. Fixed 1m-element capacity retained. Fannkuch indices/permutations are nonnegative; U32 checksum wrap preserves final U32 accumulation. Wider parameter/clock plumbing stays outside kernels. Custom Hash::SHA256 is the original eight-lane custom hash, not cryptographic SHA-256.",
            "ordering": "Build phase sequential, then runtime phase; seeded paired shuffling, no deliberate concurrent measurement work.",
        },
        "cases": cases,
        "build_observations": [],
        "qualifications": [],
        "runtime_observations": [],
        "build_summary": [],
        "runtime_summary": [],
        "paired_runtime": [],
        "failures": [],
        "warnings": [],
    }
    report["environment"]["staged_sources_sha256"] = fingerprint_tree(
        output / "sources"
    )
    report["environment"]["blot_checkout_head"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    report["environment"]["blot_compiler_identity_sha256"] = sha(
        blot_copy.parent.parent / "compiler-identity.bin"
    )
    report["environment"]["goose_runner_sha256"] = sha(goose_runner)

    def checkpoint():
        temp = output / "report.json.tmp"
        temp.write_text(json.dumps(report, indent=2) + "\n")
        temp.replace(output / "report.json")

    def runtime(short, backend, artifact, profile, revision, directory):
        case = cases[short]["catalog"]
        config = case[profile]
        data = {
            "parameters": [config[f] for f in case["port"]["fields"]],
            "iterations": config["iterations"],
            "warmups": arena.warmup_count(config),
            "expected": config["checksum"],
            "revision": revision,
        }
        command = [
            node,
            "--experimental-transform-types",
            HERE / "runtime.ts",
            backend,
            artifact,
            json.dumps(data, separators=(",", ":")),
        ]
        if backend == "goose":
            command += ["--goose-runner", goose_runner]
        row = execute(command, directory, args.timeout_seconds)
        if row["status"] == "passed":
            try:
                timing = json.loads(row["stdout"])
                for field in ["elapsed_ns", "compile_instantiate_ns", "entry_ns"]:
                    assert type(timing[field]) is int and timing[field] > 0, field
                assert (
                    timing["engine"] == "V8"
                    and timing["node"] == "v" + report["environment"]["node"]["node"]
                    and timing["v8"] == report["environment"]["node"]["v8"]
                ), "engine version mismatch"
                row["timing"] = timing
            except (ValueError, KeyError, AssertionError) as error:
                row["status"] = "failed"
                row["validation_error"] = str(error)
        return row

    artifacts = {}
    rng = random.Random(771923)
    checkpoint()
    try:
        for phase in ["cold", "marker_edit"]:
            failed_builds = set()
            jobs = [
                (i, c, b)
                for i in range(args.compile_samples)
                for c in cases
                for b in ["blot", "goose"]
            ]
            rng.shuffle(jobs)
            for sample, short, backend in jobs:
                if (short, backend) in failed_builds:
                    continue
                source = Path(cases[short]["sources"][backend])
                original = source.read_bytes()
                marker = b"const arena_revision = 0"
                replacement = b"const arena_revision = 1"
                if backend == "goose":
                    marker = b"let ARENA_REVISION = 0;"
                    replacement = b"let ARENA_REVISION = 1;"
                directory = output / "builds" / phase / short / backend / str(sample)
                directory.mkdir(parents=True)
                artifact = directory / "program.wasm"
                stats = directory / "stats.json"
                if backend == "blot":
                    command = [
                        args.deno,
                        "run",
                        "--no-config",
                        "--no-lock",
                        "-A",
                        HERE / "build_blot.ts",
                        blot_copy,
                        source,
                        artifact,
                        stats,
                    ]
                    if args.profile_backend:
                        command.append("--profile-backend")
                else:
                    command = [
                        sys.executable,
                        goose_root / "scripts/goose_wasm.py",
                        "build",
                        source,
                        "-o",
                        artifact,
                        "--backend",
                        "direct",
                        "-O2",
                        "--no-cache",
                        "--offline",
                        "--goose",
                        goose_copy,
                        "--stats",
                        stats,
                    ]
                try:
                    if phase == "marker_edit":
                        if original.count(marker) != 1:
                            raise ValueError("missing unique revision marker")
                        source.write_bytes(original.replace(marker, replacement))
                    result = execute(command, directory, args.timeout_seconds)
                    row = {
                        "phase": phase,
                        "sample": sample,
                        "case": short,
                        "backend": backend,
                        "source_sha256": sha(source),
                        **result,
                    }
                    if result["status"] == "passed":
                        row.update(
                            artifact=str(artifact),
                            wasm_bytes=artifact.stat().st_size,
                            wasm_sha256=sha(artifact),
                            driver_stats=json.loads(stats.read_text()),
                        )
                        artifacts[short, backend, phase] = artifact
                    else:
                        failed_builds.add((short, backend))
                        report["failures"].append(
                            {
                                "phase": phase,
                                "case": short,
                                "backend": backend,
                                "status": result["status"],
                                "logs": str(directory),
                            }
                        )
                    report["build_observations"].append(row)
                    checkpoint()
                    print(
                        "BUILD",
                        phase,
                        short,
                        backend,
                        sample,
                        result["status"],
                        flush=True,
                    )
                finally:
                    source.write_bytes(original)
        qualified = set()
        for short in cases:
            for backend in ["blot", "goose"]:
                if any(
                    (short, backend, phase) not in artifacts
                    for phase in ["cold", "marker_edit"]
                ):
                    continue
                passed = True
                for phase, revision in [("cold", 0), ("marker_edit", 1)]:
                    key = (short, backend, phase)
                    if key not in artifacts:
                        passed = False
                        continue
                    if phase == "marker_edit" and sha(artifacts[key]) == sha(
                        artifacts[short, backend, "cold"]
                    ):
                        raise ValueError("marker edit did not change artifact")
                    row = {
                        "case": short,
                        "backend": backend,
                        "phase": phase,
                        **runtime(
                            short,
                            backend,
                            artifacts[key],
                            "test",
                            revision,
                            output / "qualification" / short / backend / phase,
                        ),
                    }
                    report["qualifications"].append(row)
                    if row["status"] != "passed":
                        passed = False
                        report["failures"].append(
                            {
                                "phase": "qualification",
                                "case": short,
                                "backend": backend,
                                "logs": row["logs"],
                            }
                        )
                    checkpoint()
                if passed:
                    qualified.add((short, backend))
        disabled = set()
        for profile in args.profiles:
            for sample in range(-args.warmups, args.samples):
                order = list(cases)
                rng.shuffle(order)
                for short in order:
                    backends = ["blot", "goose"]
                    rng.shuffle(backends)
                    for backend in backends:
                        cell = (short, backend, profile)
                        if (short, backend) not in qualified or cell in disabled:
                            continue
                        row = {
                            "case": short,
                            "backend": backend,
                            "profile": profile,
                            "sample": sample,
                            **runtime(
                                short,
                                backend,
                                artifacts[short, backend, "cold"],
                                profile,
                                0,
                                output
                                / "runtime"
                                / profile
                                / short
                                / backend
                                / str(sample),
                            ),
                        }
                        report["runtime_observations"].append(row)
                        if row["status"] != "passed":
                            disabled.add(cell)
                            report["failures"].append(
                                {
                                    "phase": "runtime",
                                    "case": short,
                                    "backend": backend,
                                    "profile": profile,
                                    "status": row["status"],
                                    "logs": row["logs"],
                                }
                            )
                        checkpoint()
                        print(
                            "RUN",
                            profile,
                            short,
                            backend,
                            sample,
                            row["status"],
                            flush=True,
                        )
        for short in cases:
            for backend in ["blot", "goose"]:
                for phase in ["cold", "marker_edit"]:
                    rows = [
                        r
                        for r in report["build_observations"]
                        if (r["case"], r["backend"], r["phase"])
                        == (short, backend, phase)
                        and r["status"] == "passed"
                    ]
                    report["build_summary"].append(
                        {
                            "case": short,
                            "backend": backend,
                            "phase": phase,
                            "wall_ms": summary([r["wall_ms"] for r in rows]),
                            "wasm_bytes": next((r["wasm_bytes"] for r in rows), None),
                        }
                    )
                for profile in args.profiles:
                    rows = [
                        r
                        for r in report["runtime_observations"]
                        if (r["case"], r["backend"], r["profile"])
                        == (short, backend, profile)
                        and r["status"] == "passed"
                        and r["sample"] >= 0
                    ]
                    report["runtime_summary"].append(
                        {
                            "case": short,
                            "backend": backend,
                            "profile": profile,
                            "kernel_ms": summary(
                                [r["timing"]["elapsed_ns"] / 1e6 for r in rows]
                            ),
                            "process_ms": summary([r["wall_ms"] for r in rows]),
                            "compile_instantiate_ms": summary(
                                [
                                    r["timing"]["compile_instantiate_ns"] / 1e6
                                    for r in rows
                                ]
                            ),
                            "entry_ms": summary(
                                [r["timing"]["entry_ns"] / 1e6 for r in rows]
                            ),
                        }
                    )
        for profile in args.profiles:
            for short in cases:
                pairs = {}
                for r in report["runtime_observations"]:
                    if (
                        r["case"] == short
                        and r["profile"] == profile
                        and r["sample"] >= 0
                        and r["status"] == "passed"
                    ):
                        pairs.setdefault(r["sample"], {})[r["backend"]] = r["timing"][
                            "elapsed_ns"
                        ]
                complete = [p for p in pairs.values() if len(p) == 2]
                ratio = None
                reason = "fewer than five valid pairs"
                failed = any(
                    r["case"] == short
                    and r["profile"] == profile
                    and r["status"] != "passed"
                    for r in report["runtime_observations"]
                )
                if failed:
                    reason = "failed cell; no ranking"
                if len(complete) >= 5 and not failed:
                    reason = "kernel below 10ms"
                    if all(
                        statistics.median(p[b] for p in complete) >= 10_000_000
                        for b in ["blot", "goose"]
                    ):
                        ratio = summary([p["blot"] / p["goose"] for p in complete])
                        reason = ""
                report["paired_runtime"].append(
                    {
                        "case": short,
                        "profile": profile,
                        "ratio": ratio,
                        "reason": reason,
                    }
                )
        if args.samples < 5:
            report["warnings"].append(
                "Fewer than five runtime samples: correctness smoke only, not performance ranking."
            )
        if args.compile_samples < 5:
            report["warnings"].append(
                "Fewer than five build samples: compile timings are a pilot only."
            )
        for row in report["runtime_summary"]:
            if row["kernel_ms"] and row["kernel_ms"]["median"] < 10:
                report["warnings"].append(
                    f"{row['case']}/{row['backend']}/{row['profile']}: kernel below 10ms; cannot rank performance."
                )
        if any(sha(f) != h for f, h in report["environment"]["input_sha256"].items()):
            raise RuntimeError(
                "harness,host,std or reference inputs changed during run"
            )
        if (
            sha(blot_copy) != report["environment"]["compiler_sha256"]["blot"]
            or sha(goose_copy) != report["environment"]["compiler_sha256"]["goose"]
        ):
            raise RuntimeError("frozen compiler changed")
        if (
            fingerprint_tree(output / "sources")
            != report["environment"]["staged_sources_sha256"]
        ):
            raise RuntimeError("staged source changed")
        if (
            fingerprint_tree(goose_copy.parent / "stdlib")
            != report["environment"]["goose_stdlib"]
        ):
            raise RuntimeError("frozen Goose stdlib changed")
        if sha(goose_runner) != report["environment"]["goose_runner_sha256"]:
            raise RuntimeError("frozen Goose runner changed")
        if (
            sha(blot_copy.parent.parent / "compiler-identity.bin")
            != report["environment"]["blot_compiler_identity_sha256"]
        ):
            raise RuntimeError("frozen Blot identity changed")
        report["status"] = "passed"
        if report["failures"]:
            report["status"] = "partial"
        report["finished_utc"] = datetime.now(UTC).isoformat()
        checkpoint()
        write_results(output, report)
    except BaseException as error:
        report["status"] = "interrupted"
        report["error"] = repr(error)
        checkpoint()
        raise
    print(output / "report.json", flush=True)
    if report["failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
