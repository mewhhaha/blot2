# Fast compilation: a modular direct backend

The long-term goal is 1M lines/s. The next milestone is a fresh Gdev Main
build under one second, from opening the compiler session through receiving
the complete Wasm with every module checked.

## Gdev Main, 18 November 2026

Blot `ea110ae6` builds a real lighting edit in **260 ms** and a fresh Main
in **1.578 s**. Both compilers below used Gdev `45748aba`, Ink `3f2e603` and
Pen `ad9766c`. Fresh builds include session startup, asset generation, checking
all 269 modules and receiving the complete 2,639,228-byte Wasm.
[Pinned measurements and raw trials](../benchmarks/evidence/measurements/2026-11-18-gdev-incremental.json)

| Operation, median | Previous compiler | Current compiler |
| --- | ---: | ---: |
| Fresh Main, 1 worker | 1,708 ms | 1,578 ms |
| Fresh Main, 4 workers | 4,475 ms | 1,808 ms |
| Edit the lighting preset in an open session | 1,625 ms | 260 ms |
| Reject an invalid lighting edit | 303 ms | 289 ms |
| Restore the last valid edit | 1,631 ms | 250 ms |
| Revert to the original source | 1,628 ms | 256 ms |

### Live edits

The session retains checked modules and Core from its most recent successful
build. A Boolean literal change inside a closed data initializer can stop at
the producer. The Gdev edit rechecked one module and lowered six bodies.
Ordinary function edits recheck the changed module and its transitive
importers. A change the session cannot prove safe takes the full path.
Failed edits preserve the last successful revision. The
[edit benchmark](../scripts/integration/time_gdev_edits.ts) compares all
successful outputs and rejection diagnostics against fresh sessions. Retaining
the results raised median process RSS after one cycle from 319 to 354 MiB.

### Fresh builds

Gdev now exposes station state and layout, robot data and picking, and salt
appearance through small ordinary modules. The number of transitive dependents,
including each producer, fell from 12 to 3 for station, 31 to 20 for robots
and 53 to 35 for salt. The compiler shares ownership traversal scratch across
queries and groups ready modules across checker processes. At four workers
the parent does one group's work. Forks fell from 269 to 60 and reply traffic
from 139.1 to 76.7 MB. One worker remains fastest on the measured host.

A fresh serial profile spent 1,057 ms checking, 192 ms lowering, 142 ms
loading, lexing and parsing, 102 ms emitting Wasm, and 69 ms on assets.
An isolated two-level grouping experiment reduced four-worker debug time from
6.544 to 6.299 s and raised reply traffic to 81.7 MB. Allocating type-list
scratch lazily cut pooled allocations by 9.2% without a repeatable wall-time gain. Both remain
outside the release.

The next cold-build experiment gives each long-lived worker its own checker.
It can publish a module's interface as soon as the checker finishes, then
lower that module while another worker checks its callers. An optimized
probe created, encoded and decoded all 269 interfaces and all 269 Core units.
Applying those measured costs to the import graph gives **0.770 s** with four
workers under ideal scheduling. That leaves **230 ms** for process coordination,
symbol handling, extra cross-module lookups and differences between live and
frozen imports. Time a fresh process through complete Wasm before adopting
the design.

## Goose release measurements, 17 November 2026

Gdev Main took **2.04 s** median on the ordinary one-worker path. All 264
modules were fresh and all runs produced the same 2,639,595 bytes. Two
frontend workers took 5.76 s and four took 4.99 s. The
[measurements](../benchmarks/evidence/measurements/2026-11-17-gdev-subsecond.json)
pin the compiler, sources, individual trials and output hashes.

Four fresh command-line builds used the same generated asset sources on
disk. They produced byte-identical Main and exposed these unprofiled medians.

| Stage | Time |
| --- | ---: |
| Load, lex and parse | 168 ms |
| Type check | 1,351 ms |
| Lower to Core | 220 ms |
| Emit Wasm | 112 ms |

### Architecture proposed on 17 November

Give each module an immutable interface for its callers and retain its
checked bodies in the existing Core IR. Keep mutable inference state local
to the checker that owns it. Use the same boundary for two milestones.

1. **A real edit under one second.** Keep the last successful module results
   in the open session. The lighting edit currently checks all 264 modules.
   Checking just its 70 transitive dependents, including the edited module,
   would still repeat 60–62% of checker CPU in two traces. Recompute the
   changed module, propagate changes to types, effects, ownership, dispatch
   choices and observed compile-time values, and stop when the facts a caller
   used are equal. Re-emit the full Wasm. Give declarations stable identities
   or fall back to a fresh check when their slots move. Test edit, rejection,
   recovery and revert against the same compiler's fresh bytes and diagnostics.
   The in-memory experiment can reuse Core owners. The portable dependency
   bundle hit `ArtifactLimit` on Main. [Incremental query precedent](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation-in-detail.html#improving-accuracy-the-red-green-algorithm)
2. **A fresh build under one second.** Build public interfaces from source
   before checking bodies. Pilot `ui/station`, `world/salt` and `actors/robots`,
   with explicit public constraints and inference inside each body. Let
   long-lived workers read the interfaces, check bodies and lower them into
   Core. Today's four-worker path forks 264 times in 29 batches and writes
   139,332,884 bytes of checked state through pipes. The pilot must charge
   header construction, worker coordination and result transfer to the measured
   build. Keep source-order diagnostics and check every declaration.

In two timing traces of the same import graph, publishing those three
interfaces early reduced the modeled longest serial chain from 36% to 22–23%
of checker work. In the second trace, the observed session took 1.930 s,
including 1.340 s checking. A four-worker schedule on the pilot graph took
350 ms in the model. Substituting that schedule gives **0.941 s** assuming
free interface construction and worker handoff. That leaves only 59 ms of
margin. Overlapping the roughly 220 ms of Core lowering can increase it.

Full type resolution accounted for 601 of 2,632 checker CPU samples across
four fresh builds. The composite cache's 326 hits in 1.09 million probes make
it a small A/B experiment. The architectural pilot addresses a larger share
of the build. [Samples, worker replies and scheduling inputs](../benchmarks/evidence/measurements/2026-11-17-gdev-architecture.raw.json.gz)

## Decisions (14 November 2026)

The owner approved all six changes below. The ownership model gets a later
review; until then keep it minimal and runtime-checked.

1. Ownership becomes per-function: no owner graph, aliasing partition or owner
   flags flow from a caller into a callee. Lifetimes are checked at run time by
   the existing owner epochs; scope release is decided from the function's own
   types and a boolean escape summary.
2. Module-level functions require complete signatures; locals stay inferred.
3. The checker records each call's type arguments; an instance is
   `(binding, type arguments)`.
4. Function values are runtime closures (table index + environment pointer).
   Saturated calls of named functions stay direct calls.
5. Every type has one fixed layout. Nothing is projected or chosen per call.
6. Blot does not inline. Wasm engines inline hot small functions; release builds
   may run `wasm-opt`.

## Why: measured costs

The following profile and implementation stages describe the earlier Zig
compiler. Its scoped backend took 6.6 s and produced 9.2 MB on that snapshot.

CPU profile of the Zig compiler (dynamically linked `-Dprofiling=true` build,
SIGPROF sampler) building Gdev Main, grouped by cause:

| Cause | Share |
| --- | ---: |
| Types re-derived per call: type-environment copy per plan, mapping, keys | 21% |
| Ownership tracked across calls: owner graph keys, borrow tracking | 17% |
| Frontend checking (parallel workers) | 19% |
| Inline-by-default emission, then outlining giant bodies | 11% |
| Per-call record layouts: reader-layout keys, projection, refinement | 6% |
| Plan construction, lookup and rollback | 5% |
| Post-assembly optimization passes | 4% |
| Callback identity in keys | 3% |
| Wasm emission itself | 12% |

The backend allocates 5.4 GB for 2.5 MB of source; memory copies are 13% of the
time. The largest 1% of functions hold 46% of the 8.9 MB code section. The
development tier currently emits identical bytes in the same time (6.9 s).

## Architecture

- **Instances.** `direct/` compiles each `(binding, type arguments)` once.
  Type arguments come from the instantiated type at the use node, matched
  against the callee's principal scheme, until the checker records them
  (decision 3). Concrete types are hash-consed `Ty` handles shared by all units.
- **Layout by type.** Unit has no words; Bool/U32 are i32; F32 is f32; tuples and
  records concatenate their fields in canonical field order; sum types are a tag
  word plus the widest payload; closures are two words; arrays, views, refs and
  links keep the data-stack descriptor words.
- **Calls.** Saturated calls of named functions are direct calls with flattened
  arguments and multi-value results. Partial applications and lambdas build a
  closure; applying a closure is `call_indirect` with the environment first.
- **Memory.** The data-stack runtime (owner table, epochs, regions) is kept and
  re-emitted by the direct backend. A scope whose result type holds no owner,
  view or closure rewinds what it created; a function that may store a fresh
  owner into older storage keeps its allocations for the enclosing scope.
  Exports reset temporaries on entry, as today.
- **Output.** A lean Wasm writer encodes bytes directly: multi-value results, a
  function table for closures, the ABI 8 exports, imports and `blot:abi`.
- **Parallelism.** Emission per instance has no shared mutable state besides
  the instance table, so it can run on all cores; final indices are assigned in
  a deterministic order at link time.

## Status (14 November 2026)

Phases 1–3 are done behind `--backend direct` (CLI, project protocol,
`serve-project`, `build_gdev.ts`). Gdev Main compiles to 2,741,651 bytes
(scoped: 9,203,490) and its first Pen frame is byte-identical to the scoped
backend's (frame.png 19a03f0a…, frames.trace 86d50101…). On one native
(`-Dllvm=false -Doptimize=fast`) compiler the backend takes 1.2 s against
43.5 s; checking now dominates. `tests/guest/direct_backend_execution.test.ts`
runs every fixture in `compiler/fixtures/direct/`.

What the direct backend does beyond the plan above:

- Generic bodies are typed from their values: each instance's environment is
  refined by matching every expression's Core type against the type it
  produced; a callee or lambda whose result only its body fixes is emitted
  first; function-valued arguments are typed by what the callee expects,
  including its field constraints on a still-unknown argument.
- Values wider than 16 words are boxed (a pointer to an immutable copy).
- A function stored in a literal record at a type no use fixes (a codec's
  `encode` at a restore site) becomes a closure that traps if called.
- Unsupported forms are listed together with counts and sample locations.

Gdev needed three annotations (the `version` parameters of three codec
`migrate` functions, committed in ../gdev).

On a release (LLVM) compiler, Gdev Main builds in 1.15 s against 6.61 s. The
backend's share is 95 ms against 5,533 ms, so the frontend is now 90% of the
time.

Ink's suite (`pen test-blot` through a `--backend direct` wrapper) matches
the scoped backend on all 64 modules both compile, with identical outcomes.
The direct backend also passes extractions, retained and simd-batches, which
the scoped backend rejects.

## Sequencing (owner, 14 November 2026)

1. Phase 6 first (done 14 November 2026, tasks/DELETE_SCOPED.md): the direct
   backend becomes the only backend, and the scoped backend, `eval/`, the
   scoped `runtime/` and the reuse machinery built around scoped artifacts
   are deleted.
   - Tests of scoped internals go with the code.
   - A test that only exercises a feature on the approved removal list in
     tasks/LANGUAGE_COHERENCE.md goes with that feature.
   - Kept features the direct backend lacks are implemented there.
   - The checker's eight shared `backend/` modules (`collection_ops`,
     `scalar_ops`, `simd_intrinsics`, `opaque_storage`, `loop_targets`,
     `function_facts`, `runtime_identity`, `wasm`) move to a neutral place
     or are cut.
2. Then tasks/LANGUAGE_COHERENCE.md, memory model (item A) first, together
   with phase 5's frontend work.
3. Phase 7 (Goose port) last.

Run-time cost, measured with `pen bench` and `pen packets`
([evidence](../benchmarks/evidence/measurements/2026-11-14-direct-gdev-runtime.json)):
- Gdev Main's guest time per frame is 0.079 ms median on the direct backend
  against 2.45 ms on the scoped one; state snapshots take 0.46 ms against
  16 ms, and loading takes 3.2 s against 5.8 s.
- The 120 frames' render packets and the final snapshot are byte-identical.

No run-time reason remains to keep the scoped backend for release builds;
`wasm-opt` stays optional.

## Phases

1. Scalars, records, tuples, nominal data and `case`, blocks, `if`, loops,
   direct and curried calls, generics and closures. Executed Deno tests on
   fixtures, selected by an explicit backend option.
2. Arrays and `@storage`, views and refs, indexed updates, array loops,
   persistent pools, constants, Foreign callbacks and packets. Ink's tests pass.
3. Gdev Main compiles; its first Pen frame matches the scoped backend's PNG.
   Measure lines/s and Wasm size.
4. Parallel emission and lean allocation toward the 45 ms budget.
5. Frontend: recorded instantiations, required signatures (migration tool and
   std/Ink/Gdev migration), parallel body checking.
6. The direct backend serves both tiers (release adds `wasm-opt`); remove the
   scoped backend, plan/evidence machinery and outlining.
7. Port to Goose.

Check each phase with `deno task check:dev`, `deno task lint:zig` and its own
executed tests; run `deno task test:compiler` on the final candidate.
