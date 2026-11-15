#!/usr/bin/env python3
"""Check the Goose port of the direct backend against the Zig source.

Each law is a pair in compiler-goose/tests/direct: NAME.goose prints bytes as
hex, and NAME_reference.zig prints what compiler/src/direct produces for the
same input. The outputs must be equal, and Goose must not warn.

Usage: python3 compiler-goose/tools/test_direct.py [NAME ...]
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


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if result.returncode != 0:
        raise SystemExit(f"{' '.join(map(str, command))} failed:\n{result.stderr}")
    return result.stdout.strip(), result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--goose", type=Path, default=REPOSITORY / "build/goose-upstream/build/goose")
    parser.add_argument("--stdlib", type=Path, default=REPOSITORY / "build/goose-upstream/stdlib")
    args = parser.parse_args()
    names = args.names or sorted(path.stem for path in LAWS.glob("*.goose"))
    failed = False
    for name in names:
        with tempfile.TemporaryDirectory(prefix="blot-direct-") as scratch:
            scratch = Path(scratch)
            # The Zig side: the reference beside a copy of the direct backend.
            zig = scratch / "zig"
            shutil.copytree(REPOSITORY / "compiler/src/direct", zig)
            shutil.copy(LAWS / f"{name}_reference.zig", zig / "reference.zig")
            expected, _ = run(["zig", "run", "reference.zig"], zig)
            # The Goose side: the law as main.goose beside the port's sources.
            goose = scratch / "goose"
            goose.mkdir()
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
