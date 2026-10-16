# Rolling reductions and composable summaries

This specifies the ordinary source modules `std/rolling` and `std/summary`.
[Implementation qualification](ROLLING_SUMMARIES_QUALIFICATION.md) records their
algorithms, ownership and measurements. No source declaration name grants
compiler privileges; existing folds, windows and collection representations keep
their behavior. The qualified starting compiler is `2689ad5` (completed040). The
[guide](../compiler/guide.md), [ownership contract](CONTRACT.md) and current
[iterator module](../std/iter.blot) remain authoritative for existing behavior.

## API

Arguments are curried in the order shown; collections/trees come last. `s` is
the summary value, `a` an arbitrary input, and `i` the input cursor type.
`Summary s` is a public opaque nominal type with a private balanced tree. It
stores leaf values of type `s` and cached subtree values of that same type.
Measurement from `a` to `s` is ordinary `iter.map measure values` before build.

| Operation        | Arguments                                                                        | Result          |
| ---------------- | -------------------------------------------------------------------------------- | --------------- |
| `rolling.fold`   | `step: s -> a -> s`, `initial: s`, `width: U32`, `values`                        | Iterable of `s` |
| `rolling.monoid` | `combine: s -> s -> s`, `identity: s`, `width: U32`, `values`                    | Iterable of `s` |
| `rolling.group`  | `combine: s -> s -> s`, `inverse: s -> s`, `identity: s`, `width: U32`, `values` | Iterable of `s` |
| `summary.build`  | `combine: s -> s -> s`, `identity: s`, `values`                                  | `Summary s`     |
| `summary.length` | `tree: Summary s`                                                                | `U32`           |
| `summary.get`    | `index: U32`, `tree: Summary s`                                                  | `s`             |
| `summary.query`  | `combine`, `identity`, `start: U32`, `count: U32`, `tree`                        | `s`             |
| `summary.set`    | `combine`, `index: U32`, `value: s`, `tree`                                      | `Summary s`     |
| `summary.concat` | `combine`, `left: Summary s`, `right: Summary s`                                 | `Summary s`     |

`fold` admits effects in its reducer and input protocol, propagating their
ordinary inferred rows. Fast combine/inverse callbacks are pure, closed-arrow
values; effectful callbacks receive the ordinary type/effect diagnostic. Input
iterators may still have effects: each pull is performed exactly once in the
order below. Summary build may pull an effectful input once; query/set/ concat
never repull it. Ordinary storage predicates and layout checking apply.

There is no implicit inverse, proof search for associativity, numeric-type
special case or promotion of `fold` to a faster API. Unknown/nonassociative
reducers use `fold`; a reducer without an inverse may use `monoid` only when its
independent monoid contract holds.

## Algebra and ordering

The fast constructors are explicit algebra contracts. The caller promises a
total associative combine and a two-sided identity, over every value the
operation can produce. `group` also promises a total two-sided inverse. Purity
alone proves none of these laws. The compiler does not certify an arbitrary
callback's mathematics, and provides no invented diagnostic for an algebra
violation.

Every tree operation must use the same combine, identity and immutable capture
values used to build its operands. In particular, concatenating trees from
different algebras violates this explicit contract even if `s` has the same
type. This requirement is part of the caller's algebra evidence, not a guessed
closure-identity comparison or a new runtime identity registry. Supplying
inconsistent algebra must never compromise memory/type safety, but cached
results have no fold-equivalence promise in that case.

Combination always preserves left-to-right element order. It may regroup
elements; it may not permute them. Associativity is required, commutativity is
not. In a group window, remove the oldest value from the left:
`remaining = combine (inverse oldest) current`; then
`next = combine remaining incoming`. Reversing either operation is wrong for
noncommutative groups. Cached tree/query combinations follow contiguous source
interval order.

U32 addition modulo2^32 qualifies with identity0 and inverse
`fn value => @u32.sub 0 value`; overflow retains wrapping behavior. F32
addition/multiplication do not satisfy this associativity contract, including
ordinary finite values, NaNs, infinities and signed zero. Use `rolling.fold`
with explicit F32 operations for a sequential reduction. No fast path may infer
monoid/group evidence from an F32 machine type.

Each `fold` result starts from `initial` and visits that full window from left
to right. The previous result is never an accumulator for the next window.
Callbacks, arithmetic, demand forces and traps occur in the same order as
`iter.map (iter.fold_left step initial) (iter.windows width values)`. F32
operations remain individually rounded; no reassociation or compensation changes
this result. A trapping/effectful reducer is always supported here.

## Windows, laziness and failures

All rolling APIs emit full overlapping windows only. Width1 yields one result
per item; width greater than the input length yields none. Empty input yields
none. Width0 traps at adapter construction with
`rolling requires a positive width`, before obtaining/pulling the input cursor.
This adds no new compiler diagnostic.

Adapter construction with positive width obtains the ordinary immutable cursor
without pulling it. First `next` pulls at most `width` items, stopping at the
first exhausted input; it then computes/yields the first full result. A
subsequent `next` pulls at most one new item. `take0` pulls nothing; stopping
after k results never prefetches the next item. Reduction starts only after a
complete window exists. Pull/force/provider/cancellation behavior stays governed
by the existing iterator/effect contracts.

Cursor copies are persistent versions. Advancing one cannot change the other's
buffer, cached summary or future result. Reference-bearing summary values retain
their ordinary owners. Abandoning or cancelling a cursor releases its private
window state; keeping old cursors keeps exactly those saved versions alive.

Queries use half-open intervals `[start, start+count)`. Validate
`start <= length` and `count <= length-start` before addition, avoiding wrapping
bounds checks. A zero-count query returns the supplied identity, including at
`start=length`; an empty tree's full query does the same. Invalid query/get/set
operations trap with `summary range out of bounds` or
`summary index out of bounds` before a combine callback runs. Concatenation
checks mathematical length before U32 addition and traps with
`summary length overflow`; allocator limits retain their ordinary runtime trap.
Tests may lower private storage limits.

## Representation and bounds

Use owned ordinary source data with checked reference roles. No interior leaf
pointer is a source value. Summary leaves contain `s`; internal nodes contain
subtree length, cached `s` and owned child references. Empty nodes contain no
invented `s`: the caller supplies the identity on build/query. Cache physical
layout derives from checked `s`, including mixed rows, references and cycles.
Public opaque recipes expose only the existing exact one-word reference ABI.

Choose one balanced persistent tree algorithm for summaries and monoid rolling
buffers; share it only if the implementation stays smaller. Append/drop/set/
concat copy the changed spine and share untouched subtrees. Rebalance in source
interval order, keeping height O(log(n+1)). A source-level proof need not invent
a mutable ring or observable hidden mutation. `fold` and `group` may use the
existing persistent List window queue instead.

Costs below count callback invocations separately from callback-internal cost
and input-protocol cost. Live storage excludes the borrowed input and includes
owned summaries and traversal scratch; saved versions are counted separately.

| API              | Setup / first result           | Subsequent result or operation                                        | Live state          |
| ---------------- | ------------------------------ | --------------------------------------------------------------------- | ------------------- |
| `rolling.fold`   | O(width) pulls + reducer calls | One pull + O(width) reducer calls                                     | O(width)            |
| `rolling.group`  | O(width) pulls + combines      | One pull, one inverse, two combines; O(log(width+1)) queue navigation | O(width)            |
| `rolling.monoid` | O(width) pulls + combines      | One pull + O(log(width+1)) combines/navigation                        | O(width)            |
| `summary.build`  | O(n) pulls/combines            | —                                                                     | O(n)                |
| `summary.length` | —                              | O(1)                                                                  | O(1) extra          |
| `summary.get`    | —                              | O(log(n+1))                                                           | O(log(n+1)) scratch |
| `summary.query`  | —                              | O(log(n+1)) combines                                                  | O(log(n+1)) scratch |
| `summary.set`    | —                              | O(log(n+1)) combines/new nodes                                        | O(log(n+1)) new     |
| `summary.concat` | —                              | O(log(n+m+1)) combines/new nodes                                      | O(log(n+m+1)) new   |

The group steady cost excludes window-reduction recomputation, but does not
claim constant-time persistent queue navigation. Ordered `fold` intentionally
keeps O(width) work. No amortized bound is substituted for a claimed worst-case
operation bound. A reference/callback summary's underlying graph may exceed one
word; include its real retained size in memory measurements.

## Acceptance laws for045–046

Compare every operation against ordinary folds/windows at input sizes
0,1,2,3,31,63,257,4096 and widths1,2,3,31,257,n,n+1. Check width0 separately.
Use U32 wrapping sums, products/count summaries, an associative noncommutative
composition and a noncommutative group. For U32 input `[4294967295,2,3]`, sum
windows of width2 are `[1,5]`. F32 ordered input `[16777216.0,1.0,-16777216.0]`
at width3/initial0 must return0, while the reassociated result1 demonstrates why
it receives no inferred fast evidence. Include signed-zero/NaN/Inf inputs with
bitwise comparisons where no arithmetic changes their bits.

Trace effectful inputs and ordered reducers through short input, `take0`, early
stop, thrown host callbacks, suspended/resumed requests and cancellation.
Compare trap location/order, not just final results. Keep iterator copies,
windows and old trees across further pulls/updates, allocations, resets and
cross-entry use. Check shared/cyclic/reference summaries, empty concatenation,
uneven partitions, all query endpoints, invalid/wrapping ranges and updates
across balancing boundaries. Native OOM and retained source/dependency/
checkpoint failures must preserve old owners and fresh-output equivalence.

Measure callback/node counts separately from CPU. Vary n and width
independently: doubling width must preserve the group inverse/two-combine steady
count; monoid work follows height, ordered work follows width. Tree build counts
are linear; query/set/concat examined and copied paths are logarithmic,
including an adversarial sequence of uneven concatenations. Keep at least seven
alternating compiler pairs and31 warmed guest pairs, plus raw outliers,
versions, source/ binary hashes, requested/live/committed memory and
source/artifact phase parity. Long streams retaining only the current
cursor/tree must stay bounded by the documented live state; explicit retained
versions explain additional storage.

Implementation completion requires the full specified API and structural bounds,
executed laws, full compiler gate and zero Zig findings. This document alone
claims no executable feature or measured speedup.

## Design qualification

This044 milestone changes documentation only. Review on12October2026 uses the
qualified compiler's ordinary curried functions, inferred/closed effect rows,
nominal opaque/reference ABI, persistent collection snapshots and iterator pull
order. No new syntax or compiler intrinsic is specified. Link/format checks and
independent U32/F32/noncommutative trace assertions validate the design;
executed APIs and their CPU/storage gates remain tasks045–046. Algebra contracts
are explicit caller promises, never automatically inferred or advertised as
compiler-certified proofs. No runtime compatibility registry is introduced.
