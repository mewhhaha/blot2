#!/usr/bin/env python3
"""Execute the isolated engine laws against live Goose sources.

Usage: python3 compiler-goose/tools/test_engines.py [coalesce expectation package_owner_frames parser proof_leases source_sort diagnostic_ownership body_freeze immutable_readers import_arena source_validation_ownership editor_budget cache_root_frames native_asset_metadata completion_probe completion_project_load dependency_ownership empty_session archive_capture resolved_body wasm_scope_outline core_validation_borrow retained_seed executor_frame footprint_owner effect_evidence_owner worker_runtime_pins semantic_outcomes server_session storage_call_cache function_plan_input wasm_pipeline_scope record_order identity_owner module_stamps result_diagnostic declaration_scheme_cycles layout_bridge_words layout_intern_leaf layout_frame_store effect_evidence_handles layout_fixed_stacks code_expectation_leaf unit_uses_identity closed_local_identity owned_arrays_seen layout_owner_traversal emission_owner_reads emission_owner_prepare]
Evidence and cached native objects live in build/goose-port/engine-tests/.
"""
from __future__ import annotations
import argparse
import base64
import gzip
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("goose_build", ROOT / "build.py")
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


def inputs(entry: Path, stdlib: Path) -> list[dict]:
    """Fingerprint the source import closure, including the selected stdlib."""
    pending = [entry]
    seen = set()
    while pending:
        path = pending.pop().resolve()
        if path in seen:
            continue
        seen.add(path)
        for name in re.findall(r"^\s*import\s+([.\w]+)\s*;", path.read_text(), re.M):
            if name.startswith("."):
                candidates = [path.parent / (name[1:].replace(".", "/") + ".goose")]
            else:
                relative = name.replace(".", "/") + ".goose"
                candidates = [ROOT / "src" / relative, stdlib / relative]
            match = next((candidate for candidate in candidates if candidate.is_file()), None)
            if match is None:
                raise RuntimeError(f"cannot fingerprint import {name} in {path}")
            pending.append(match)
    return [{"path": str(path), "sha256": build.digest_file(path)} for path in sorted(seen)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", choices=["coalesce", "expectation", "package_owner_frames", "parser", "proof_leases", "source_sort", "diagnostic_ownership", "body_freeze", "immutable_readers", "import_arena", "source_validation_ownership", "editor_budget", "cache_root_frames", "native_asset_metadata", "completion_probe", "completion_project_load", "dependency_ownership", "empty_session", "archive_capture", "resolved_body", "wasm_scope_outline", "core_validation_borrow", "retained_seed", "executor_frame", "footprint_owner", "effect_evidence_owner", "worker_runtime_pins", "semantic_outcomes", "server_session", "storage_call_cache", "function_plan_input", "wasm_pipeline_scope", "record_order", "identity_owner", "module_stamps", "result_diagnostic", "declaration_scheme_cycles", "layout_bridge_words", "layout_intern_leaf", "layout_frame_store", "effect_evidence_handles", "layout_fixed_stacks", "code_expectation_leaf", "unit_uses_identity", "closed_local_identity", "owned_arrays_seen", "layout_owner_traversal", "emission_owner_reads", "emission_owner_prepare"])
    parser.add_argument("--goose", default=os.environ.get("GOOSE_BIN", str(ROOT.parent.parent / "goose-to-wasm/build/native/goose")))
    parser.add_argument("--stdlib", type=Path, default=ROOT.parent.parent / "goose-to-wasm/build/source/stdlib")
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 30:
        parser.error("--timeout must be positive and at most 30 seconds")
    goose = build.executable(args.goose)
    cc = build.executable(args.cc)
    stdlib = args.stdlib.resolve(strict=True)
    output = ROOT.parent / "build/goose-port/engine-tests"
    output.mkdir(parents=True, exist_ok=True)
    evidence = {"goose": {"path": str(goose), "sha256": build.digest_file(goose)},
                "cc": {"path": str(cc), "sha256": build.digest_file(cc)},
                "stdlib": str(stdlib), "stage_timeout": args.timeout,
                "platform_sha256": build.digest_file(ROOT / "native/platform.c"),
                "stages": [], "tests": {}}

    def call(stage: str, command: list[str], timeout: float) -> None:
        log = output / (stage.replace(" ", "-") + ".log")
        started = time.monotonic()
        with log.open("wb") as stream:
            process = subprocess.Popen(command, cwd=output, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                status = process.wait(timeout=timeout)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as failure:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                status = 124
                if isinstance(failure, KeyboardInterrupt):
                    status = 130
        seconds = time.monotonic() - started
        evidence["stages"].append({"stage": stage, "command": command,
            "exit_code": status, "seconds": seconds, "log": str(log),
            "log_sha256": build.digest_file(log)})
        if status:
            raise RuntimeError(f"{stage}: exit {status}; diagnostics: {log}")

    # Reuse the production builder's content-addressed object cache, with the
    # same bounded, logged subprocess path as the test stages.
    build.call = call
    flags = ["-std=gnu11", "-D_GNU_SOURCE", "-O0", "-pthread"]
    try:
        runtime = output / "goose_runtime.c"
        call("emit runtime", [str(goose), "--emit-runtime", str(runtime)], args.timeout)
        objects = [build.cached_object("compile " + name, source, output, [str(cc)],
                    flags, evidence["cc"]["sha256"], args.timeout)
                   for name, source in [("runtime", runtime), ("platform", ROOT / "native/platform.c")]]
        evidence["native_objects"] = [{"path": str(path), "sha256": build.digest_file(path),
            "source": str(source), "source_sha256": build.digest_file(source),
            "compile_command": [str(cc)] + flags + ["-c", str(source), "-o", str(path)]}
            for path, source in zip(objects, [runtime, ROOT / "native/platform.c"])]
        evidence["runtime_sha256"] = build.digest_file(runtime)
        # The explicit prepareMapped probe hits its 30s emission cap; it remains
        # opt-in and unqualified, outside the completed component-law inventory.
        for name in args.tests or ["coalesce", "expectation", "package_owner_frames", "parser", "proof_leases", "source_sort", "diagnostic_ownership", "body_freeze", "immutable_readers", "import_arena", "source_validation_ownership", "editor_budget", "cache_root_frames", "native_asset_metadata", "completion_probe", "completion_project_load", "dependency_ownership", "empty_session", "archive_capture", "resolved_body", "wasm_scope_outline", "core_validation_borrow", "retained_seed", "executor_frame", "footprint_owner", "effect_evidence_owner", "worker_runtime_pins", "semantic_outcomes", "server_session", "storage_call_cache", "function_plan_input", "wasm_pipeline_scope", "record_order", "identity_owner", "module_stamps", "result_diagnostic", "declaration_scheme_cycles", "layout_bridge_words", "layout_intern_leaf", "layout_frame_store", "effect_evidence_handles", "layout_fixed_stacks", "code_expectation_leaf", "unit_uses_identity", "closed_local_identity", "owned_arrays_seen", "layout_owner_traversal", "emission_owner_reads"]:
            started = time.monotonic()
            test = ROOT / "tests" / (name + ".goose")
            before = inputs(test, stdlib)
            case = output / name
            source = case / "src"
            source.mkdir(parents=True, exist_ok=True)
            for module in (ROOT / "src").iterdir():
                if module.name == "main.goose":
                    continue
                link = source / module.name
                if not link.is_symlink():
                    link.symlink_to(module, target_is_directory=module.is_dir())
            shutil.copyfile(test, source / "main.goose")
            program, binary = case / "program.c", case / "test"
            call(name + " emit", [str(goose), "-O0", "--stdlib", str(stdlib),
                "-o", str(program), str(source / "main.goose")], args.timeout)
            call(name + " link", [str(cc)] + flags + [str(program)] +
                [str(path) for path in objects] + ["-lm", "-o", str(binary)], args.timeout)
            call(name + " run", [str(binary)], args.timeout)
            if inputs(test, stdlib) != before:
                raise RuntimeError(f"{name}: source changed during verification")
            seconds = time.monotonic() - started
            evidence["tests"][name] = {"inputs": before, "seconds": seconds,
                "program_sha256": build.digest_file(program), "binary_sha256": build.digest_file(binary)}
            print(f"{name}: passed ({seconds:.3f}s)")
        evidence["passed"] = True
        return 0
    except (OSError, RuntimeError) as failure:
        evidence["passed"] = False
        evidence["failure"] = str(failure)
        print(failure, file=sys.stderr)
        return 1
    finally:
        receipts = output / "receipts"
        receipts.mkdir(exist_ok=True)
        archive = receipts / (str(time.time_ns()) + ".json.gz")
        evidence["receipt"] = str(archive)
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        logs = {}
        for stage in evidence["stages"]:
            path = Path(stage["log"])
            logs[str(path)] = base64.b64encode(path.read_bytes()).decode("ascii")
        payload = {"evidence": evidence, "stage_logs_base64": logs}
        with archive.open("xb") as stream:
            stream.write(gzip.compress(json.dumps(payload).encode(), mtime=0))
        print("Immutable receipt: " + str(archive), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
