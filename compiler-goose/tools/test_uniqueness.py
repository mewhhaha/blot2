#!/usr/bin/env python3
"""Check the Goose port of the uniqueness pass against the Zig compiler.

Each program in compiler-goose/tests/uniqueness is built as one file, with no
prelude, by both compilers. Neither may report a lex, parse or check
diagnostic, and both must report the same lowering diagnostics: code, span,
message, count and order. The pass runs after lowering, so `build` reaches it
whether or not a backend follows.

Usage: python3 compiler-goose/tools/test_uniqueness.py [--zig BLOTC] [--goose BLOTC_GOOSE] [NAME ...]
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT.parent
LAWS = ROOT / "tests/uniqueness"


def diagnostics(compiler, source, output):
    result = subprocess.run([str(compiler), "build", str(source), str(output)], capture_output=True, text=True,
                            stdin=subprocess.DEVNULL, timeout=120)
    frontend, lowering = [], []
    for line in result.stdout.splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            raise SystemExit(f"{compiler} printed a line that is not JSON for {source.name}: {line[:200]}")
        if record.get("kind") != "diagnostic":
            continue
        item = (record.get("code"), record.get("start"), record.get("end"), record.get("message"))
        if record.get("stage") == "lower":
            lowering.append(item)
        elif record.get("stage") in ("lex", "parse", "check"):
            frontend.append(item)
    return frontend, lowering


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--zig", type=Path, default=REPOSITORY / "compiler/zig-out/bin/blotc")
    parser.add_argument("--goose", type=Path, default=ROOT / "build/blotc-goose")
    args = parser.parse_args()
    names = args.names or sorted(path.stem for path in LAWS.glob("*.blot"))
    failed = rejected = accepted = 0
    with tempfile.TemporaryDirectory(prefix="blot-uniqueness-") as scratch:
        for name in names:
            source = LAWS / f"{name}.blot"
            zig_frontend, zig_lowering = diagnostics(args.zig, source, Path(scratch) / f"{name}.zig.wasm")
            goose_frontend, goose_lowering = diagnostics(args.goose, source, Path(scratch) / f"{name}.goose.wasm")
            problems = []
            if zig_frontend or goose_frontend:
                problems.append(f"frontend diagnostics (zig {[item[0] for item in zig_frontend]}, goose {[item[0] for item in goose_frontend]})")
            if zig_lowering != goose_lowering:
                problems.append(f"zig {[item[:3] for item in zig_lowering]} goose {[item[:3] for item in goose_lowering]}")
            if problems:
                failed += 1
                print(f"{name}: {'; '.join(problems)}")
            elif zig_lowering:
                rejected += 1
            else:
                accepted += 1
    print(f"uniqueness: {rejected + accepted} of {len(names)} programs agree ({rejected} with rejections, {accepted} accepted)")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
