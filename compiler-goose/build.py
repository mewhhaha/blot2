#!/usr/bin/env python3
"""Build the Goose compiler itself; no Zig compiler/oracle is invoked.

The active source-writing phase does not run this build. --identity-only is a
source authoring operation and never starts a compiler. Every actual build
regenerates its identity after writing the selected Goose runtime, then emits
C through a C-host header and links only the ordinary Goose runtime/OS shim.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
IDENTITY = ROOT / "src/source_identity.goose"
MANIFEST = ROOT / "build/source-identity.json"
DOMAIN = b"blot-goose-compiler-source-v1\0"


def digest_file(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for part in iter(lambda: source.read(1024 * 1024), b""):
            value.update(part)
    return value.hexdigest()


def frame(value: bytes) -> bytes:
    return struct.pack("<Q", len(value)) + value


def source_inputs() -> list[Path]:
    paths = set((ROOT / "src").rglob("*.goose"))
    paths.update((ROOT / "native").rglob("*.c"))
    paths.update((ROOT / "native").rglob("*.h"))
    paths.add(Path(__file__).resolve())
    paths.discard(IDENTITY)
    return sorted(paths, key=lambda path: path.relative_to(ROOT).as_posix())


def executable(command: str) -> Path:
    value = shutil.which(command)
    if value is None:
        raise RuntimeError(f"executable not found: {command}")
    return Path(value).resolve()


def fingerprint(args: argparse.Namespace, goose: Path | None,
                cc: Path | None, runtime: Path | None) -> dict:
    entries = [{"path": path.relative_to(ROOT).as_posix(),
                "bytes": path.stat().st_size, "sha256": digest_file(path)}
               for path in source_inputs()]
    resources = []
    for ordinal, resource in enumerate(args.resource_root):
        resource = Path(resource).resolve(strict=True)
        for path in sorted(resource.rglob("*")):
            if path.is_file() and path.suffix in {".goose", ".h", ".c", ".inc"}:
                resources.append({"root": ordinal,
                                  "path": path.relative_to(resource).as_posix(),
                                  "bytes": path.stat().st_size,
                                  "sha256": digest_file(path)})
    goose_sha = None
    cc_sha = None
    runtime_sha = None
    goose_path = None
    cc_path = None
    if goose is not None:
        goose_sha = digest_file(goose)
        goose_path = str(goose)
    if cc is not None:
        cc_sha = digest_file(cc)
        cc_path = str(cc)
    if runtime is not None:
        runtime_sha = digest_file(runtime)
    configuration = {
        "schema": 1, "host": sys.platform, "machine": os.uname().machine,
        "entry": "src/main.goose", "host_entry": "blot_goose_main",
        "goose_inline": args.inline, "c_flags": args.cflag,
        "stdlib": args.stdlib,
        "inference_budget": args.inference_budget,
        "artifact_replay": args.artifact_replay,
        "goose_sha256": goose_sha,
        "cc_sha256": cc_sha,
        "runtime_sha256": runtime_sha,
    }
    value = hashlib.sha256(DOMAIN)
    value.update(frame(json.dumps(configuration, sort_keys=True,
                                  separators=(",", ":")).encode()))
    for entry in entries:
        value.update(frame(entry["path"].encode()))
        value.update(struct.pack("<Q", entry["bytes"]))
        value.update(bytes.fromhex(entry["sha256"]))
    value.update(frame(json.dumps(resources, sort_keys=True,
                                  separators=(",", ":")).encode()))
    return {"algorithm": "sha256", "digest": value.hexdigest(),
            "configuration": configuration, "sources": entries,
            "resource_roots": [str(Path(path).resolve())
                               for path in args.resource_root],
            "resources": resources,
            "goose": goose_path,
            "cc": cc_path,
            "build_selected": goose is not None and cc is not None,
            "qualification": "unverified source and build inputs"}


def write_identity(record: dict) -> None:
    assert record["digest"] != "00" * 32
    values = ",".join(str(byte) for byte in bytes.fromhex(record["digest"]))
    replay = "false"
    if record["configuration"]["artifact_replay"]:
        replay = "true"
    text = ("// Generated from actual Goose/host/build inputs by build.py.\n"
            "// Regenerated before every build; no Zig oracle digest is reused.\n"
            "namespace blot_source_identity;\n"
            f"let digest:u8[32]=[{values}];\n"
            f"let inference_budget:u64={record['configuration']['inference_budget']};\n"
            f"let artifact_replay:bool={replay};\n")
    IDENTITY.write_text(text)
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(record, sort_keys=True, indent=2) + "\n")


def call(stage: str, command: list[str], timeout: float) -> None:
    started = time.monotonic()
    print(f"build: {stage} started (limit {timeout:g}s)", file=sys.stderr,
          flush=True)
    try:
        process = subprocess.Popen(command, cwd=ROOT / "src", start_new_session=True)
    except OSError as failure:
        elapsed = time.monotonic() - started
        raise RuntimeError(f"{stage} could not start after {elapsed:.3f}s: {failure}") from failure
    try:
        status = process.wait(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt) as failure:
        # Terminate the whole stage, including compiler subprocesses. A failed
        # iteration must not leave work running after the driver exits.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
        # The leader may exit on TERM while descendants ignore it. Always
        # finish the group, including when the direct child has already exited.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        elapsed = time.monotonic() - started
        if isinstance(failure, KeyboardInterrupt):
            raise RuntimeError(f"{stage} interrupted after {elapsed:.3f}s") from failure
        raise RuntimeError(f"{stage} timed out after {elapsed:.3f}s "
                           f"(limit {timeout:g}s)") from failure
    elapsed = time.monotonic() - started
    if status != 0:
        raise RuntimeError(f"{stage} failed with exit {status} after {elapsed:.3f}s")
    print(f"build: {stage} finished in {elapsed:.3f}s", file=sys.stderr, flush=True)


def cached_object(stage: str, source: Path, build: Path, compiler: list[str],
                  flags: list[str], cc_digest: str, timeout: float) -> Path:
    key = hashlib.sha256(frame(source.read_bytes()) + frame(
        json.dumps({"cc": cc_digest, "flags": flags,
                    "host": sys.platform, "machine": os.uname().machine},
                   sort_keys=True).encode())).hexdigest()
    output = build / f"{source.stem}-{key[:24]}.o"
    if output.exists():
        print(f"build: {stage} cached", file=sys.stderr, flush=True)
        return output
    pending = output.with_suffix(f".{os.getpid()}.tmp.o")
    try:
        call(stage, compiler + flags + ["-c", str(source), "-o", str(pending)], timeout)
        pending.replace(output)
    finally:
        pending.unlink(missing_ok=True)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", default=os.environ.get("GOOSE_BIN", "goose"))
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/blotc-goose")
    parser.add_argument("--inline", choices=["-O0", "-O1", "-O2"], default=None)
    parser.add_argument("--release", action="store_true",
                        help="select Goose -O2 and C -O2; development defaults to -O0")
    parser.add_argument("--cflag", action="append", default=[])
    parser.add_argument("--stage-timeout", type=float, default=30,
                        help="maximum seconds per subprocess stage (default: 30)")
    parser.add_argument("--stdlib", type=Path,
                        default=os.environ.get("GOOSE_STDLIB"),
                        help="selected Goose standard library; required for actual builds")
    parser.add_argument("--resource-root", action="append", default=[],
                        help="selected Goose stdlib/package resource tree to fingerprint")
    parser.add_argument("--inference-budget", type=int, default=1_000_000)
    parser.add_argument("--artifact-replay", action="store_true")
    parser.add_argument("--identity-only", action="store_true",
                        help="write a source-only identity without executing toolchains")
    args = parser.parse_args()
    if args.stdlib is not None:
        selected_stdlib = Path(args.stdlib).resolve(strict=True)
        if not selected_stdlib.is_dir():
            parser.error("--stdlib must name a directory")
        args.stdlib = str(selected_stdlib)
        args.resource_root.append(str(selected_stdlib))
    elif not args.identity_only:
        parser.error("--stdlib (or GOOSE_STDLIB) must select the library fingerprinted and loaded by this build")
    if args.inference_budget < 1 or args.inference_budget > (1 << 64) - 1:
        parser.error("inference budget must be 1..18446744073709551615")
    if not math.isfinite(args.stage_timeout) or args.stage_timeout <= 0:
        parser.error("stage timeout must be a positive finite number of seconds")
    optimization = "-O0"
    if args.release:
        optimization = "-O2"
    if args.inline is None:
        args.inline = optimization
    args.cflag = ["-std=gnu11", "-D_GNU_SOURCE", optimization, "-pthread"] + args.cflag
    if args.identity_only:
        write_identity(fingerprint(args, None, None, None))
        return
    goose = executable(args.goose)
    cc_words = shlex.split(args.cc)
    if len(cc_words) != 1:
        parser.error("--cc names one compiler executable; pass flags with --cflag")
    cc = executable(cc_words[0])
    build = ROOT / "build"
    build.mkdir(parents=True, exist_ok=True)
    runtime = build / "goose_runtime.c"
    # Runtime emission happens before identity generation, so the identity pins
    # the actual runtime text that is compiled, as well as the emitting binary.
    call("emit runtime", [str(goose), "--emit-runtime", str(runtime)],
         args.stage_timeout)
    record = fingerprint(args, goose, cc, runtime)
    write_identity(record)
    program = build / "blot_goose.c"
    header = build / "blot_goose.h"
    call("emit program", [str(goose), "-o", str(program), "--header", str(header),
          args.inline, "--stdlib", args.stdlib, str(ROOT / "src/main.goose")], args.stage_timeout)
    compiler = [str(cc)] + cc_words[1:]
    runtime_object = cached_object("compile runtime", runtime, build, compiler,
        args.cflag, record["configuration"]["cc_sha256"], args.stage_timeout)
    platform_object = cached_object("compile platform", ROOT / "native/platform.c",
        build, compiler, args.cflag, record["configuration"]["cc_sha256"],
        args.stage_timeout)
    args.output = args.output.resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    pending_output = args.output.with_name(f"{args.output.name}.{os.getpid()}.tmp")
    try:
        call("compile and link program", compiler + args.cflag + [str(program),
             str(ROOT / "native/main.c"), str(platform_object),
             str(runtime_object), "-lm", "-o", str(pending_output)],
             args.stage_timeout)
        pending_output.replace(args.output)
    finally:
        pending_output.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as failure:
        print(f"build: {failure}", file=sys.stderr, flush=True)
        sys.exit(1)
