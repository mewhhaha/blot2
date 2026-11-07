#!/usr/bin/env python3
"""Build the optional private containment experiment; never select it by default."""

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
PATCH_SHA256 = "06a8e595057d89e734b5a5e153b8d930cfd031de9f463fbe62d3186ab7818b91"
PATCHED_SOURCE_SHA256 = "6c3d5bcfba8ef629f4df78b545074357b3f279685e32e5e82c91d6c9cae6d8cf"
PATCHED_HEADERS = {
    "src/type_queries.h": "b208f80b37381846b15c5070b7740e365c746da726b1bff183a29aff4e61a7b0",
    "src/typecheck.h": "f7d15db05a495ec865b52fa73dba922716ca0be5fb3d6d51b4564e59d9c3d8bb",
    "src/typecheck_types.h": "1b2504f80d3ec8d9f87dbb8d795bb75dc95674514ff8ba418983dc85d868caad",
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
    if len(files) != 108 or actual != expected:
        raise RuntimeError(f"source/src differs from expected pin: {len(files)} files, sha256 {actual}")
    return actual


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
        '-DGOOSE_TCC_LIB_PATH="' + str(native / "tcclib") + '"',
        "-I" + str(goose_build / "source/third_party/subprocess"),
        "-I" + str(native / "generated"), "-isystem", str(native / "tcc/api"),
    ]
    identity = fingerprints(goose_build, patch, cxx, flags)
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
            stages.append(run_stage("compile", [
                str(cxx), *flags, "-c", str(work / "source/src/main.cpp"),
                "-o", str(work / "main.cpp.o"),
            ], work, 90))
            stages.append(run_stage("link", [
                str(cxx), str(work / "main.cpp.o"),
                *[str(native / name) for name in LINK_INPUTS],
                "-ldl", "-lm", "-o", str(work / "goose"),
            ], work, 15))
            if fingerprints(goose_build, patch, cxx, flags) != identity:
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
    args = parser.parse_args()
    try:
        print(json.dumps(build(args)))
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
