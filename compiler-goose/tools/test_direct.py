#!/usr/bin/env python3
"""Check the direct backend's laws against the recorded bytes.

Each law in compiler-goose/tests/direct is NAME.goose, which prints bytes as
hex, beside NAME.expected. `writer.expected` preserves the exact bytes the Zig
direct backend produced on 15 November 2026; `runtime.expected` was updated on
22 November 2026 for the on-demand 64 KiB linear memory allocator (paged owner
directory, chunk-list scratch stack, lazy transport/undo buffers). The output
must equal the record, and Goose must not warn.

Usage: python3 compiler-goose/tools/test_direct.py [--goose EXE] [--stdlib DIR] [NAME ...]
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT.parent
LAWS = ROOT / "tests/direct"
GOOSE = REPOSITORY / "build/goose-port/upstream-d5ae5bb"


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if result.returncode != 0:
        raise SystemExit(f"{' '.join(map(str, command))} failed:\n{result.stderr}")
    return result.stdout.strip(), result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--goose", type=Path, default=GOOSE / "build-precision/goose")
    parser.add_argument("--stdlib", type=Path, default=GOOSE / "source-precision/stdlib")
    args = parser.parse_args()
    names = args.names or sorted(path.stem for path in LAWS.glob("*.goose"))
    failed = False
    for name in names:
        expected = (LAWS / f"{name}.expected").read_text().strip()
        with tempfile.TemporaryDirectory(prefix="blot-direct-") as scratch:
            # The law as main.goose beside the compiler's sources.
            goose = Path(scratch)
            for part in ("direct", "support"):
                (goose / part).symlink_to(ROOT / "src" / part)
            shutil.copy(LAWS / f"{name}.goose", goose / "main.goose")
            actual, warnings = run([str(args.goose), "main.goose", "--stdlib", str(args.stdlib)], goose)
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
