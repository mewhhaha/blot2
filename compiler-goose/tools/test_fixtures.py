#!/usr/bin/env python3
"""Build every program of compiler-goose/tests/fixtures and compare with the record.

tests/fixtures/expected.json holds, for each program, what the Zig compiler
gave on 15 November 2026, the day it was removed: the exit code, the SHA-256
and size of the Wasm, and the JSON records without clocks, memory counts and
`symbol_bytes` (which counts the absolute path). The `differences` table holds
reviewed work-counter changes beside their original values. Reusing unchanged
types during substitution reduces `type_nodes` and, for two programs,
`effect_rows`. The recorded diagnostics and Wasm are unchanged.

The record of `direct/boxed_records.blot` is this compiler's (16 November
2026): an update that leaves a boxed record's words as they were keeps its
block, and a loop that carries a boxed value releases an iteration's memory
when the value came out as it went in. tests/guest runs the program.

The ABI 8 invocation-finish extension (17 November 2026) re-recorded the Wasm
bytes and function counts of exported programs. The audit compared the same
sources before and after the change: it added the hook, its optional ABI
section and any required signature without changing existing function bodies.

Blot vNext Checkpoint 2 (21 November 2026) re-recorded `direct/boxed_records.blot`
(3764 -> 3728 Wasm bytes): provably unique boxed records/sums reuse their block
in place on single-use updates (FBIP), eliminating one `newBlock` + `memoryCopy`
in `nested` while preserving aliasing safety in `fields`.

Runtime performance Checkpoint R1 (22 November 2026) re-recorded the Wasm bytes
and emitted function counts of 51 direct-backend fixtures: scoped `CheckedArray`
/ `CheckedGrow` / `CheckedView` handle hoisting, in-place owner loop carries,
method-call `apply(project(...))` unwinding, single-op array/storage forwarding,
`createUninit` + dynamic repeated-byte `memory.fill`, inline `storage.push` fast
path, zero-allocation `continue` release skipping, and zero-copy pure entry
packet input. All exit codes, diagnostics, and frontend counters are unchanged.

Runtime performance Checkpoint R2 (22 November 2026) re-recorded the Wasm bytes
and emitted function counts of 36 direct-backend fixtures: small pure leaf
function inlining (preserving caller CheckedArray/CheckedView descriptors),
bulk contiguous slice/array-to-GrowArray push loops (`memory.copy`), small
constant-array `for` loop unrolling, compile-time constant-tag `match` arm
pruning, direct inline emission of non-exported scalar and nullary-constructor
constants, and the `noStorageResize` `Tag.construct` traversal fix. All exit
codes, diagnostics, and frontend counters are unchanged.

On-demand linear memory Checkpoint A (22 November 2026) re-recorded the Wasm
bytes and emitted function counts of 98 direct-backend fixtures: initial memory
starts at 1 Wasm page (64 KiB) with `memory.grow` up to the planned budget,
2-level paged owner directory, chunk-list scratch stack with loop-free
`rewind_stack` fast path and guarded `releaseTo`, and lazy transport/undo
buffers. All exit codes, diagnostics, and frontend counters are unchanged.

Batch 1C (22 November 2026) retired `List` / `@cursor` / `std/list` /
`std/iter`, `@requests` / `yield` / `complete`, `do (monad ...)`,
`@record.merge`, custom fixity declarations / backtick operators (replaced by
the fixed 19-operator built-in table with direct dispatch), and `lent`. The 80
fixtures exercising retired features were removed (109 fixtures remain) and
expected.json was re-recorded against the slimmer `std/prelude.blot` and direct
operator lowering.

Batch 1D (22 November 2026) collapsed `reuse/dependency_payload.goose` via
`write_dependency_payload.py`, slimmed worker interface replies, restored
direct `Tag.scalar` / `Tag.associated` lowering for built-in scalar operators
(`!=`, `<=`, `>`, `>=`, etc.), and taught `core_builder.goose::directArity` to
recognize primitive intrinsic aliases (`const F32.add = @f32.add`, etc.). All
109 fixtures kept identical exit codes and diagnostics while shedding 131
`std/prelude.blot` Core nodes and eliminating closure allocations / indirect
calls in scalar comparison and prelude math helpers.

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
