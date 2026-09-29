# Task-local type graph

The `Core_levels` module is the first new inference kernel. It is deliberately
separate from the compatibility compiler's existing chronological substitution
API. Adding it to the native build does not make it the default source solver,
and its unit timings are not source-compilation speedups.

## Storage and ownership

An arena stores variable cells and compound nodes in indexed storage. Handles
carry an owner and a monotonically increasing generation; rolling back and
reusing a slot cannot turn a stale handle into a reference to a new variable.
The sealed module does not expose mutable cells. Each worker owns its arena;
independent workers do not synchronize individual unification operations.

Variable links use union by rank and path compression. Linking an outer variable
to an inner structure lowers the levels of reachable variables. Generalization
freezes only variables above the binding boundary; `protect` handles variables
that must remain monomorphic, including ambient effects and blocked obligations.
The API takes multiple roots so a signature and its residual obligation types
can be frozen and instantiated together, retaining their sharing.

A frozen scheme is a postorder immutable DAG, not an expanded type tree. Fully
generalized schemes can move to another arena with the same nominal identity
registry. Schemes containing weak variables must stay in their owning arena.
Clearing or rolling back those variables invalidates later instantiation rather
than accidentally freshening an outer binding.

## Transactions

Checkpoints are local, live and strictly nested. Links, ranks, level reductions
and path-compression writes all enter the undo trail. Failed unification restores
its graph and new allocation count. A successful nested transaction still rolls
back with its outer transaction. An exception with an abandoned inner checkpoint
unwinds that checkpoint too, preserving the original exception.

A successful transaction callback must close explicit inner checkpoints. A
callback that fails to do so is rejected and rolled back. Attempt counters in
`statistics` deliberately remain cumulative across rollbacks; they count actual
work, not only accepted work. `view` and `equivalent` may compress paths, but do
not change the semantic solution. Compression is trailed inside a checkpoint.

## Effects and boundaries

Effect rows retain duplicate operation identities. Residual-row unification
cancels equal occurrences, not sets, and connects fresh tails when both sides
are open. Closed and rigid tails remain constrained. `equivalent` is structural
representation equality after following links; it intentionally does not sort
row labels. Semantic row equality is tested through unification.

Kinds, constructor arities, type occurs checks, invalid handles, allocation
limits and work limits are explicit failures. Traversals and freezing use
worklists so deep types and shared binary DAGs do not recursively expand.
The `Never` rule retains the compiler's bottom-type unification behavior.

Blot's variance closing, principal scheme rules, residual predicates, diagnostics
and immutable chronological substitution histories remain authoritative in the
existing pipeline. They must be adapted and differentially validated before
this kernel replaces that pipeline. In particular, this kernel accepts equal
rigid type symbols; the old low-level type solver does not implement that case
in the same way. The two APIs are not interchangeable by renaming functions.

## Verification

`test_levels.ml` covers level lowering, weak sharing, independent instantiation,
predicate-only roots, protected ambient rows, rollback after late failure,
path compression, stale/reused slots, nested checkpoint misuse, row multiplicity,
20,000-node deep types, a depth-30 shared DAG, and four independent domains.

An independent persistent-substitution implementation checks 48,000 randomized
first-order equations across 2,000 systems. Another 4,000 randomized closed-row
comparisons use a multiset oracle. These comparisons and the invariants total
287,801 assertions in the current test. They are not extra source-suite tests or
a proof of the complete inference engine.

Run:

```sh
make -C compiler/core test
```
