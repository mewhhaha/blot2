# Fast compilation

The long-term goal is one million source lines per second. The Gdev milestone
measures a fresh process from project session open to receipt of complete Wasm.

## Gdev Main, 18 November 2026

Blot `d92d35ac` compiled the 46,109-line project in **938 ms** median over
twelve fresh processes, about **49,100 lines/s**. A lighting edit took
**291 ms** median. On the same sources, an unused `#run` fell from **1,938 to
1,031 ms**. Using it for the actual lighting field took **1,015 ms** and
emitted byte-identical Wasm. All 269 modules used the worker queue.
[Measurements, compiler identities and probe inputs](../benchmarks/evidence/measurements/2026-11-18-gdev-staging-interfaces.json)

![Fresh Gdev compile times with ordinary and staged lighting](../benchmarks/evidence/measurements/2026-11-18-gdev-staging-interfaces.svg)

### Earlier worker release

Blot `20fed713` took **0.889 s** median on fresh Main and **268 ms**
on a lighting preset edit in an open session. Each of six fresh builds checked
all 269 modules, emitted the same 2,639,228 bytes and finished in 870–910 ms. Both defaults used Gdev `45748aba`, Ink `3f2e603`
and Pen `ad9766c` on the same shared eight-core Linux host.
[Measurements and raw trials](../benchmarks/evidence/measurements/2026-11-18-gdev-compiler-workers.json)

| Operation | Previous default | Current default |
| --- | ---: | ---: |
| Fresh Main | 1,691 ms | 889 ms |
| Lighting preset edit | 270 ms | 268 ms |
| Reject an invalid lighting edit | 303 ms | 403 ms |
| Recover the last valid edit | 263 ms | 273 ms |
| Revert the lighting preset | 266 ms | 269 ms |

Fresh trials opened a new native process, regenerated assets and checked every
module with warm filesystem pages. The edit trials alternated previous and current
compilers and compared successful bytes and rejection diagnostics with fresh sessions.

### Where fresh time goes

Seven forked workers and the parent check dependency-ready modules. Each
publishes its interface as soon as it is ready, then lowers the checked body to
Core. Importers decode each producer once per worker. The coordinator restores
the budget debits in source order and assembles the complete Wasm.

In a separate traced build, checking and worker-side lowering took
447 ms, gathering Core took 54 ms, loading and parsing took
156 ms, assets took 73 ms and the Wasm backend took 113 ms.
The serial trace spent 1,119 ms checking and 207 ms lowering.
Sending the largest Core tables as verified Goose arrays reduced worker replies
from 75.0 MB to 72.9 MB. With the same scheduler it reduced fresh time from
0.914 s to 0.889 s on these six pairs.

### Edits and remaining costs

A successful build retains the interfaces, inference-budget debits and Core it
needs for the next edit. A closed-record Boolean edit checks one module and
reuses 268. Restoring the last successful revision after rejection reuses all
269. Rejection falls back to the source checker for the ordered diagnostic.
In the measured cycle, the compiler process ended at
212 MiB RSS, compared with 354 MiB previously.

Changing the body of a public lighting function produced different Wasm and
rechecked 72 modules in **1.11 s** median across the edit, revert
and repeat. Comparing the changed module's exported interface before checking
its importers could reduce that work. The source splits already reduced the
inclusive dependent count for station from 12 to 3, robots from 31 to 20 and
salt from 53 to 35.
[Source split and serial edit measurements](../benchmarks/evidence/measurements/2026-11-18-gdev-incremental.json)
· [Worker prototype and rejected experiments](../benchmarks/evidence/measurements/2026-11-18-gdev-persistent-workers.json)

### What one million lines per second would take

Main has 46,109 physical source lines, including 314 generated lines. The
889 ms release median is **51,890 lines/s**. One million lines/s on this input
allows **46 ms** to receive complete Wasm. The release trace spent 434 ms
outside parallel checking and worker-side lowering. In a separate, slower
timing window the same binary took 2.48 s with one worker, 1.30 s with eight
and 1.50 s with sixteen on eight physical cores.
[Worker scaling graph](../benchmarks/evidence/measurements/2026-11-18-gdev-multicore.svg)
· [Source counts and raw trials](../benchmarks/evidence/measurements/2026-11-18-gdev-multicore.json)

1. **Early interfaces.** The estimate of 307 → 225 ms for the eight-worker
   checker assumed free headers for `world_storage`, `world/salt` and
   `actors/robots`. In the source pilot, scenes, hauling plans and minors each
   compiled with the corresponding producer remainder deliberately broken.
   Complete builds checked all 272 modules. They took 938 → 928 ms across
   twelve paired runs, winning seven with a 6 ms median within-pair gain.
   The application retains its current layout. A second pilot passed the
   hauling planner a declared U32 stash index and a lazy lookup. It compiled
   with the entire salt producer broken. A declared callbacks record over
   `FrameAccess` hit `TypeLimit` even after reducing it to one imported field.
   This reproducer is a smaller target than adding result annotations to all
   2,923 functions that currently omit them.
   [Pilot inputs and results](../benchmarks/evidence/measurements/2026-11-18-gdev-staging-interfaces.json)
2. **Compile-time execution.** The direct backend folds supported pure scalar
   `#run` and `#do` expressions from current Core. Imported scalar functions
   and constants can run during compilation. A retained Boolean edit to an
   imported constant rechecks one module and updates the staged result.
   Quoted code and numeric proof validation still use the live checker.
3. **Reduce work per line and parallelize the rest of the pipeline.** The
   checker alone used 1,101 ms of single-core CPU. At the throughput target,
   eight cores have 369 ms of CPU for the entire compile. Measure repeated
   type resolution and the 72.9 MB of worker replies. A trace of the new
   compiler spent 163 ms parsing and 142 ms in the Wasm backend. Parse files independently
   and reserve stable Wasm indices so workers can emit function bodies in
   parallel. [Go's per-function backend queue](https://go.dev/src/cmd/compile/internal/gc/compile.go)

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
