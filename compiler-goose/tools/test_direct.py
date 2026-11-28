#!/usr/bin/env python3
"""Check the direct backend's laws against the recorded bytes.

Each law in compiler-goose/tests/direct is NAME.goose, which prints bytes as
hex, beside NAME.expected. `writer.expected` preserves the exact bytes the Zig
direct backend produced on 15 November 2026; `runtime.expected` was updated on
23 November 2026 for Phase 3 of Concurrency vNext (history-independent logical
stack/heap budgets, exact-cap active-only stack free lists, dedicated transport
pool with Page-0 offset 640 `arena_oom_flag`, `live_flag` / `static_pool_flag`,
inter-procedural `escape_min_slot`, and trap-safe `fork` / persistent staging),
and on 24 November 2026 for Unified Dynamic Arrays Phase 5 (removed
`Runtime.freeze` and the `GrowArray`/`ResizeArray` distinction;
`runtime.expected` shrinks to 7707 bytes), and on 25 November 2026 for Audit
Soundness + Trap Provenance (`r.create` `length > capacity_mask / stride`
overflow guard and Page-0 offset `772` `trap_site_offset` zeroing in `r.reset`;
`runtime.expected` is 7765 bytes), and on 27 November 2026 for Batch 1+2
(`stack_slow` best-fit large-chunk reuse within 4x and `r.reserve` for
`@storage.reserve`/`@storage.extend`; `runtime.expected` is 8371 bytes), and on
28 November 2026 for Batch 6 (extracted shared cold `push_grow` helper used by
`r.push`/`r.reserve` with gated `>= 8 MiB` in-place tail extension at
`arena_top`; `runtime.expected` is 8571 bytes).
The output must equal the record, and Goose must not warn.

Usage: python3 compiler-goose/tools/test_direct.py [--goose EXE] [--stdlib DIR] [NAME ...]
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT.parent
LAWS = ROOT / "tests/direct"
UPSTREAM_GOOSE = REPOSITORY / "build/goose-port/upstream-d5ae5bb"
GOOSEW_VERSION = os.environ.get("GOOSEW_VERSION", "v2026.4-8")


def default_goose() -> Path:
    if os.environ.get("GOOSE_USE_UPSTREAM") == "1":
        return UPSTREAM_GOOSE / "build-precision/goose"
    exe = ".exe" if sys.platform == "win32" else ""
    candidates: list[Path] = []
    if env_bin := os.environ.get("GOOSEW_BIN"):
        candidates.append(Path(env_bin))
    candidates.append(REPOSITORY.parent / "goose-to-wasm/build/bin" / f"goosew{exe}")
    if on_path := shutil.which("goosew"):
        candidates.append(Path(on_path))
    candidates.append(ROOT / "build/goosew" / GOOSEW_VERSION / "bin" / f"goosew{exe}")
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return UPSTREAM_GOOSE / "build-precision/goose"


def default_stdlib(goose: Path) -> Path:
    if env_stdlib := os.environ.get("GOOSE_STDLIB"):
        path = Path(env_stdlib)
        if path.is_dir():
            return path
    resolved = goose.resolve()
    for candidate in (
        resolved.parent / "stdlib",
        resolved.parent.parent / "stdlib",
        REPOSITORY.parent / "goose-to-wasm/build/bin/stdlib",
        REPOSITORY.parent / "goose-to-wasm/stdlib",
        UPSTREAM_GOOSE / "source-precision/stdlib",
    ):
        if candidate.is_dir():
            return candidate
    return UPSTREAM_GOOSE / "source-precision/stdlib"


def is_goosew(goose: Path) -> bool:
    return goose.stem.lower().startswith("goosew")


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if result.returncode != 0:
        raise SystemExit(f"{' '.join(map(str, command))} failed:\n{result.stderr}")
    return result.stdout.strip(), result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--goose", type=Path, default=None)
    parser.add_argument("--stdlib", type=Path, default=None)
    args = parser.parse_args()
    goose_bin = args.goose or default_goose()
    stdlib = args.stdlib or default_stdlib(goose_bin)
    names = args.names or sorted(path.stem for path in LAWS.glob("*.goose"))
    failed = False
    for name in names:
        expected = (LAWS / f"{name}.expected").read_text().strip()
        with tempfile.TemporaryDirectory(prefix="squid-direct-") as scratch:
            # The law as main.goose beside the compiler's sources.
            work = Path(scratch)
            for part in ("direct", "support"):
                src = ROOT / "src" / part
                dst = work / part
                try:
                    dst.symlink_to(src, target_is_directory=True)
                except OSError:
                    shutil.copytree(src, dst)
            shutil.copy(LAWS / f"{name}.goose", work / "main.goose")
            if is_goosew(goose_bin):
                cmd = [
                    str(goose_bin), "main.goose", "--stdlib", str(stdlib),
                    "--target", "native", "-O2", "-o", str(work / "out.c"), "--run",
                ]
            else:
                cmd = [str(goose_bin), "main.goose", "--stdlib", str(stdlib)]
            actual, warnings = run(cmd, work)
        problems = []
        if actual != expected:
            problems.append("bytes differ")
        if "warning" in warnings:
            problems.append("Goose warnings")
            print(warnings, file=sys.stderr)
        print(f"{name}: {', '.join(problems) or 'ok'} ({len(expected) // 2} bytes)")
        failed = failed or bool(problems)
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
