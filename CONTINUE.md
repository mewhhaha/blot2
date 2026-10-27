# Continue the Goose K1 rewrite

Worktree: `/home/mewhhaha/.codex/worktrees/0409/blot2`, branch `rewrite/goose-k1`.
Draft PR: https://github.com/mewhhaha/blot2/pull/43, targeting `main`.
The user requested the draft PR, then a bounded runtime performance pass with Sol
review. The PR was opened after pushing `900ede2`; the bounded runtime follow-up
and the requested direct comparison against main are complete and recorded below.
Sol also reviewed the new benchmark's equivalence and boundary handling.
All agent lanes are frozen,
all required checks and measurements are complete, and no jobs remain running.
Do not continue an open-ended optimization search without a new user request.

Read [the direct main comparison](benchmarks/MAIN_COMPARISON.md),
[the previous/new K1 runtime results](benchmarks/RUNTIME.md),
[implementation ledger](IMPLEMENTATION.md), [contracts](docs/CONTRACT.md) and
[normative snapshots](docs/spec/INDEX.md). The earlier
[structural](benchmarks/STRUCTURAL.md) and [parity](benchmarks/PARITY.md) reports
remain immutable historical evidence.

## Current qualification

The release gate passed **116 native entries, 92 Deno tests, editor scopes and
29 formatter round trips**. Input manifest:
`27e9627f595ffe94ff0a2955c600ef977cd1262638152326700716c8fb85d67e`.
Compiler SHA-256:
`94b3d24012f8868a8eb7e8e6351edcfea9529c3d7de36845d10b0b2e47f032bd`.
[Current evidence](benchmarks/results/runtime/manifest.json) pins all 197
qualified inputs, full gate logs, baseline inputs and 228 measurement records.
Source and binary hashes remain identical to the passed gate. Historical
packages and snapshot-specific packagers must not be overwritten or rerun
against a different candidate.

## Completed runtime pass

Exactly two mechanisms were selected after Sol review:

- Frame planning shares the register-edge predicate with emission and omits
  physical phi scratch for those edges. Nonflat parallel-copy fallback and
  independent Owned-seal scratch remain. The plain F32 loop body drops from
  138 to 93 Wasm bytes and from eight frame bytes to zero. Conservative certified
  body bounds, source admission and public contract preflight remain unchanged.
- Four-byte copies use integer load-before-store. Dynamic sizes select that
  path for four bytes and otherwise keep bulk copy, including zero; known other
  fixed sizes remain unchanged. Size calculation precedes scratch spills,
  F32 bits and overlap behavior are exact, telemetry counts once, and argument/
  result slots remain distinct. Shared generic bodies and the ABI are unchanged.

One native fixture, three copy execution laws and one phi execution law cover
0–256-byte copies, unaligned overlaps, signed-zero/NaN words, bounds failure
without partial writes, typed generic/fixed paths, exact counters, simultaneous
mixed/F32 swaps, nonflat edges and conservative envelope rejection. The full
existing ownership, generic, adapter, artifact, cancellation and OOM corpus passed.

## Results and stopping point

Five counterbalanced pairs of five loop kernels run each Wasm artifact in a
fresh Deno process. Both compiler versions use `--opt=off`; this is independent
of the earlier inlining work. Default V8 and optimizing-only controls stay separate.
Each call executes 1,024 integer or 128 F32 iterations, with varying seeds, exact
reference results, 20,000 warmup and 20,000 timed calls.

Generic integer recurrence improves from 5.795 to 1.267 microseconds per kernel
call in default V8: paired ratio 0.220, about 4.5× faster. Optimizing-only ratio is
0.206, about 4.9× faster. Generic F32 paired ratios are 0.813/0.847, about 15–19%
less time. Ordinary kernels and the eight-byte aggregate fallback remain roughly
unchanged. Nine compile controls give paired ratios 0.959–1.023, with no established
compile-time change. All samples/ranges are retained; CPU placement/load/frequency
and cache remain uncontrolled. That pass did not compare against main; the
separate follow-up below now does. No new gdev measurement was made.

The selected changes passed and have useful measured results. Stop here rather
than tuning these kernels further. The initial release inliner remains qualified
but its earlier general runtime benefit is unresolved; no inlining limits changed.

## Completed comparison against main

The requested follow-up compares this exact qualified K1 with main `1e39b5d`
using its installed hash-matched release `fd2119f5…`. Both committed main
provenance blobs are archived. No compiler inputs or binaries changed.

Five counterbalanced pairs, two fresh-engine modes and nine compile families
produce 209 records under `benchmarks/results/main-comparison/`. Ordinary loops
are near parity. Generic integer takes 1.13–1.20× main's time, generic F32
3.61–4.24×, generic pair 6.40–6.55×. Call-chain/closure/diamond/generic compilation
is faster in every measured pair, while proof guards and static domains take
about 13% and 71% more time. All paired ranges remain visible in the report.
K1 uses `--opt=off`; main uses its default pipeline. Required ownership hooks
are included where exported (main's pair fixture). No retained-session or
compiler rebuild comparison was added. The bounded comparison is complete;
no optimization search follows automatically from these regressions.

## Earlier work and reproduction

The prior structural pass borrowed validator Core views, replaced proof SCC
search with iterative Tarjan, and added bounded release inlining. It reduced
fresh compile time roughly 7–15% against the preceding K1 and retained body edits
from 6.96 to 6.29 ms. Its off-tier Wasm was byte-identical before/after. Previous
legacy numbers belong to that snapshot, not the new runtime candidate.

Pinned Goose: `/tmp/blot-k1-goose/build/goose`, commit
`a108677d300cb0e8bbb842c35a353abe67a20c6c`,
`GOOSE_HOME=/tmp/blot-k1-goose-home`. Bootstrap can recreate it.
Compiler changes require the complete `scripts/check.sh --release` gate.
Current compiler is `build/blot`; the preserved runtime baseline is
`build/runtime-pass-baseline/blot` (`ca49141e…`) with complete input/gate snapshots.
Earlier preserved binaries and hashes are documented in historical reports.

The runtime orchestration and structural inspection are archived from
`build/run_runtime_pass.py` and `build/runtime-pass-attribution/inspect.py`.
Public harness/model/worker files live in `scripts/`. Compiler rebuild-time and
retained-edit timings were not rerun for this runtime pass.

The user authorized committing/pushing for the draft PR. No installation, merge
or issue closure is part of this task; do not replace the installed compiler,
merge the draft or close #37 without a new instruction.
