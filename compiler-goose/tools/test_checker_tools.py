#!/usr/bin/env python3
"""Reproduce 24 semantic, 166 stability and 300 visited laws without a port build.

The baseline and candidate must both include reachable-program diagnostics and
runtime observation; the candidate additionally includes stable-closures.
Each C++ suite compiles once. Upstream Goose fixtures are checked by content hash.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

import build_goose_checker as builder
import checker_semantic_controls

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "compiler-goose/tests/checker_tools"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def block(text, head):
    start = text.index(head)
    opened = text.index("{", start)
    depth = 1
    end = opened + 1
    while depth:
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
        end += 1
    return text[start:end]


def source_root(path):
    path = path.resolve()
    if path.name == "src":
        path = path.parent
    builder.checked_source(path, None)
    return path


def command(args, name, values, timeout):
    started = time.monotonic()
    result = subprocess.run([str(value) for value in values], capture_output=True,
                            text=True, timeout=timeout)
    (args.output / (name + ".stdout")).write_text(result.stdout)
    (args.output / (name + ".stderr")).write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"{name} failed ({result.returncode}); see {args.output / (name + '.stderr')}")
    return {"command": [str(value) for value in values], "exit": result.returncode,
            "seconds": round(time.monotonic() - started, 3), "stdout": result.stdout,
            "stderr": result.stderr}


def stability(args):
    baseline = args.baseline_source / "src"
    candidate = args.source / "src"
    if digest(baseline / "ast.h") != digest(candidate / "ast.h"):
        raise RuntimeError("stability fixture requires identical baseline/candidate AST schemas")
    prefix = ""
    for name in ("includes.h", "utils.h", "direct_input_trace.h", "small_vector.h",
                 "flat_map.h", "lexer_cache.h", "lexer.h", "ast.h", "type_queries.h"):
        prefix += '#include "' + str(baseline / name) + '"\n'
    prefix += '#include "candidate-gates.h"\n#include <cstdio>\nusing namespace goose;\n'
    prefix += 'static int passed;\nstatic void law(const char *, const function<void()> &test) { test(); passed++; }\n'
    prefix += '#include "' + str(TESTS / "stability_laws.h") + '"\n'
    (args.output / "probe-prefix.h").write_text(prefix)
    gates = (candidate / "type_queries.h").read_text()
    for name in ("StableTypeGraph", "StableCanContainGraph", "StableReachesGraph", "StableQueryProfile"):
        gates = gates.replace(name, "Candidate" + name)
    (args.output / "candidate-gates.h").write_text(gates)
    binary = args.output / "stability"
    built = command(args, "compile-stability", [args.cxx, "-std=gnu++20", "-O2", "-Wall",
                    "-Wextra", "-Wno-unused-parameter", "-I" + str(args.output),
                    TESTS / "stability.cpp", "-o", binary], 30)
    tested = command(args, "stability", [binary], 120)
    rows = [json.loads(line) for line in tested["stdout"].splitlines()]
    if rows[0]["laws"] != 166:
        raise RuntimeError("stability law inventory changed")
    (args.output / "stability-results.json").write_text(json.dumps(rows, indent=2) + "\n")
    return {"compile": built, "run": tested, "binary_sha256": digest(binary), "laws": 166,
            "scope": "actual AST/gates; modeled query leaves and synthetic timing only"}


def visited(args):
    expected = args.fixtures["visited"]
    source = args.source / "src"
    if digest(TESTS / "visited.cpp") != expected["fixture_sha256"]:
        raise RuntimeError("frozen visited fixture changed; re-extract and qualify its provenance")
    if digest(source / "ast.h") != expected["ast_sha256"]:
        raise RuntimeError("visited fixture AST schema changed; re-extract before claiming coverage")
    for item in expected["blocks"]:
        actual = block((source / item["file"]).read_text(), item["head"])
        if hashlib.sha256(actual.encode()).hexdigest() != item["sha256"]:
            raise RuntimeError("visited fixture source changed: " + item["head"])
    binary = args.output / "visited"
    built = command(args, "compile-visited", [args.cxx, "-std=gnu++20", "-O2", "-Wall",
                    "-Wextra", TESTS / "visited.cpp", "-o", binary], 30)
    tested = command(args, "visited", [binary], 30)
    if not tested["stdout"].startswith("laws 300\n"):
        raise RuntimeError("visited law inventory changed")
    return {"compile": built, "run": tested, "binary_sha256": digest(binary), "laws": 300,
            "scope": "source-extracted TypeEq/ordered traversal; controlled lazy/array-size leaves"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, required=True, help="candidate private compiler")
    parser.add_argument("--baseline", type=Path, required=True, help="previous reachable private compiler")
    parser.add_argument("--source", type=Path, required=True, help="candidate source root containing src/")
    parser.add_argument("--baseline-source", type=Path, required=True, help="baseline source root containing src/")
    parser.add_argument("--upstream", type=Path, default=ROOT.parent / "goose-to-wasm/build/source",
                        help="pinned upstream source root containing test/ and stdlib/")
    parser.add_argument("--stdlib", type=Path, help="override selected stdlib tree")
    parser.add_argument("--cc", type=Path, default=Path("/usr/bin/clang"))
    parser.add_argument("--cxx", type=Path, default=Path("/usr/bin/clang++"))
    parser.add_argument("--checks", nargs="+", choices=("semantic", "stability", "visited"),
                        default=["semantic", "stability", "visited"])
    parser.add_argument("--output", type=Path, default=ROOT / "build/goose-port/checker-tools")
    args = parser.parse_args()
    args.goose = args.goose.resolve(strict=True)
    args.baseline = args.baseline.resolve(strict=True)
    args.source = source_root(args.source)
    args.baseline_source = source_root(args.baseline_source)
    args.upstream = args.upstream.resolve(strict=True)
    if args.stdlib is None:
        args.stdlib = args.upstream / "stdlib"
    args.stdlib = args.stdlib.resolve(strict=True)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    args.fixtures = json.loads((TESTS / "fixtures.json").read_text())
    report = {"candidate_sha256": digest(args.goose), "baseline_sha256": digest(args.baseline),
              "candidate_source_sha256": builder.checked_source(args.source, None),
              "baseline_source_sha256": builder.checked_source(args.baseline_source, None),
              "stdlib_sha256": builder.tree_digest(args.stdlib),
              "tracked_sources": {str(p.relative_to(ROOT)): digest(p) for p in [
                  Path(__file__), Path(checker_semantic_controls.__file__),
                  *sorted(TESTS.iterdir())] if p.is_file()}, "checks": {}}
    if "semantic" in args.checks:
        for name, expected in args.fixtures["upstream_files"].items():
            path = args.upstream / "test" / name
            if digest(path) != expected:
                raise RuntimeError("upstream fixture changed: " + name)
        report["checks"]["semantic"] = checker_semantic_controls.run(args)
    if "stability" in args.checks:
        report["checks"]["stability"] = stability(args)
    if "visited" in args.checks:
        report["checks"]["visited"] = visited(args)
    path = args.output / "receipt.json"
    path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"receipt": str(path), "checks": list(report["checks"]),
                      "whole_compiler_qualified": False}))


if __name__ == "__main__":
    main()
