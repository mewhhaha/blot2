# Compiler direction

The approved next program replaces tracing with explicit ownership: full control
flow lifetimes, temporary elimination/regions, RC for shared storage, suspended
effect ownership and cancellation, then removal of tracing after qualification.
The implemented lifetime pass follows proven temporaries across branches, loop
exits, borrowed direct calls and fresh-result ownership transfers. It also
releases closed allocation groups with shared children and cycles when every
reference and exit is proven, and records pointer-free collection element
layouts. Shared RC, complete effect lifetime cleanup and collector removal
remain open; do not
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
