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

Specialization lives in `specialization.zig`: it binds layout expectations,
solves type/effect obligations and returns owned mappings for a source body.
The service has no instruction builder or Wasm module. Retained refinement hooks
keep the existing stable artifact-owner identity and validity checks. Dynamic
member selection, closure captures and staging still request semantic work as
needed; this boundary does not assume every expression was monomorphized early.

`runtime_ir.zig` owns the compact typed stack representation before encoding.
Each opcode has an exhaustive input/result/effect contract; direct/indirect calls
resolve their signatures and allocation roles against the module. Scalar
replacement, vectorization and lifetime analysis consume these shared facts.
`runtime_pipeline.zig` owns transformed bodies and discards an obsolete buffer as
soon as the next pass replaces it. This is a stack IR, not SSA, and it does not
infer reference ownership from an arbitrary i32 word.

`runtime_layout.zig` defines the guest's fixed heap structures, their field roles
and offsets. Runtime constructors, static serialization, list helpers and arena
headers use those definitions. `runtime_cleanup.zig` records lexical obligations
for private provider frames, State cells, request frames/cells and demand reset.
Normal scope exits and source branches release only exited scopes; cancellation
unwinds the entire function, including inlined scopes. Escaping payload values
retain their independent ownership/collector policy.

Execution choices are a single session-owned `execution_policy.Policy`, with
named reference/project defaults and explicit differential-test overrides.
Cached-output equality includes that policy. Stamping instrumentation belongs
to the caller; there are no mutable global compiler switches. Identical semantic
validation inputs share immutable arrays through independent leases within one
compilation. Executable, value and evidence admission remain separate proofs.

Representation conversions distinguish layout, evidence, their respective effect
rows and code-expectation handles. Runtime cleanup distinguishes function/local
handles, and resolved bodies distinguish source expressions. Store-bound services
still enforce owner identity; equal integers from different owners are not
interchangeable. Dense legacy Core tables keep their existing word encoding.

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

Arrays are contiguous. Lists use persistent AVL trees with right-sized leaves
of up to 248 words. Exclusive end edits reuse slack and tree nodes; shared edits
detach one path and leaf. Branch copies freeze their children so both versions
remain independently editable. Ownership tokens are descriptor addresses plus
one, never tracing pointers to obsolete descriptors. Static data is immutable,
unused slots stay zero, and descriptors cache the current traversal leaf.
Immutable cursors also own an independent leaf cache, so interleaved forks do
not repeatedly evict one another. Source-body facts have one compilation owner;
bounded scalar collections can use locals and private rectangular append
regions can allocate their exact result. These optimizations consume typed
structure, not prelude names. The dense scalar-row fixture is experimental and
does not change Array/List layouts used by programs.

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
