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

Concurrency vNext Phase 1 (22 November 2026) added represented opaque `Kernel`
and `Process` handle types to `std/prelude.blot` (+231 source bytes, +26 syntax
nodes, +17 type nodes), reserved the `spark` keyword, added `entry kernel` /
`entry process`, wire-schema / relational read-only purity analysis, and fixed
`k == 1` record-payload constructor/pattern lowering. All 109 fixtures kept
100% identical exit codes, diagnostics, and emitted Wasm bytes.

Concurrency vNext Phase 2 (23 November 2026) added 4-wide Wasm SIMD (`v128`)
auto-vectorization for `spark` (`direct/function_spark.goose`), body-scoped
`offset = -2` `unpatchableOperand` relocations, `#run` `Tag.spark` staging,
and uniform producer-site `0x7fc00000` NaN canonicalization on F32 arithmetic
and rounding ops (`+`, `-`, `*`, `/`, `sqrt`, `floor`, `ceil`, `trunc`) with
safe consumer peephole elision. Re-recorded the 14 fixtures containing F32
arithmetic/rounding (+13 bytes per non-elided F32 op); all 109 fixtures kept
identical exit codes, diagnostics, and frontend counters.

Concurrency vNext Phase 3 (23 November 2026) upgraded `direct/runtime.goose`
with history-independent logical stack/heap budgets (`stack_live_bytes`,
`heap_live_bytes`), exact-cap active-only stack free lists (`stack_free_32k`,
`stack_free_large`), dedicated transport pool (`alloc_transport`,
`open_transport_pin`, `free_transport`, `detach_temp_slot`) with Page-0 offset
640 `arena_oom_flag`, `live_flag` / `static_pool_flag`, inter-procedural
`escape_min_slot`, box-aware `@simd.load`/`@simd.store`, trap-safe `fork`,
iterative persistent state staging (`direct/function_persist.goose`),
physical-stride `FlatNumeric` codecs + `entry kernel`/`entry process` ABI 8
wrappers (`direct/function_kernels.goose`), and full `LayoutReceipt` retained
build gating. Re-recorded the 92 direct-backend fixtures (+6 runtime helpers
and updated runtime bytes); all 109 fixtures kept identical exit codes,
diagnostics, and frontend counters.

Memory Model Phase 4 (23 November 2026) implemented the full value restriction
for `let` (`check/check.goose`: only a syntactic `func` generalizes; plain
`let` bindings still settle pending field requirements via `solveFields`) and
fixed direct-backend polymorphic local capture instantiation
(`direct/function_calls.goose::captureValue` now scans the capturing closure's
body under `f.env` and instantiates in a temporary copy of `f.env` instead of
caching into `f`'s monomorphic bindings). Re-recorded `expected.json`:
`discard-fixtures/original.blot` now exits 1 (`unresolved type variable` on an
unannotated unused tuple of generic constants), `discard-fixtures/deferred-anonymous.blot`
and `deferred-body.blot` now report `missing_member` at check stage instead of
`storage_unsupported` in emit, `discard-fixtures/deferred-alias.blot` exits 0
on its dead unreferenced alias tuple, `result_selected_operand.blot` drops from
45 to 43 emitted functions, `discard-fixtures/runtime-panic.blot` drops from 35
to 34 functions, and `direct/closures.blot` keeps monomorphic `let wrap = $Some`.

Unified Dynamic Arrays Phase 5 (24 November 2026) removed `#[+T]`/`#[~T]`/
`GrowArray`/`ResizeArray`/`seal`/`@storage.freeze`/`@storage.reserve`, unified
all dynamic arrays onto `Array T` (`#[T]`), hardened `Tag.array` backend
invariants (heap promotion, `fork` journaling, checked-array invalidation,
`escape_min_slot` promotion), and enforced `ownedInPlacePath` on
`@storage.push`/`@storage.pop`/`@storage.truncate`. Re-recorded `expected.json`
for all 109 fixtures (migrating legacy grow/resize/freeze fixtures to `Array`
and `own`-threaded helpers; `global_call_freeze.blot` now exits 1 with
`aliased_update` on mutating an aliased module `const` array).

Unified Dynamic Arrays Phase 6 (24 November 2026) retired `check/purity.goose`
and its diagnostic codes (`spark_mutates_capture`, `kernel_mutates_context`,
`process_mutates_global`, `purity_limit`) since ownership now guarantees all
module `const` pools are deeply immutable, unconditionally emitting `mode = 2`
(`static_pool_flag | live_flag`) for every module `const` pool. Re-recorded
`expected.json`: 100 of 109 fixtures stayed byte-identical and the 9 fixtures
with module `const` pools changed only `wasm_sha256` (same byte sizes, exit
codes, and records).

Runtime performance Tier 4 (25 November 2026) added deferred F32 NaN
canonicalization on pure-FP counted loops (4A), variant tag-store skip and
pre-loop `CheckedLe` bounds hoisting (4B), 4×v128 register-blocked matmul
k-loop tiling + descending `48,32,16,0` BCE-coalesced SIMD lanes (4C),
`CheckedGrow` reuse + depth-3/`spark` inlining + loop-depth-scoped
`unique_owned` forwarding (4D), and exact `2.0*x -> x+x`, 2× scalar `for ever`
unrolling, and 4× strided fill (4E). Re-recorded `expected.json`: 8 of 109
fixtures changed Wasm bytes/SHA (6 smaller via `CheckedGrow` reuse/`2.0*x`,
2 same-size SHA changes, `scoped-loop-cleanup.blot` +81 B from `CheckedLe`);
all exit codes, diagnostics, and work counters are unchanged.

Runtime performance Tier 5 (25 November 2026) added branchless `select` indexed
updates, short-circuit `or`-break, `memory.copy` copy-tail loops, invariant
2-way merge `k < dst_len` hoisting, and deeper loop-bearing helper inlining
with interprocedural handle preservation (5A); intra-element `v128` SIMD for
16-byte `Maybe Vec3` updates and pre-loop indirect-index bounds scans (5B);
2-row × 16-col (`8 × v128`) register-blocked outer-row matmul tiling (5C);
16-wide `v128` SIMD masked/unmasked `U32` reductions (5D); 4-pixel `v128`
outer-loop escape-time SIMD with `v128.any_true` early exit and SIMD `2.0*x`
strength reduction (5E); and 16-wide (`4 × v128`) SIMD affine LCG recurrence +
8× scalar parallel-power unrolling (5F). Re-recorded `expected.json`: 107 of
109 fixtures stayed byte-identical; 2 shrank from deeper inlining
(`fixed_scalar_spans.blot` 48→47 funcs / 8764→8726 B;
`scoped-loop-refinement.blot` 47→46 funcs / 10393→10286 B) with zero exit-code,
diagnostic, or frontend work-counter changes.

Agent Diagnostics (25 November 2026) added secondary blame origin fields
(`origin_kind`, `origin_start`, `origin_end`, `subject_start`, `subject_end`,
`holder_start`, `holder_end`) to rejected lowering diagnostics via
`blot_check_uniqueness::explain` on error paths. Re-recorded `expected.json`:
107 of 109 fixtures stayed byte-identical; only the 2 rejected lowering
diagnostics (`global_call_freeze.blot` and `mutating_owner_return_truncate.blot`)
gained the new blame span fields with zero exit-code, Wasm, or counter changes.

Track 2 & Track 4A/4B (25 November 2026) extended `--wasm3` with indirect
closure tail calls (`OP_return_call_indirect` `0x13`) and relaxed SIMD
min/max/trunc (`f32x4.relaxed_min`, `f32x4.relaxed_max`,
`i32x4.relaxed_trunc_f32x4_{s,u}`), added generalized `#[n; T]` dependent
equal-length and post-trap bounds-check elimination (`CheckedBound.sized_len_ty`
in `direct/function.goose`, `direct/function_control.goose`,
`direct/function_storage.goose`), and added generalized AoS `#[Vec2]`/`#[Vec4]`
record auto-SIMD (`tryEmitAosF32RecordLoop` in `direct/function_spark.goose`).
Re-recorded `expected.json`: 106 of 109 fixtures stayed byte-identical; 3
fixtures strictly shrank from redundant bounds-check removal
(`fixed_scalar_spans.blot` 8726->8717 B, `primitive-aliases.blot`
13165->13138 B, `scoped-loop-cleanup.blot` 9643->9634 B) with zero exit-code,
diagnostic, function-count, or frontend work-counter changes.

Language Audit Waves 1-3 & Trap Provenance (25 November 2026) fixed type,
trait associated-output, `traitIsReadOnly`, `is opaque` reflection, `fork`+`with`
`Foreign`, uniqueness (loan undo trail, generic `#for`/freeze/copy, `with`
record/cell/fork soundness), FBIP/linearAppend aliasing, SIMD incremental
relocation (`unpatchableOperand`), `#run`/`#if` associated `eq`/`ne`,
`defer_f32_nan`, `@simd.store` cache invalidation, `let ... else:`/`#for`
carries, `std/text` exact `from_f32`, `r.create` overflow + `static_pool_flag`
guards, `Code.no_entry` for entry-less builds, and `"blot:traps"` v1 / Page-0
offset `772` trap metadata. Re-recorded `expected.json` (109 fixtures, zero
exit-code changes; 9 library-only fixtures updated from `storage_unsupported`
to `no_entry`; uniform `+4 effect_rows / +13 type_nodes` and `+29B` runtime
guard deltas).

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
