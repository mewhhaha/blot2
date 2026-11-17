# Continue the Blot ownership conversion

## Current task

Finish the save/restore conversion already on main. A writer takes its world
with `own` and returns the successor. Rebind that successor before reading,
encoding or passing the world on. The two Gdev decoders now return
`(report, access)`. A caller that only needs the report can discard the
returned world. Keep the saved lanes, trap behavior, packet order, ABI 8
and session protocol 2.

The compiler in this checkout is the Goose compiler with the direct backend.
The Zig source was retired in November. The compiler port and the old scoped
backend are historical work. The long-term compilation goal is one million
lines per second. The current integration task is the owned-world migration.

## Starting point on 17 November

| Checkout | Revision | What it supplies |
| --- | --- | --- |
| blot2 | `1ff5c88e` | Goose compiler and ownership rules |
| pen | `1dfca8a` | Explicit-owner generated encoders and program loop |
| ink | `15b107a` | Save, scene history and host decoder changes |
| gdev | `78abf6b` | Game, fixtures and partially converted callers |

At these revisions, a source search finds ten calls that still pass an output
buffer to `world.decode_state` or `world.decode_scene`:

| Gdev file | Calls |
| --- | ---: |
| test_support/rocket_mornings.blot | 1 |
| test_support/traps_codec_rejects_fixture.blot | 3 |
| tests/codec_saved_state.blot | 3 |
| tests/restore_game.blot | 2 |
| performance/sparse-stream.blot | 1 |

Follow the changed helpers into their callers. Code executed after a restore
must observe the returned world. The sparse-stream performance entry needs an
explicit check in addition to the test suite. The previous handoff reported
219 of 231 entries checked and a matching 120-frame packet run partway
through the conversion. Those observations predate the finished callers.

## Verify this batch

1. Build from the pulled sources. `deno task test:compiler` builds the release
   compiler used by Pen and runs the tooling, reference, packaging, guest and
   host checks. Build Pen with `cargo build --release -p pen` in its checkout
   and its plugins with `cargo build --release --target wasm32-wasip2` in
   `../pen/plugins`. An existing local executable can predate the pull.
2. Run the affected Gdev tests and the sparse-stream entry using the current
   compiler. Check the main and devtools entries, generated bindings and both
   sibling suites. From each project the suite command is
   `../pen/target/release/pen test-blot`.
3. Compare per-module outcomes and individual failing tests. The preceding
   source pair is Gdev `e431d43` and Ink `719e0c7`, with the same Pen.
   Historical totals were Gdev 391 passed, 67 failed and 107 modules that
   did not compile, and Ink 268 passed, 1 failed and 3 modules that did not
   compile. The scratch comparison script and log from the original machine
   are untracked. Export the two revisions into a temporary sibling layout to
   reproduce a reference when those logs are absent.
4. Compare Gdev's full `pen packets DIR --frames 120` outputs with the same
   inputs on both source pairs. Use `pen bench --runs 3 --frames 300 --json`
   for the short benchmark and `pen bench --runs 1 --frames 200000 --json`
   for the retention regression. Inspect a fresh first frame from the actual
   game using the [integration runner](scripts/integration/run_pen.py).
   [Earlier runtime measurements](benchmarks/evidence/measurements/2026-11-16-owned-world-runtime.json)
   give the workloads and their original results.

## After save/restore

Continue top-down through functions returning a value beside the world,
capturing closures, the hooks record and Ink's editor chain. Then convert the
Ink library writers used by Gdev. Ink's physics conversion is recoverable at
`58e6b02`. Its physics edits were reverted in `719e0c7` after the owned step
exhausted the stack in `tests/prepared-physics.blot`. Restore that family once
the backend can release iteration temporaries while retaining new allocations
carried into the next iteration.

The starting source count is **1,561 candidate stores and 55 lent functions**
across Ink lib/tests and Gdev src/tests/test_support/devtools/performance.
The [counter](scripts/integration/count_stores.py) estimates stores by line
shape. Keep the transition syntax until remaining users are migrated, then
remove the mutation form of `=`, `lent`, `migrate-stores` and the reporting
switches, and reconcile spec §10.3. Declaration `let x = …` stays.

The [memory model](tasks/MEMORY_MODEL.md) records ownership decisions and
known checker/backend limits. The [language approvals](tasks/LANGUAGE_COHERENCE.md),
[compiler port record](tasks/GOOSE_PORT.md), [compiler build guide](compiler-goose/README.md)
and [compile-speed plan](tasks/FAST_COMPILE.md) retain the wider work. The
full pre-review handoff is in Git at `1ff5c88e:CONTINUE.md`.
