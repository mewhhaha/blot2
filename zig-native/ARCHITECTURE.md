# Native compiler architecture

The compiler uses one native project pipeline for full builds and retained
revisions. Deno supplies the optional client, formatter and guest host; it does
not parse, infer or stage source for compilation.

1. Immutable UTF-8 source buffers feed flat token and syntax arrays. Symbols are
   interned once into an owned byte buffer and referenced by numeric IDs.
2. The checker owns dense type, row, binding and chronological substitution
   tables. Principal declaration information is separate from call-site
   evidence.
3. Owned typed Core retains normalized types, exact imported identities, staged
   values and source origins after frontend scratch is released.
4. Evidence and code instances specialize retained bodies. Relocatable function
   fragments carry symbolic dependencies until deterministic Wasm assembly.
5. The project server publishes a revision only after checking and emission
   succeed. Failed edits preserve the last successful revision. Immutable
   dependency modules can be shared across revisions without retaining a chain
   of prior mutable solver states.

Compiled `.blotdep` files contain typed dependency modules and their admission
metadata. Compiler identity, source changes, catalogs, nominal origins and
compile-time dependencies participate in validity checks. Native work counters
are instrumentation, not source-language fuel semantics.

Constant records keep unused generic fields in the evaluator until a concrete
use selects them. Calls and partial applications can retain those fields while
capturing dynamic arguments once. Code jobs containing such static captures
currently rebuild after edits because their request keys do not describe the
captured values; other semantic and code reuse remains available. Complete
emission journals still reconstruct the exact output.

## Ownership and memory

IDs and side-table spans survive array growth. Hashes locate candidates;
structural equality and complete semantic evidence decide reuse. Mutable query
scratch is released explicitly. Published immutable modules own their tables.
The solver preserves cursor-relative chronological substitutions; replacing it
with ordinary union-find would change semantics without an admission proof.

Arrays are contiguous. A List descriptor owns doubly linked chunks of up to 256
words. Exclusive end edits reuse slack; shared edits copy the entire chain.
Static descriptors are immutable. Unused payload slots remain zero for the
tracing collector, and cached chunk positions make monotone traversal linear.
This improves owned construction but makes a shared edit expensive on long
lists.

## Limits and measurement

The native evaluator defaults to 1,000,000 operations, nesting depth 256,
1,000,000 values and 4,194,304 child slots per evaluation session. It diagnoses
exhaustion; these limits do not count retired Bend evaluation steps. Separate
backend and Wasm memory constraints are enforced at their boundaries.

Measure fresh processes, dependency population, first edits, subsequent edits,
no-ops and failed-edit recovery independently. Include transport and output
publication in public edit measurements. Report requested allocator bytes
separately from process RSS. Keep deterministic output and executed guest checks
alongside latency measurements. The gdev targets are approximately 500 ms cold
and below 100 ms incremental, without a hard real-time guarantee.
