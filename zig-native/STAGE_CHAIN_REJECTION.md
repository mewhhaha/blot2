# Stage-chain rejection

Task 099 keeps inference-budget exhaustion a positioned rejection through
project export handling. It adds no budget setting or semantic shortcut.

A public reduction builds a record with 64 arithmetic callbacks and a U32 field.
Each stage reads that field and calls the previous stage:

```blot
const holder = fn () => #{ f0: fn x => x * 2.0 + x / 3.0, g: 4 }
const s0 = fn () => (holder ()).g
const s1 = fn () => (holder ()).g + s0 ()
entry const e = fn () => s1 ()
```

The regression generator in
[tests/stage_chain_budget.test.ts](tests/stage_chain_budget.test.ts) expands
this to 64 callback fields and 51, 52 and 64 stage links. With the default
one-million-step module budget, 51 links compile at 974,824 inference steps; 52
links exhaust the budget. Before the fix, both CLI and retained server crash
with signal 11. Gdb identifies `project_check.Engine.moduleExports` as slicing
an empty nominal table with `[1..]`.

The checker already discards its partially inferred engine and returns one owned
`inference_budget` diagnostic. That rejected result has empty nominal,
constructor and effect-family tables. Export handling now iterates each whole
table and skips index zero when present. Valid-module export indices retain
their meaning; empty rejected tables publish no declaration exports and keep the
existing diagnostic. Rejection and recovery use the existing owner paths.

## Qualification, 11 October 2026

Implementation revision: `5340ef2`. Baseline: `c226967` (unchanged export loops
through task 097's `f2b41b4`). Zig 0.17.0.

- A focused native law exhausts a zero-step private module budget, confirms all
  three catalogs are empty, and verifies zero exports plus the same owned,
  positioned project diagnostic. It passes in the development build.
- CLI laws pass at 52 and 64 links: exit 1, one positioned `inference_budget`,
  no Wasm publication and zero live requested memory after teardown.
- Server laws pass at 51, 52, 64 and recovery to 51 links. Both rejected
  revisions agree with independent fresh sessions. Recovery preserves Wasm bytes
  and the executed result, 204.
- `deno task test:compiler` passes the full native suite and 653 guest/client
  tests.
  `ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`
  reports zero findings across 315 files.
- Successful 51-link control preserves all checker counters and its 13,077-byte
  Wasm exactly. Its checker still takes 974,824 inference steps.
- The private gdev split-hauling fixture now reports a positioned
  `inference_budget` and exits 1. It remains uncompiled; it no longer crashes.

[Binary pins and control measurements](qualification/stage-chain-rejection-pins.json)
preserve the comparison. The successful control is one pair under uncontrolled
host load and concurrent native-test builds; its timing establishes no speedup.

This fixes crash handling. Large unresolved callback chains can still exceed
inference's existing work budget. Their cost and general summary admission are
separate compiler work; no compile-time speedup is claimed. Task 097 remains
open until its outstanding reported-fixture compilation is qualified.

## Scheduling follow-up

Task 097's `881c6ab` removes unsuccessful selection retries. The same public
51-stage control now takes 269,363 steps; 100 stages compile and 101 still
reject without crashing. The executable budget regression now uses that
boundary. The blocked fixture compiles and executes successfully; task 097's
fixture gate is complete. See [PENDING_SELECTIONS.md](PENDING_SELECTIONS.md).
The earlier measurements above remain the historical qualification of `5340ef2`.
