#!/usr/bin/env python3
"""Build every program of compiler-goose/tests/fixtures and compare with the record.

tests/fixtures/expected.json holds, for each program, what the Zig compiler
gave on 15 November 2026, the day it was removed: the exit code, the SHA-256
and size of the Wasm, and the JSON records without clocks, memory counts and
`symbol_bytes` (which counts the absolute path). Where the Goose compiler is
known to differ, `differences` holds its value beside Zig's; today that is the
`type_nodes` counter of four programs.

The record of `direct/boxed_records.blot` is this compiler's (16 November
2026): an update that leaves a boxed record's words as they were keeps its
block, and a loop that carries a boxed value releases an iteration's memory
when the value came out as it went in. tests/guest runs the program.

Usage: python3 compiler-goose/tools/test_fixtures.py [--compiler EXE] [NAME ...]
       --record EXE writes expected.json from that compiler instead.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT.parent
FIXTURES = ROOT / "tests/fixtures"
EXPECTED = FIXTURES / "expected.json"
DROPPED = ("memory", "memory_scope", "phase_profile", "symbol_bytes")


def build(compiler, name, scratch):
    """The normalized outcome of build-project for one fixture."""
    output = Path(scratch) / "out.wasm"
    if output.exists():
        output.unlink()
    result = subprocess.run(
        [str(compiler), "build-project", str(FIXTURES / name), str(output),
         "--std-root", str(REPOSITORY / "std"), "--prelude", str(REPOSITORY / "std/prelude.blot")],
        capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=600)
    text = result.stdout.replace(str(FIXTURES) + "/", "").replace(str(REPOSITORY) + "/", "")
    records = []
    for line in text.splitlines():
        record = json.loads(line)
        for key in list(record):
            if key.endswith("_us") or key in DROPPED:
                del record[key]
        records.append(record)
    outcome = {"exit": result.returncode, "records": records}
    if output.exists():
        data = output.read_bytes()
        outcome["wasm_sha256"] = hashlib.sha256(data).hexdigest()
        outcome["wasm_bytes"] = len(data)
    if result.stderr.strip():
        outcome["stderr"] = result.stderr.strip()
    return outcome


def names():
    return sorted(str(path.relative_to(FIXTURES)) for path in FIXTURES.rglob("*.blot"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--compiler", type=Path, default=ROOT / "build/blotc-goose")
    parser.add_argument("--record", type=Path, help="write expected.json from this compiler")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="blot-fixtures-") as scratch:
        if args.record:
            programs = {name: build(args.record.resolve(), name, scratch) for name in names()}
            EXPECTED.write_text(json.dumps({"programs": programs, "differences": {}}, indent=1, sort_keys=True) + "\n")
            print(f"recorded {len(programs)} programs")
            return
        expected = json.loads(EXPECTED.read_text())
        selected = args.names or names()
        failed = 0
        for name in selected:
            want = json.loads(json.dumps(expected["programs"].get(name)))
            if want is None:
                print(f"{name}: no record")
                failed += 1
                continue
            for change in expected["differences"].get(name, []):
                record = want["records"][change["record"]]
                assert record[change["counter"]] == change["zig"], (name, change)
                record[change["counter"]] = change["goose"]
            got = build(args.compiler.resolve(), name, scratch)
            if got != want:
                failed += 1
                detail = [key for key in sorted(set(got) | set(want)) if got.get(key) != want.get(key)]
                print(f"{name}: differs in {', '.join(detail)}")
                if "records" in detail:
                    for index, (left, right) in enumerate(zip(got["records"], want["records"])):
                        keys = [key for key in sorted(set(left) | set(right)) if left.get(key) != right.get(key)]
                        if keys:
                            print(f"  record {index}: " + "; ".join(
                                f"{key}: {json.dumps(left.get(key))[:80]} (recorded {json.dumps(right.get(key))[:80]})" for key in keys[:4]))
        extra = sorted(set(expected["programs"]) - set(names())) if not args.names else []
        for name in extra:
            print(f"{name}: recorded, but the program is gone")
        print(f"{len(selected) - failed} of {len(selected)} fixtures match the record")
        if failed or extra:
            sys.exit(1)


if __name__ == "__main__":
    main()
