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
