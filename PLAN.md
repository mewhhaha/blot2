# Compiler direction

## Semantic compilation performance program

The next ten hills are approved after checkpoint `8b44ee6`. Preserve that
compiler and the gdev source snapshot for paired fresh-process and retained-edit
measurements. The qualified starting measurements are 1,606 ms cold and 399 ms
first edit; quieter diagnostic timings are for attribution, not claimed gains.

1. Split oversized inference regions using independently valid body summaries.
2. Deduplicate repeated semantic specialization by complete evidence.
3. Share immutable semantic graphs while keeping solver variables region-local.
4. Extend semantic early cutoff to general body edits with exact dependencies.
5. Publish transactional revision deltas without rebuilding unchanged metadata.
6. Retain evaluated constants and relocatable serialized data with exact inputs.
7. Expand portable dependencies to eligible complete semantic artifacts.
8. Complete the resolved backend IR boundary for calls, control flow and ownership.
9. Remove incidental function indices from optimized-body reuse identities.
10. Schedule independent semantic jobs with owned solver state deterministically.

Status: implementation in progress. The earlier bounded paths and experiments
below remain the reference and fallback, not evidence that these new gates are
complete. General language rules authorize reuse; declaration names never do.
Preserve chronological solver semantics, staging, diagnostics, provider and
generative identities, revision recovery, and executed-Wasm behavior. Measure
each architectural step before extending its admission or production defaults.

The current implementation adds a Session-local completed-refinement index to
both fresh CLI and retained builds, shares closed source types across lexical
imports, retains dependency-validation certificates, imports nonempty portable
principal results, relocates optimized direct calls, and allows exact completed
scalar constants inside retained code fragments. Refinement receipts can now
stop transitive invalidation at freshly checked closed-call judgments: changing
a callee from addition to subtraction preserves eligible caller type answers
while runtime code and staged values rebuild. Focused parity and allocation
failure laws pass. The release build and 1,095 native tests pass; all 548
guest/client tests pass across the full run and focused environmental retries.
The [qualification report](std/PERFORMANCE.md#semantic-compilation-performance)
records the final scope and pinned binary.

Three broader paths remain opt-in: independent first-order call partitions,
resolved scalar SSA with structured branches/joins, and independent semantic
workers. The partition experiment accepts 963 gdev boundaries and reduces the
largest diagnostic region from 13,863 to 10,335 scopes, with identical Wasm and
evaluation counts. Initial fresh-session pairs improve, but retained-edit
samples show no clear win. It therefore does not change production defaults.

These are bounded implementations, not completion of the entire redesign.
Higher-order/SCC summaries, general body edit identities, full metadata deltas,
retained aggregate evaluation/serialized data, arbitrary portable semantic jobs,
resolved calls/loops/heap ownership, and a general adaptive semantic scheduler
remain open. Five alternating pairs show median native CPU of 1,196 → 1,182 ms
cold, 350 → 310 ms first edit and 330 → 290 ms revert. Cold CPU is nearly
unchanged; edit CPU improves about 11–12%. Requested allocation traffic falls
433.6 → 425.4 MB. Host contention makes the wall samples unsuitable for proving
the target latency; the 500 ms cold / 100 ms edit goals remain unestablished.
The historical measurements below describe their respective checkpoints.

## Existing programs

The current list-like transfer order is: preserve one typed frontend and shared
language laws; packed scalar rows and broader general fusion/SIMD; then ragged
builders, rolling reductions and composable source summaries. Query rewrites,
runtime caches and workers remain separate measured follow-ups. Their remaining
scalar/generic frontend convergence is specific to list-like; Blot keeps its
existing typed path, separate List/Array types and explicit lazy iterators.
Do not copy eager producer rewrites across effectful iterator pulls.

The first production storage step packs flat scalar List and Array rows. It covers
literals, static values, fill/generate, exact builders, indexing, updates,
structural copies, cursors and List/Array conversion. Reference-bearing/nested
rows retain their previous representation. The full native suite and 546
guest/client tests pass, including allocation failure and fresh/retained laws.
The [qualification report](std/PERFORMANCE.md#production-packed-scalar-rows)
records every runtime and compiler measurement. Direct scalar field
reads avoid extracted boxes. Packed cursors and direct loops reuse leaf spans;
bounded allocation-producing callees expose their temporary rows to scalar
replacement. Broader row fusion and SIMD remain the next representation work.
The measured generation and conversion fixtures use 6.4× and 4.0× less CPU,
respectively, but read-only List folds use 1.9× as much CPU. Packed retained
List storage falls 61%. Closing the traversal regression remains open. This
batch does not improve compiler latency: paired gdev cold compilation is
1,466 → 1,606 ms and first edit 389 → 399 ms. Both targets remain unmet.

The compiler-performance program approved after `586e0ae` covers ten hills:

1. Reuse fully optimized function bodies with exact optimizer dependencies.
2. Include captured values in executable identities and reuse admission.
3. Recheck individual changed bodies instead of whole modules where valid.
4. Produce resolved ownership-aware SSA before runtime emission.
5. Reduce allocation traffic using reusable scratch and immutable sharing.
6. Persist admitted specializations and optimized dependency fragments.
7. Share generic machine code where representation and evidence permit it.
8. Offer a fast development tier with full semantics and required cleanup.
9. Schedule immutable independent jobs concurrently with deterministic output.
10. Produce patches for ABI-compatible running Wasm programs.

This program is in progress. Begin with optimized body retention and complete
dependency laws; retain the frozen compiler and gdev workload in
`build/compiler-hills/before`. Every stage requires fresh/retained parity,
failure recovery, allocation ownership and end-to-end measurements. Prototype
SSA, shared generic code, tiers, concurrency and patches before changing their
production defaults. No optimization may recognize prelude declaration names.

Current progress: optimized-body retention (1) and scratch/closed-evidence sharing
(5) are qualified. Capture keys (2) cover anonymous static closures; projected
principal-query replay (3) covers structurally identical scalar-literal edits,
not general body-level checking. Exact private machine-body sharing (7), the
development tier (8) and coarse optimizer jobs (9) are qualified opt-in
prototypes. Sharing reduces gdev Wasm size by 7.8%; total compile-time gains from
these options remain unproven. Portable backend checkpoints (6) now restore
empty-result principal-query proofs and optimized bodies across processes. Their
full gate and restart measurements pass, with about 30% less child CPU work on
gdev restarts under a contended host. They do not persist arbitrary
specializations or evaluated values. Resolved scalar SSA (4) is a private,
default-off prototype with exact-output and ownership laws; its gdev coverage is
too narrow to establish a useful speedup. Live scalar Wasm patches (10) have an
executed native/host prototype, including stable exported identities, recursive
call redirection and atomic publication. It rejects heap/effect state and has no
project-client API yet. That preceding checkpoint passed the release build,
native suite and 539 guest/client tests, with 120 existing lint warnings and
no errors across 279 files.

The program is not complete: general body-level checking, full resolved
ownership-aware SSA, arbitrary specialization persistence and stateful live
patching remain open. The final paired default-path run measures 1,354 → 1,294 ms
cold, 984 → 378 ms first edit and 982 → 376 ms subsequent edit. Earlier quieter
runs measured 773/184/171 ms for the candidate; do not compare absolute latency
across batches. Both targets remain unmet.

The architecture cleanup approved after checkpoint `42cb11f` covers all seven
review findings. Preserve source behavior, fresh/retained parity and the existing
cycle laws throughout this migration:

1. A typed runtime IR shared by allocation, vectorization and lifetime passes.
2. Explicit cleanup paths for normal return, break, cancellation and demand reset.
3. A specialization boundary that hands resolved bodies to runtime emission.
4. Defined production reuse policies, isolated differential controls and shared
   revision validation inputs with distinct semantic/executable proofs.
5. Shared heap layout definitions for construction, access and serialization.
6. Compilation/session-owned options and instrumentation; no mutable global knobs.
7. Distinct numeric handle domains and named accessors at compiler boundaries.

These boundaries are now implemented: the compact typed stack IR and pipeline,
private-scope cleanup ledger, semantic specialization service, shared policy and
validation leases, centralized fixed heap schemas, caller-owned instrumentation,
and distinct conversion/runtime handles. The full compiler gate and paired
measurements against the committed compiler pass; the
[qualification report](std/PERFORMANCE.md#compiler-architecture-cleanup)
records bounded private-handler memory and unchanged compilation cost.
The stack IR is not SSA; dynamic source
selection still queries semantics, and legacy dense Core storage still uses raw
words internally. These changes do not remove tracing or solve dynamic cycles.

The approved next program replaces tracing with explicit ownership: full control
flow lifetimes, temporary elimination/regions, RC for shared storage, suspended
effect ownership and cancellation, then removal of tracing after qualification.
The implemented lifetime pass follows proven temporaries across branches, loop
exits, borrowed direct calls and fresh-result ownership transfers. It also
releases closed allocation groups with shared children and cycles when every
reference and exit is proven, and records pointer-free collection element
layouts. Private handler scopes now clean up explicitly. Shared RC, ownership
of escaping and suspended effect values, and collector removal remain open; do not
describe this partial proof as universal ownership or a GC-free runtime.
The cycle audit has an executed counterexample: State can return a closure that
reaches the demand caching that closure. Preserve this legal behavior and its
bounded-memory regression when adding RC; cyclic ownership cannot be omitted.

The latest `../list-like/LIST.md` review covers its uncommitted packet/span design.
Adopted here: allocation-free empty values and unchanged structural operations,
and identical-bit edit avoidance with safe snapshots. Preserve Blot's distinct
List/Array types, no public list indexing, logarithmic tree edits and detached
small slices. Larger span buffers, sparse compaction and host span borrows need
workload and lifetime evidence before changing those contracts.
The follow-up review adopts `splice` and ordered `splice_many` as ordinary
source functions over structural slices/concatenation. Its paged spine, tiny
owners and generation caches are still prototypes, not their default layout.

The previous transfer batch implemented independent immutable cursor caches, bounded
scalar temporary collections across helpers, rectangular exact-size builders,
and compile-owned function facts. Packed scalar rows began as a separate measured
fixture; their production integration is the current batch above. Ragged count
passes, rolling reductions, summary trees, host span borrows and adaptive runtime
workers remain future work.

The list/iterator program approved on 2026-10-07 follows checkpoint `5f09303`:

1. Ordinary `iter`/`next` dispatch in `for` and comprehensions, preserving effects,
   monadic control flow, evaluation order and early exit.
2. Immutable snapshot cursors with efficient leaf traversal and independent positions.
3. Source adapters: zip/zip_strict, enumerate, windows, take/take_while, map/filter,
   folds and explicit list/array collection.
4. Structural concatenation, slices and splits; no public list indexing.
5. Bulk leaf copying, conversion and construction.
6. Measured growth, metadata and sparse-result storage improvements.
7. Automatic numeric SIMD and explicit SIMD primitives, preserving scalar semantics.
8. General elimination of local iterator state and step allocations.

These eight areas are implemented and qualified in the
[iterator follow-up](std/PERFORMANCE.md#iterator-and-structural-list-follow-up).
Allocation elimination and automatic SIMD have bounded admission rules; generic
iterator pipelines can still allocate. Runtime reclamation uses a tracing arena
collector alongside ownership analysis. The larger gdev snapshot remains above
the 500 ms fresh-process and 100 ms retained-edit targets.

Preserve distinct List/Array types and ordinary source implementations; compiler
optimizations must not recognize adapter or prelude declaration names. Check
both const evaluation and executed Wasm, retained dependency validity, and
cold/edit compiler cost.

The approved type-system and ergonomics program, including typed external
assets, is tracked in [language evolution](zig-native/LANGUAGE_EVOLUTION.md).

Blot uses the handwritten Zig 0.17 compiler and its asynchronous
retained-project API. The targets for gdev are about 500 ms cold compilation and
under 100 ms incremental compilation, with language, effects, staging and guest
behavior preserved. Exact Bend API shapes and evaluation step counts are retired
by the owner's decision on 2026-10-05.

The current work and measurements are in
[zig-native/STATUS.md](zig-native/STATUS.md). Continue improving invalidation
precision, scratch ownership and artifact reuse only where measurements show a
benefit. Dependency bundles and retained modules must account for compiler
settings, nominal identities, provider/evidence selection and executed
compile-time code.

Use language fixtures, negative diagnostics, allocation-failure tests, executed
Wasm and fresh-versus-retained output comparisons as correctness gates. Keep
cold process timing, dependency population, first edit, subsequent edit, no-op
and failed-edit recovery separate. Parallelize only after measuring a useful
independent workload and including coordination costs.

The [demand evaluation design](zig-native/DEMANDS.md) specifies the `@demand`
spelling, predictable elimination of deferred arguments, and the effect,
lifetime, and incremental dependency rules needed for source-defined `&&` and
`||` to compile to ordinary branches. The compiler now eliminates cells for
bounded expression combinators, including repeated local demands. More complex
and escaping uses retain runtime cells; `@force` remains an alias.

The [standard library audit](std/PERFORMANCE.md) covers collection construction,
callback effects, demand lowering, math and vector allocation, with paired
runtime measurements and a fresh gdev compilation baseline.
