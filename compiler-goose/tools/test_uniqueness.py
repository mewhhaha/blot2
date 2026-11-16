#!/usr/bin/env python3
"""Check the uniqueness pass against the record of the Zig compiler.

Each program in compiler-goose/tests/uniqueness is built as one file, with no
prelude. It may not get a lex, parse or check diagnostic, and its lowering
diagnostics must be those in tests/uniqueness/expected.json: code, span,
message, count and order. For the 73 programs named a, b, c and d the record
holds what the Zig compiler reported on 15 November 2026, the day it was
removed, except b41, c05 and c10, which moves at a last read now accept, and
b18 and the second site of c22, which take a fresh tuple apart. The
programs named e and f are about `own` parameters and those moves, which came
later; their record is this compiler's, read through by hand. The pass runs after
lowering, so `build` reaches it whether or not a backend follows. A run that
ends without a compilation record (a crash) fails.

The programs named g are about the rules every function has: its result is
the caller's alone, and a call only borrows its arguments. The programs
named h are about what stays while `=` exists: `lent` functions, what a
store may keep, function values, and a closure that gives back what it
captured after the call it was written for. The programs named i are
about `own` in function types: lambdas and function values that take a
parameter over. The programs named j take a value apart into parts of
its own.

Usage: python3 compiler-goose/tools/test_uniqueness.py [--compiler EXE] [NAME ...]
       --record EXE writes expected.json from that compiler instead.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LAWS = ROOT / "tests/uniqueness"
EXPECTED = LAWS / "expected.json"
# (label, environment switch, record)
MODES = [("", False, EXPECTED)]


def diagnostics(compiler, source, output, rules=False):
    environment = dict(os.environ)
    environment.pop("BLOT_REPORT_STORES", None)
    result = subprocess.run([str(compiler), "build", str(source), str(output)], capture_output=True, text=True,
                            stdin=subprocess.DEVNULL, timeout=120, env=environment)
    frontend, lowering = [], []
    if '"kind":"compilation"' not in result.stdout:
        raise SystemExit(f"{compiler} ended without a compilation record for {source.name}: {result.stderr.strip()[:300]}")
    for line in result.stdout.splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            raise SystemExit(f"{compiler} printed a line that is not JSON for {source.name}: {line[:200]}")
        if record.get("kind") != "diagnostic":
            continue
        item = [record.get("code"), record.get("start"), record.get("end"), record.get("message")]
        if record.get("stage") == "lower":
            lowering.append(item)
        elif record.get("stage") in ("lex", "parse", "check"):
            frontend.append(item)
    return frontend, lowering


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--compiler", type=Path, default=ROOT / "build/blotc-goose")
    parser.add_argument("--record", type=Path, help="write expected.json from this compiler")
    args = parser.parse_args()
    every = sorted(path.stem for path in LAWS.glob("*.blot"))
    failed = False
    with tempfile.TemporaryDirectory(prefix="blot-uniqueness-") as scratch:
        for label, rules, path in MODES:
            if args.record:
                record = {}
                for name in every:
                    frontend, lowering = diagnostics(args.record, LAWS / f"{name}.blot", Path(scratch) / f"{name}.wasm", rules)
                    if frontend:
                        raise SystemExit(f"{name}{label}: frontend diagnostics {[item[0] for item in frontend]}")
                    record[name] = lowering
                path.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
                print(f"recorded {len(record)} programs{label}")
                continue
            expected = json.loads(path.read_text())
            names = args.names or every
            wrong = rejected = accepted = 0
            for name in names:
                frontend, lowering = diagnostics(args.compiler, LAWS / f"{name}.blot", Path(scratch) / f"{name}.wasm", rules)
                problems = []
                if name not in expected:
                    problems.append("no record")
                if frontend:
                    problems.append(f"frontend diagnostics {[item[0] for item in frontend]}")
                if lowering != expected.get(name):
                    problems.append(f"got {[item[:3] for item in lowering]}, recorded {[item[:3] for item in expected.get(name, [])]}")
                if problems:
                    wrong += 1
                    print(f"{name}{label}: {'; '.join(problems)}")
                elif lowering:
                    rejected += 1
                else:
                    accepted += 1
            print(f"uniqueness{label}: {rejected + accepted} of {len(names)} programs match the record ({rejected} with rejections, {accepted} accepted)")
            failed = failed or wrong != 0
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
