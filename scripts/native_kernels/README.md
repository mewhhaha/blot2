# Native compiler kernels

`../native_compiler_kernels.ts` applies three Bend 2.0.27 native CPU kernels
after the guarded String comparison transform. The generated Bend code remains
the fallback. JS emission is unchanged.

- `index.c.inc` consumes each owned Patricia node with `ctr_take`, drops the
  unselected branch, and borrows only a String suffix while its owned root is
  held. The selected value is transferred to `Some` only after String equality.
- `free.c.inc` borrows a type tree, reproduces the exact nested `union` order in
  32 stack slots, then allocates an independent result list and releases the
  original work. Depth, node count, fuel, and variable count are bounded.
- `closed.c.inc` certifies that no value variable or open row can change under
  nonempty substitutions. It transfers the original owned type/list into the
  result without rebuilding the tree. Unknown shapes, insufficient fuel, and
  large trees run the Bend resolver.
- `owned_active.c.inc` runs after the closed path. It plans a bounded active
  substitution in a stack-local table of at most 256 compact nodes, then freezes
  changed nodes once. It preserves chronological versions and the original owned
  roots until every reused field has been acquired. Unsupported rows, fuel,
  layouts and unkeepable fields use the generated resolver.
- `nat_index.c.inc`, applied by `../native_nat_index.ts` after the owned
  resolver, replaces numeric Patricia lookup's branch closures with a consuming
  loop. It retains Bend's Nat48 comparisons and zero-mask division behavior,
  transfers the selected value and releases unselected paths. Shared snapshots
  use the ordinary runtime ownership operations.
- `map_bit.c.inc` and `string_cmp.c.inc`, applied together by
  `../native_borrowed_strings.ts` after NatIndex, borrow immutable String nodes
  while retaining the original owned roots. Map.bit returns its key and the same
  33-way trie bit; String.cmp returns both roots and unsigned U32 lexicographic
  order. Both loops poll for cancellation. The device keeps the generated Bend
  cases. This transform checks installed Base Map/String/Char definitions, all
  five affected generated entries and continuations, their U32 helpers, and the
  native term and atomic read layout. It stops the build if any reviewed
  contract changes.

The transformer pins the Bend version, relevant source definitions, all 16 Ty
constructors, runtime ownership helpers and cancellation macros, the complete
Index and resolve work-case shapes, and each generated free-work constructor
projection branch. An update to source semantics or generated C layout must be
reviewed before updating a contract. Bounded type kernels use the original
generated cases as fallback. The direct index loops replace their complete
guarded cases. No global cache or RC bypass exists.

Run the fast transformer checks with:

```sh
deno test --allow-read scripts/native_compiler_kernels.test.ts
deno test --allow-read scripts/native_owned_resolver.test.ts
deno test --allow-read scripts/native_nat_index.test.ts
deno test --allow-read scripts/native_borrowed_strings.test.ts
```

After building a baseline and candidate compiler, run the native API oracle:

```sh
deno run --allow-read --allow-run scripts/native_compiler_kernels_oracle.ts BASELINE_BLOTC CANDIDATE_BLOTC
```

It compares repeated analyze/compile results and errors at 1 and 4 threads,
including Unicode module names, long shared prefixes, generic effects, type
failures and recovery after failures. The standalone Bend probes in `probes/`
exercise Patricia Map snapshots and value ownership, free-variable order and
fuel fallback, and closed versus open row resolution against its independent
source implementation. Build and compare fresh native C for those probes with:

```sh
deno run --allow-read --allow-write --allow-run scripts/native_kernels/probes/run.ts
```

The harness emits each Bend probe to a temporary C file, applies the same
checked C assets through its probe-specific symbol guard, compiles baseline and
candidate, and compares three seeds at 1 and 4 threads. It removes the temporary
files after comparison.

The active owned resolver has a separate direct native oracle:

```sh
deno run --allow-read --allow-write --allow-run scripts/native_kernels/probes/run_owned.ts
```

This checks final and non-final variable replacement, repeated chronology,
low-fuel diagnostics, and at least three actual changed-path fast-path hits.

The numeric index oracle covers empty/hit/missing lookups, high and maximum
Nat48 keys, shared snapshots, nested payloads, malformed zero/nonpower branch
masks, repeated parallel lookups, exact overflow diagnostics, and direct-path
hit counts. Its candidate also runs under AddressSanitizer and UBSan:

```sh
deno run --allow-read --allow-write --allow-run scripts/native_kernels/probes/run_nat_index.ts
```

The borrowed String direct probe exercises empty and prefix comparisons,
distinct equal and shared strings, embedded NUL, Unicode and U32 boundary
characters, Nat48 map positions, and exact overflow diagnostics at 1 and 4
workers. It confirms both kernels execute, compares to generated Bend output,
and runs the candidate under AddressSanitizer and UBSan:

```sh
deno run --allow-read --allow-write --allow-run scripts/native_kernels/probes/run_borrowed_strings.ts
```
