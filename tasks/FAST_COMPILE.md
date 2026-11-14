# Fast compilation: a modular direct backend

Goal: compile Blot at 1M lines/s. Gdev Main (45,335 lines in 264 files, 2.5 MB
of source with its generated asset modules) should build in about 45 ms; it
takes 6.6 s today (about 6,900 lines/s) and produces 9.2 MB of Wasm.

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
runs every fixture in `compiler/fixtures/direct/` on both backends.

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

1. Phase 6 first: the direct backend becomes the only backend, and the scoped
   backend, `eval/`, the scoped `runtime/` and the reuse machinery built
   around scoped artifacts are deleted.
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
