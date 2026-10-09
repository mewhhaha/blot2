# Standard library performance

Library performance follows ordinary type, effect and ownership evidence. The
compiler does not recognize prelude, collection-helper or framework declaration
names. Use the [language guide](../compiler/guide.md) for semantics and the
[compiler status](../zig-native/STATUS.md) for current compilation measurements.
Historical comparisons remain in git.

## Choosing collections

`List a` and `Array a` are distinct types. Lists support traversal and
persistent construction. Arrays provide indexing, checked `get`/`set`, and
trapping `at`/`replace`. Conversions are explicit; there is no public List
indexing. Collection transformations take their collection argument last for
pipelines. Numeric arrays cross the guest ABI by copying, so host mutation
cannot change a retained guest value.

Lists use persistent balanced trees with right-sized leaves of at most 248
storage words. An exclusive end edit can reuse slack and tree nodes. A shared
edit copies one path and leaf, preserving both snapshots. Arrays are contiguous;
runtime append still copies. Repeated growth therefore has different costs from
filling a known-size array or building a List and converting once.

Flat tuples and structural records with 1–16 checked scalar fields can occupy
consecutive payload words in Lists and Arrays. Public lengths and cursor
positions still count elements. Nested, nominal, reference-bearing, erased and
wider rows retain the boxed representation. Extracted values own their storage;
packing never licenses changing a surviving snapshot or reordering F32 work.

Packing reduces retained storage and construction/conversion work on qualified
fixtures. It is not a universal traversal speedup: the existing read-only List
fold fixture uses about 1.9 times the CPU of the preceding boxed layout, and its
cursor fixture about 1.5 times. That regression remains open. Measure the actual
traversal and element shape before selecting a representation.

## Effects, callbacks and demands

List and Array folds propagate reducer effects. List `any` and `all` stop at the
first deciding element; empty inputs return false and true respectively without
calling the predicate. List `filter` evaluates each predicate once in order.
Array construction and collection `map`/`generate` retain their documented pure
callback contracts.

`Maybe.unwrap_or_else` and `Result.unwrap_or_else` defer the fallback until
failure. `unwrap_or` remains eager. `@demand` requests one deferred result and
shares its successful completion; `@force` remains an alias. An ordinary
callback runs on each invocation. Skipped demands must not run effects or traps.
See [the demand design](../zig-native/DEMANDS.md) for forwarding, escaping
values, provider scope, cancellation and failed completion.

Known callbacks can use direct calls and bounded inlining. Unknown callbacks
retain the general path. Known demand combinators containing admitted branches,
constructor matches, guards and acyclic local forwarding calls can use local
memo state instead of a heap cell. Admission is bounded to 96 expression/pattern
nodes across the forwarding chain and preserves lexical binding identities,
evaluation order and once-only demand behavior.

## Optimization boundaries

| Mechanism           | Current boundary                                                                                                                                                                                                                |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Exclusive updates   | Checked success branches, nested unique fields and loop exits can preserve ownership; surviving aliases, captures and extracted inner values prevent destructive updates.                                                       |
| Small aggregates    | Fully initialized, nonescaping records, tuples and wrappers can become scalar locals. ABI values, captured values, unknown offsets and GC roots remain boxed.                                                                   |
| Small collections   | Up to eight scalar elements can use locals when all uses are admitted traversal or intrinsic length reads; escaping and updated collections remain boxed.                                                                       |
| Exact builders      | Up to four rectangular finite generators can allocate final storage directly. Bounds must be independent of region binders, nonallocating, nontrapping and pure. Ragged, filtered and effectful regions keep ordinary builders. |
| Staged construction | Private bounded indexed regions update scratch and freeze once. Published spans and observed intermediate versions remain immutable. Append/prepend can reuse unpublished end slack.                                            |
| Traversal           | Word-element and packed-row cursors retain their own leaf cache. Cross-leaf fields use checked lookup. Generic iterator step/cursor allocations are not universally eliminated.                                                 |
| Inlining            | A four-node source budget expands to 64 for aggregate results inside loops or known callbacks, with at most six nested expansions and a 4,096-instruction bound.                                                                |
| SIMD and fusion     | Existing proofs apply to admitted typed loops. Broader row fusion, ragged builders, rolling reductions and composable summaries remain open.                                                                                    |

`prefix_sums` uses recursive pair sums with linear work and intermediate
storage, including constant evaluation. Array `indices`, `filter` and
`filter_map` build a private chunked List in one traversal and convert once.
`concat` avoids intermediate chunk arrays; `flatten` counts lengths before
filling. Both retain length-overflow checks. Vec2/Vec3 interpolation preserves
the documented F32 operation order; sine and cosine share angle reduction in
`F32.tan`.

Runtime ownership optimizations coexist with a nonmoving tracing collector. They
do not prove that every object has a finite lexical lifetime: State, closures
and cached demands can form cycles. Guest memory readings report committed Wasm
pages, including temporary capacity, rather than exact live objects or
cumulative allocation.

## Measuring changes

Build both compiler versions with Zig 0.17 and keep their standard libraries
paired with the appropriate executable. Dependency files include compiler
identity and cannot be shared indiscriminately between versions. The harnesses
record binary/source hashes, check results and retain raw samples.

```sh
deno run --allow-read --allow-write --allow-run scripts/bench_stdlib.ts \
  zig-native/zig-out/bin/blotc std build/stdlib-bench \
  /path/to/baseline/blotc /path/to/baseline/std

deno run --allow-read --allow-write --allow-run scripts/bench_packed_rows.ts \
  /path/to/baseline/blotc zig-native/zig-out/bin/blotc std build/packed-rows

deno run --allow-read --allow-write --allow-run scripts/bench_runtime_costs.ts \
  zig-native/zig-out/bin/blotc std build/runtime-costs
```

Keep guest runtime, guest memory, compiler CPU, compiler requested allocation
and process RSS separate. Warmup and sampling policies are defined by each
harness; compare matching fixtures and measurement boundaries. Fixture speedups
do not establish whole-application speedups. On the current development machine
ananicy can demote Deno and its children, so wall time alone is insufficient
evidence.

For compilation, keep a `createCompiler` instance open across edits and dispose
it when finished. Retained reuse validates source bodies, semantic reads and
complete captured-value graphs; a type-preserving edit can still invalidate
executable callers. Use `deno task bench:compile` to separate fresh processes,
session population, first edit, later edit and no-op requests. Its
`--restart-cache` option measures process restart separately. Failed edits must
preserve the preceding successful revision and its owners.
