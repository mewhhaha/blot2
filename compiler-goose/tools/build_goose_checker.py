#!/usr/bin/env python3
"""Build a pinned private checker with explicit optional development modes."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
SOURCE_SHA256 = "1c7388a6c15f4429fef83f9d8377524123c231a2df20ddad91542ea31ff4bd39"
PATCH_SHA256 = "5168d0b9ad17328d8ada154c251c6bd3956ea801fdb61ff92f9427e38d4e4bfa"
PATCHED_SOURCE_SHA256 = "652b36d0039864a5a2bc9f6220f86bf08da77624f53a650ff15fe61e6914eded"
PATCHED_HEADERS = {
    "src/typecheck_calls.h": "3ca9bf3180d7793fa4e5cc7cc449f817bd1cb0ef6b44e6c07cf1ec33de15117c",
    "src/typecheck_builtins.h": "1bfec9e12a67467f44935a2820b416e7f12ca6c7e4e1af4eaf3969b153ce75e1",
    "src/clone.h": "f9e88692342c320da4290773ca0fdb159171e6ddb9211967a55dd7fa819bc79c",
    "src/type_queries.h": "521a808993a7f286dfdd79aa9494979ab334731984305aefe82cf112c91a900c",
    "src/typecheck.h": "5caf95d6677b44574d6bd167d4f9106107635947435ea8fcbfcac9e7c167e401",
    "src/typecheck_types.h": "dc1413cca9c5a4d945f17f079145875e4b49993d6eaff399e7a74f8d20b4a8cd",
}

REACHABLE_PROGRAM_PATCH_SHA256 = "b85c2eb347e88d6d5a0ba203d95370da872737538303f3a1e07cd27581cabb09"
# Keys are (selected-root diagnostics, runtime observation). All 108 files stay pinned.
REACHABLE_PROGRAM_SOURCES = {
    (False, False): "580dacd788139adf330874699fb9dd107194dcd8cbc386d804b9f054aad47e38",
    (True, False): "093b2a49921d7bcbe70fa772c442e1fe55e551bfda6f9bacf666f48510fe9d39",
    (False, True): "289fe724f7f13022bf035c911de73b92de399151d432b7dbfe9da467b0d9eda3",
    (True, True): "b35482ed9f79d8ba68578b8c16c07c6576a80bd379f2246e0c5a59610d5c9c15",
}

STABLE_CLOSURES_PATCH_SHA256 = "9e39a1011fbd9ceeb27caa0ea05584e476e33066f99cbac1bc105d91958aa91f"
# Keys are diagnostics, runtime observation and reachable-program mode.
STABLE_CLOSURES_SOURCES = {
    (False, False, False): "861fcfc6c786a0d768dfb2d4b2d27dfc584b56ad2d6138bf5e13052d461e09c9",
    (False, False, True): "d42241b5f0e4ed9fa276bdcbd38c4f3acaaa49012f3859a2f24d6a24e01ef6f8",
    (False, True, False): "b898170cd638f5f185aa6f5ecb46590426397f717ac489fd4a60896926fb826d",
    (False, True, True): "6e7af3b6b5ba0e44eebb1c125d0d5ad9c105ddf335ec611d0e2845dae046dbad",
    (True, False, False): "d3772ffcc2231c76db17d241d0ad3305b36c3196d4410175069612c4b124367e",
    (True, False, True): "f77020969723688160b6a4f469717a62691b8089d386256072ffc1e734ec92e9",
    (True, True, False): "62e4bbc04b7dcb2c5770e3185a24de6068a6627fcd087b9d17334a8d66847ef1",
    (True, True, True): "7c1501a2a77451b3f3d38d31b19daba4204baeefd91310f2e6235613623bdec6",
}

ARRAY_REACH_GATE_PATCH_SHA256 = "bddc93903b58489f47c1ddf41adfe141d1a68e795777f96554cd8b8207ef804a"
# This layer requires stable-closures; keys are diagnostics/runtime/reachable.
ARRAY_REACH_GATE_SOURCES = {
    (False, False, False): "dcedc7d49da1643e469a5bfe34a55a93672a7a1d49d354a413ae42f52e62f91a",
    (False, False, True): "260743c05ebfd13fb6d102c93dec3707b3d8923bbd6522ec44f9f2d880fb5cf0",
    (False, True, False): "29bcb52979da4b80a14266b64d0f86e95e086975818518658bea217eccb9ddb3",
    (False, True, True): "cd1fc3306a761a633a00c27d0b65eac8286126e24d56fd2ee08a36632cf5f680",
    (True, False, False): "4616a9c32fc51a9f6ce9181ac1cccb29825d1d84aafafe722c3cfb828a793f22",
    (True, False, True): "912ba1fc9e1111841a8379d7a0daade247e04251f470736bd7d5642d4eaf02ab",
    (True, True, False): "9f5bf7ea2500c01a5cf3057712ed67bcea76b162797a2647499adde728893712",
    (True, True, True): "dcd6ffbca3ac21a4fafe227525c08eeda2f0caff0c399ca29a29d4223a414d45",
}

LINK_INPUTS = (
    "CMakeFiles/goose.dir/src/process.cpp.o",
    "CMakeFiles/goose.dir/src/progress.cpp.o",
    "libgoose_shaderc.a",
    "libtcc.a",
)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def json_digest(value):
    data = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(data).hexdigest()


def tree_digest(path):
    if not path.is_dir():
        raise RuntimeError(f"missing input directory: {path}")
    files = {}
    for item in sorted(path.rglob("*")):
        if item.is_file():
            files[str(item.relative_to(path))] = digest(item)
    if not files:
        raise RuntimeError(f"empty input directory: {path}")
    return json_digest(files)


def checked_source(source, expected=SOURCE_SHA256):
    # Paths include src/ to match the frozen 108-file upstream manifest.
    files = {}
    for item in sorted((source / "src").rglob("*")):
        if item.is_file():
            files[str(item.relative_to(source))] = digest(item)
    actual = json_digest(files)
    if len(files) != 108 or (expected is not None and actual != expected):
        raise RuntimeError(f"source/src differs from expected pin: {len(files)} files, sha256 {actual}")
    return actual


def regenerate_runtime_header(source):
    # Match upstream GenRuntimeHeader, from private runtime inputs only.
    names = ("runtime.h", "runtime_impl.h", "runtime_threads.h",
             "runtime_ext.h", "runtime_os.h", "goose.h")
    output = ('// Generated by `goose --gen-runtime-header` from src/runtime/. '
              'Do not edit.\n#pragma once\n\nnamespace goose {\n\n'
              'struct RuntimeFile {\n    const char *name;\n    string_view text;\n'
              '};\n\ninline const RuntimeFile runtime_files[] = {\n')
    for name in names:
        contents = (source / "src/runtime" / name).read_text()
        if ')GSRT"' in contents:
            raise RuntimeError(f"runtime raw-string delimiter in {name}")
        output += '    { "' + name + '", string_view(\n'
        position = 0
        while position < len(contents):
            end = min(position + 8000, len(contents))
            if end < len(contents):
                newline = contents.rfind("\n", position, end + 1)
                if newline > position:
                    end = newline + 1
            output += 'R"GSRT(' + contents[position:end] + ')GSRT"\n'
            position = end
        if not contents:
            output += '""\n'
        output += '    ) },\n'
    output += '};\n\n}  // namespace goose\n'
    (source / "src/runtime_inline.h").write_text(output)


def fingerprints(goose_build, patch, cxx, flags):
    source = goose_build / "source"
    native = goose_build / "native"
    source_sha256 = checked_source(source)
    if digest(patch) != PATCH_SHA256:
        raise RuntimeError("containment patch changed; review and update its pinned digest")
    version = subprocess.check_output([str(cxx), "--version"], text=True, timeout=5)
    if version.splitlines()[0] != "clang version 23.1.4":
        raise RuntimeError(f"expected clang 23.1.4, got {version.splitlines()[0]}")
    inputs = {}
    for name in LINK_INPUTS:
        inputs[name] = digest(native / name)
    for name in ("generated", "tcc/api", "tcclib"):
        inputs[name] = tree_digest(native / name)
    inputs["subprocess"] = tree_digest(source / "third_party/subprocess")
    return {
        "recipe_sha256": digest(Path(__file__)),
        "source_sha256": source_sha256,
        "patch_sha256": PATCH_SHA256,
        "patched_source_sha256": PATCHED_SOURCE_SHA256,
        "patched_headers": PATCHED_HEADERS,
        "cxx": str(cxx),
        "cxx_sha256": digest(cxx),
        "cxx_version": version.strip(),
        "compile_flags": flags,
        "link_flags": ["-ldl", "-lm"],
        "goose_build": str(goose_build),
        "inputs": inputs,
    }


def run_stage(name, command, work, timeout):
    started = time.monotonic()
    with (work / f"{name}.log").open("w") as log:
        child = subprocess.Popen(
            command, cwd=work, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            status = child.wait(timeout=timeout)
        except BaseException:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
            raise
    result = {"stage": name, "exit": status, "seconds": round(time.monotonic() - started, 3)}
    print(json.dumps(result), file=sys.stderr, flush=True)
    if status:
        raise RuntimeError(f"{name} failed ({status}); see {work / (name + '.log')}")
    return result


def build(args):
    if args.array_reach_gate and not args.stable_closures:
        raise RuntimeError("--array-reach-gate requires --stable-closures")
    goose_build = args.goose_build.resolve()
    cache = args.cache_dir.resolve()
    if cache.is_relative_to(goose_build):
        raise RuntimeError("cache directory must be outside the upstream Goose build")
    patch = Path(__file__).with_name("goose-containment.patch")
    cxx = Path("/usr/bin/clang++")
    native = goose_build / "native"
    flags = [
        "-O3", "-DNDEBUG", "-std=gnu++20", "-Wall", "-Wextra",
        "-Wno-missing-field-initializers",
        "-DGOOSE_EXPANSION_NODE_LIMIT=" + str(args.expansion_node_limit),
        '-DGOOSE_TCC_LIB_PATH="' + str(native / "tcclib") + '"',
        "-I" + str(goose_build / "source/third_party/subprocess"),
        "-I" + str(native / "generated"), "-isystem", str(native / "tcc/api"),
    ]
    if args.reachable_program:
        flags.append("-DGOOSE_REACHABLE_PROGRAM=1")
    identity = fingerprints(goose_build, patch, cxx, flags)
    diagnostic_patch = Path(__file__).with_name("goose-diagnostic-roots.patch")
    if args.diagnostic_roots:
        identity["diagnostic_roots_patch_sha256"] = digest(diagnostic_patch)
    runtime_patch = Path(__file__).with_name("goose-runtime-observer.patch")
    if args.runtime_observer:
        identity["runtime_observer_patch_sha256"] = digest(runtime_patch)
    reachable_patch = Path(__file__).with_name("goose-reachable-program.patch")
    if args.reachable_program:
        if digest(reachable_patch) != REACHABLE_PROGRAM_PATCH_SHA256:
            raise RuntimeError("reachable-program patch changed; review and update its pinned digest")
        identity["reachable_program_patch_sha256"] = REACHABLE_PROGRAM_PATCH_SHA256
        identity["reachable_program_source_sha256"] = REACHABLE_PROGRAM_SOURCES[
            (args.diagnostic_roots, args.runtime_observer)
        ]
    stable_patch = Path(__file__).with_name("goose-stable-closures.patch")
    if args.stable_closures:
        if digest(stable_patch) != STABLE_CLOSURES_PATCH_SHA256:
            raise RuntimeError("stable-closures patch changed; review and update its pinned digest")
        identity["stable_closures_patch_sha256"] = STABLE_CLOSURES_PATCH_SHA256
        identity["stable_closures_source_sha256"] = STABLE_CLOSURES_SOURCES[
            (args.diagnostic_roots, args.runtime_observer, args.reachable_program)
        ]
    array_patch = Path(__file__).with_name("goose-array-reach-gate.patch")
    if args.array_reach_gate:
        if digest(array_patch) != ARRAY_REACH_GATE_PATCH_SHA256:
            raise RuntimeError("array-reach-gate patch changed; review and update its pinned digest")
        identity["array_reach_gate_patch_sha256"] = ARRAY_REACH_GATE_PATCH_SHA256
        identity["array_reach_gate_source_sha256"] = ARRAY_REACH_GATE_SOURCES[
            (args.diagnostic_roots, args.runtime_observer, args.reachable_program)
        ]
    key = json_digest(identity)
    cache.mkdir(parents=True, exist_ok=True)
    # Serialize publishers; a failed or interrupted build never replaces a binary.
    with (cache / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        completed = cache / key
        binary = completed / "goose"
        if completed.exists():
            receipt = json.loads((completed / "receipt.json").read_text())
            if receipt["identity"] != identity or digest(binary) != receipt["binary_sha256"]:
                raise RuntimeError(f"damaged cache entry; remove {completed} and retry")
            return {"binary": str(binary), "sha256": receipt["binary_sha256"], "cached": True}
        work = Path(tempfile.mkdtemp(prefix=key + ".", dir=cache))
        try:
            shutil.copytree(goose_build / "source/src", work / "source/src")
            checked_source(work / "source")
            stages = [run_stage("patch", [
                "patch", "--batch", "--forward", "--fuzz=0", "-p1",
                "-d", str(work / "source"), "-i", str(patch),
            ], work, 5)]
            patched_source_sha256 = checked_source(work / "source", PATCHED_SOURCE_SHA256)
            for name, expected in PATCHED_HEADERS.items():
                if digest(work / "source" / name) != expected:
                    raise RuntimeError(f"patched header differs from candidate: {name}")
            if args.diagnostic_roots:
                stages.append(run_stage("diagnostic-patch", [
                    "patch", "--batch", "--forward", "--fuzz=0", "-p1",
                    "-d", str(work / "source"), "-i", str(diagnostic_patch),
                ], work, 5))
                patched_source_sha256 = checked_source(
                    work / "source", "faf008f12e7add6de2447bde29a5f6cff489da0883a2091bead315f02a713c81"
                )
            if args.runtime_observer:
                stages.append(run_stage("runtime-observer-patch", [
                    "patch", "--batch", "--forward", "--fuzz=0", "-p1",
                    "-d", str(work / "source"), "-i", str(runtime_patch),
                ], work, 5))
                regenerate_runtime_header(work / "source")
                patched_source_sha256 = checked_source(work / "source", None)
            if args.reachable_program:
                stages.append(run_stage("reachable-program-patch", [
                    "patch", "--batch", "--forward", "--fuzz=0", "--no-backup-if-mismatch", "-p1",
                    "-d", str(work / "source"), "-i", str(reachable_patch),
                ], work, 5))
                patched_source_sha256 = checked_source(
                    work / "source", identity["reachable_program_source_sha256"]
                )
            if args.stable_closures:
                stages.append(run_stage("stable-closures-patch", [
                    "patch", "--batch", "--forward", "--fuzz=0", "--no-backup-if-mismatch", "-p1",
                    "-d", str(work / "source"), "-i", str(stable_patch),
                ], work, 5))
                patched_source_sha256 = checked_source(
                    work / "source", identity["stable_closures_source_sha256"]
                )
            if args.array_reach_gate:
                stages.append(run_stage("array-reach-gate-patch", [
                    "patch", "--batch", "--forward", "--fuzz=0", "--no-backup-if-mismatch", "-p1",
                    "-d", str(work / "source"), "-i", str(array_patch),
                ], work, 5))
                patched_source_sha256 = checked_source(
                    work / "source", identity["array_reach_gate_source_sha256"]
                )
            stages.append(run_stage("compile", [
                str(cxx), *flags, "-c", str(work / "source/src/main.cpp"),
                "-o", str(work / "main.cpp.o"),
            ], work, 120))
            stages.append(run_stage("link", [
                str(cxx), str(work / "main.cpp.o"),
                *[str(native / name) for name in LINK_INPUTS],
                "-ldl", "-lm", "-o", str(work / "goose"),
            ], work, 15))
            final_identity = fingerprints(goose_build, patch, cxx, flags)
            if args.diagnostic_roots:
                final_identity["diagnostic_roots_patch_sha256"] = digest(diagnostic_patch)
            if args.runtime_observer:
                final_identity["runtime_observer_patch_sha256"] = digest(runtime_patch)
            if args.reachable_program:
                final_identity["reachable_program_patch_sha256"] = digest(reachable_patch)
                final_identity["reachable_program_source_sha256"] = REACHABLE_PROGRAM_SOURCES[
                    (args.diagnostic_roots, args.runtime_observer)
                ]
            if args.stable_closures:
                final_identity["stable_closures_patch_sha256"] = digest(stable_patch)
                final_identity["stable_closures_source_sha256"] = STABLE_CLOSURES_SOURCES[
                    (args.diagnostic_roots, args.runtime_observer, args.reachable_program)
                ]
            if args.array_reach_gate:
                final_identity["array_reach_gate_patch_sha256"] = digest(array_patch)
                final_identity["array_reach_gate_source_sha256"] = ARRAY_REACH_GATE_SOURCES[
                    (args.diagnostic_roots, args.runtime_observer, args.reachable_program)
                ]
            if final_identity != identity:
                raise RuntimeError("build inputs changed during compilation; refusing publication")
            receipt = {
                "identity": identity, "binary_sha256": digest(work / "goose"),
                "stages": stages, "patched_source_sha256": patched_source_sha256,
            }
            (work / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
            work.rename(completed)
        except BaseException:
            print(f"unfinished private build retained at {work}", file=sys.stderr)
            raise
    return {"binary": str(binary), "sha256": receipt["binary_sha256"], "cached": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--goose-build", type=Path, default=ROOT.parent / "goose-to-wasm/build",
        help="existing official Goose build containing source/ and native/",
    )
    parser.add_argument(
        "--cache-dir", type=Path, default=ROOT / "build/goose-port/private-checker",
        help="private build cache (default: ignored build/goose-port/private-checker)",
    )
    parser.add_argument(
        "--expansion-node-limit", type=int, choices=(100000, 1000000), default=100000,
        help="bounded cumulative const-for expansion nodes; default retains upstream100000",
    )
    parser.add_argument(
        "--diagnostic-roots", action="store_true",
        help="include store-origin notes and optional GOOSE_DIAGNOSTIC_ROOTS selection",
    )
    parser.add_argument(
        "--runtime-observer", action="store_true",
        help="include private pool/capacity events and terminal OOM failpoints",
    )
    parser.add_argument(
        "--reachable-program", action="store_true",
        help="omit eager dead-body diagnostics; retain live roots, externs and signatures",
    )
    parser.add_argument(
        "--stable-closures", action="store_true",
        help="publish complete stable graph closures; include optional query profile counters",
    )
    parser.add_argument(
        "--array-reach-gate", action="store_true",
        help="qualify ArrayElems cache by actual reachability; requires --stable-closures",
    )
    args = parser.parse_args()
    try:
        print(json.dumps(build(args)))
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
