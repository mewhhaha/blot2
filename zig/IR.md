# Native type IR

The type **resolution, replacement and renaming** stage now runs on compact
native Zig IDs. This is an integrated stage of the compiler, not a second
compiler selected only by tests. It is **not the completed whole-compiler IR
rewrite**: lowering, constraint solving, generalization, specialization,
compile-time evaluation and Wasm emission still use source-derived algorithms.

## Representation

`type_ir.zig` has no dependency on the generic runtime or generated semantic
functions. It owns four distinct 32-bit handle types: `Type`, `Row`, `Name`, and
`Symbol`. Type nodes are 16 bytes, plus eight bytes of cached traversal facts
per node, with contiguous spans for variable-length type arguments and ordered
effect labels. The representation covers all sixteen current type constructors
and all four effect-row tail forms. Variable and parameter payloads retain all
48 identity bits; node handles are not language variable identities.

Types, rows, nominal identities and UTF-8 symbols are structurally interned.
Hash collisions are checked against complete keys and contents. Effect labels
retain both order and duplicates. Appending an existing label span preserves its
offset across storage growth rather than keeping a stale slice or copying it
through a temporary allocation.

## Live integration

The generated callers dispatch these entries to the native stage:

| Retained entry         | Native implementation                                                    |
| ---------------------- | ------------------------------------------------------------------------ |
| `types.resolve`        | Full single-type resolution                                              |
| `types.resolve_work`   | Single-type and type-list resolution                                     |
| `types.resolve_row_at` | Chronological effect-row resolution                                      |
| `types.rewrite`        | Variable, parameter and free-name replacement; freshening and relocation |
| `types.rename_work`    | Variable renaming and conversion to scheme parameters                    |

There is no generated compound-type fallback in these implementations.
`type_bridge.zig` imports legacy type nodes once per raw object per task context
and exports changed results lazily. Unchanged results reuse existing immutable
values. This boundary remains necessary while surrounding stages still produce
and consume generic values; the whole compiler does not yet stay in compact IR.

A task's `Context` owns its IR store, interning tables, import/export maps and
reusable traversal buffers. Other workers never mutate them. Exported legacy
values follow the existing request-arena lifetime; IR caches are destroyed at
task/request teardown and are not copied into retained sessions. No unvalidated
pointer-keyed cache crosses a source revision.

Native entry selection remains guarded by the exact hashes of `types.bend`,
`model.bend`, `effect_rows.bend` and `nat_index.bend`. An upstream semantic
change disables affected overrides until their implementation is revalidated.
This is a migration guard, not a runtime fallback after a native operation
starts.

## Preserved semantics

Substitution histories are chronological. A replacement sees only bindings
_after_ its insertion position, including when it contains a reference to
itself. Renaming and direct replacement do not recursively rewrite an inserted
replacement. Type variables, quantified parameters and free source names remain
distinct, as do their row counterparts.

Traversal uses explicit work stacks, not one native call frame per type node.
Its memo key includes the type ID, chronological cursor, remaining substitution
links and structural fuel. Fuel retains the original depth **and list-width**
rules, rather than becoming a global node counter. Cache reuse cannot bypass
complexity errors or borrow answers from another substitution snapshot. Child
processing and row rewriting retain diagnostic precedence. Cached variable-kind
flags and minimum required fuel allow an unaffected subtree to be returned in
constant time without hiding a nesting or width error.

The resolver memo table is reused only for the same immutable substitution
snapshot and bounded between operations; direct rewrites clear it because their
mapping or replacement can change. Interned nodes and import caches currently
live for the task/request, not for an entire incremental session.

## Checks

`zig build test` runs native IR tests alongside the existing runtime tests.
`type_ir_tests.zig` compares against independently emitted aliases of the
unchanged reference algorithms. Their entire transitive call graph avoids the
native overrides, including generated lambdas and outlined arms; a generator
regression checks this separation. These reference entry points are present in
the generated module for tests, but production native operations never call
them.

The tests cover every current type constructor and row tail; exact complexity
and kind diagnostics; chronological insertion boundaries; snapshot changes;
Unicode free names; 48-bit identities; thousands of seeded comparisons;
allocation-failure cleanup; and alias-safe storage growth. A 4,096-level bridge
test checks stack-bounded import, rewrite and export. A shared 40-level
branching graph is transformed with 41 distinct node visits while preserving
shared children in the exported result.

Those are structural regression checks, not an end-to-end compiler speedup
claim. No benchmark job is added to CI. The unchanged source compatibility suite
continues to validate artifacts, diagnostics, native sessions and guest Wasm.

## Remaining migration

Next stages must carry IDs through constraint solving and generalization,
followed by the expression/declaration IR, specialization, compile-time
execution and code generation. The bridge should shrink as those consumers
become native; adding more conversion boundaries is not the final architecture.
