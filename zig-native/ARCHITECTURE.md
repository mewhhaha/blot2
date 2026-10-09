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
solves type/effect obligations and returns owned mappings for a source body. The
service has no instruction builder or Wasm module. Retained refinement hooks
keep the existing stable artifact-owner identity and validity checks. Dynamic
member selection, closure captures and staging still request semantic work as
needed; this boundary does not assume every expression was monomorphized early.

Constant aggregates can retain unobserved polymorphic accessors while selected
fields lower with their own concrete use types. For an anonymous callable whose
argument contains an open callback row, source emission proves the body against
the selected code shape and the caller's frozen argument signature. Solved
partial physical shapes retain unknown rows without becoming semantic evidence.
Exact live captures stay within that Session; these hints disable semantic
receipts and executable-fragment reuse. Bounded inlining selects small bodies;
private functions handle larger bodies and deeper composition. Runtime argument
order, ambient effect widening and cleanup retain ordinary call semantics.

A completed closure specialization also proves its frozen closure and demand
captures at their exact evidence. The evaluator publishes those fixed points
together, after reserving all cache entries, so later requests do not recheck or
clone the same capture graph. A typed header or an unresolved region grants no
such proof. Different captured values keep their own identities.

`runtime_ir.zig` owns the compact typed stack representation before encoding.
Each opcode has an exhaustive input/result/effect contract; direct/indirect
calls resolve their signatures and allocation roles against the module. Scalar
replacement, vectorization and lifetime analysis consume these shared facts.
`runtime_pipeline.zig` owns transformed bodies and discards an obsolete buffer
as soon as the next pass replaces it. This is a stack IR, not SSA, and it does
not infer reference ownership from an arbitrary i32 word.

`runtime_layout.zig` defines the guest's fixed heap structures, their field
roles and offsets. Runtime constructors, static serialization, list helpers and
arena headers use those definitions. `runtime_cleanup.zig` records lexical
obligations for private provider frames, State cells, request frames/cells and
demand reset. Normal scope exits and source branches release only exited scopes;
cancellation unwinds the entire function, including inlined scopes. Escaping
payload values retain their independent ownership/collector policy.

Execution choices are a single session-owned `execution_policy.Policy`: codegen
tier, machine-code sharing and codegen/semantic worker counts. Compiler behavior
is not policy; the CLI and the project server run the same implementation, and
artifact retention follows the retained session (`retain_artifacts`/`previous`).
Cached-output equality includes the policy. Stamping instrumentation belongs to
the caller; there are no mutable global compiler switches. Identical semantic
validation inputs share immutable arrays through independent leases within one
compilation. Executable, value and evidence admission remain separate proofs.

Frontend schemes reference shareable callee schemes instead of copying their
transitive obligations. Backend first-order calls become summary constraints:
once their input types close, a session queue checks each target/input pair in
an independent region. The explicit job stack avoids native recursive inference
along deep call chains and reuses shared subgraphs. Interface preflight has its
own summary mode so witness validation keeps its source order. Failed jobs
replay ordinary collection for authoritative diagnostics. Declared global
functions whose checked schemes have no residual predicates admit calls from
those schemes directly, including function parameters and quantified rows.
Computed function values still require their actual capture proofs. Independent
closed proofs publish before unrelated caller constraints finish; source
interface and retained capture checks keep their existing collection rules.
General higher-order calls, lexical captures and recursive components still
require shared inference regions. Occurs checks visit each resolved node once
even when the type is a shared DAG.

[General call summaries](CALL_SUMMARIES.md) specifies the next boundary:
separate principal graphs and completed call judgments, explicit residual and
callback obligations, capture inputs, recursive components, canonical keys and
transactional publication. It is a design contract; the general implementation
and qualification remain open.

Current variable resolution can reuse a node-local certificate across unrelated
substitutions. Closed results remain stable; open aliases watch the remaining
chronological variable. Physical type/effect edits and rollback invalidate the
certificate generation, and historical cursor queries retain their original
traversal. Published source variables carry no solver certificate. Composite
resolution and constraint scheduling still use their existing epoch-based cache
and solver passes.

Representation conversions distinguish layout, evidence, their respective effect
rows and code-expectation handles. Runtime cleanup distinguishes function/local
handles, and resolved bodies distinguish source expressions. Store-bound
services still enforce owner identity; equal integers from different owners are
not interchangeable. Dense legacy Core tables keep their existing word encoding.

Compiled `.blotdep` files contain typed dependency modules and their admission
metadata. Compiler identity, source changes, catalogs, nominal origins and
compile-time dependencies participate in validity checks. Native work counters
are instrumentation, not source-language fuel semantics.

Constant records keep unused generic fields in the evaluator until a concrete
use selects them. Calls and partial applications can retain those fields while
capturing dynamic arguments once. Anonymous closure keys include every static
capture. Retained admission matches the complete value, callable and evidence
graph, including aliases, against current values. Unknown correspondence
declines reuse. Captured generic values do not authorize a principal scheme
receipt. Named partial static helpers still depend on their enclosing job's
validated static roots rather than an independent capture key.

Successful retained revisions also own optimizer inputs and optional transformed
function bodies. Exact source instructions, signatures, direct callee bodies and
completed ownership summaries authorize reuse. A transitive change to a callee's
escape behavior invalidates callers even when their instructions are unchanged.
Summary preparation uses deterministic function order before either fresh
optimization or reuse. Numeric function IDs currently remain part of the key;
index movement conservatively loses reuse. Final Wasm assembly still runs.

Principal query receipts also preserve compiler memo effects. An admitted
literal-only edit can reuse an empty inference result while replaying exact
nominal-cache writes and owner-translated closed call proofs. Absence and
negative nominal reads are dependencies, as are completed scalar types. This
path still requires an empty initial call-proof table and the complete source
input projection; it does not yet provide general per-body incremental
inference. Actual constant evaluation and executable validity remain
independent.

`backend_checkpoint.zig` serializes principal receipts and optimized body
candidates for process restarts. The portable graph owns its arrays and strings,
with no native pointers, allocator capacities or evaluated source values. A
complete source image (including literal bits) and observed semantic inputs gate
principal-proof import. Optimized bodies use the ordinary exact
input/callee/lifetime matcher. `restart_cache.zig` persists these candidates by
compiler identity and entry under the platform cache directory, using atomic
replacement. The CLI writes only successful builds. The server writes its first
committed revision before replying and its latest committed revision on graceful
close; editing does not add a checkpoint write per build. Missing, corrupt and
unavailable caches fall back to ordinary compilation. Explicit checkpoint
import/export remains available. This is separate from `.blotdep` frontend
bundles and from the more permissive in-memory literal projection.

## Ownership and memory

IDs and side-table spans survive array growth. Hashes locate candidates;
structural equality and complete semantic evidence decide reuse. Mutable query
scratch is released explicitly. Published immutable modules own their tables.
The solver preserves cursor-relative chronological substitutions; replacing it
with ordinary union-find would change semantics without an admission proof.

`region_arena.zig` owns temporary region storage. Each active inference region
leases its own arena, exports evidence into the Session, then returns only raw
capacity. Small allocations use bump blocks; large buffers use reusable size
classes and can grow through the backing allocator. Reset never allocates. A
pool retains at most 64 MiB, and temporary allocator wrappers cannot borrow or
populate another owner's pool. Checker pending obligations and imported-scheme
scratch use independent leases; Checked and frozen-Core tables remain durable.

Arrays are contiguous. Lists use persistent AVL trees with right-sized leaves of
up to 248 words. Exclusive end edits reuse slack and tree nodes; shared edits
detach one path and leaf. Branch copies freeze their children so both versions
remain independently editable. Ownership tokens are descriptor addresses plus
one, never tracing pointers to obsolete descriptors. Static data is immutable,
unused slots stay zero, and descriptors cache the current traversal leaf.
Word-element cursors also own an independent leaf cache, so interleaved forks do
not repeatedly evict one another. Source-body facts have one compilation owner;
bounded scalar collections can use locals and private rectangular append regions
can allocate their exact result. These optimizations consume typed structure,
not prelude names. The separate dense scalar-row fixture supports a broader
recursive layout experiment. Production collections now pack flat tuples and
records of up to 16 checked scalar fields. All construction, access, copying,
cursor and constant paths use the same checked row stride. Extracted rows own
their storage; ordinary scalar replacement can eliminate temporary boxes. List
trees store spans of words; typed operations translate logical row counts and
positions. Rows may cross leaves, and List/Array conversions copy spans
directly. Scalar field projections can read packed data without a box. Packed
cursors and direct loops reuse leaf spans; boundary-crossing fields use checked
word lookups. A bounded direct-call expansion pass exposes ordinary allocation
producers to scalar replacement. Generic iterator step/cursor allocation remains
a separate limit.

## Limits and measurement

The native evaluator defaults to 1,000,000 operations, executed nesting depth
256, 1,000,000 values and 4,194,304 child slots per evaluation session. It
diagnoses exhaustion; these limits do not count retired Bend evaluation steps.
Separate structural type-depth, backend and Wasm memory constraints are enforced
at their boundaries. Source call-chain length does not consume the execution
depth budget.

Measure fresh processes, dependency population, first edits, subsequent edits,
no-ops and failed-edit recovery independently. Include transport and output
publication in public edit measurements. Report requested allocator bytes
separately from process RSS. Keep deterministic output and executed guest checks
alongside latency measurements. The gdev targets are approximately 500 ms cold
and below 100 ms incremental, without a hard real-time guarantee. The project
API's `profileBackend: true` and the CLI's `build ... --profile` (also
`build-project`) add nested phase timings and the eight slowest inference
regions as `backend_timing.work`. Detailed clocks are disabled by default so
profiling does not tax ordinary hot paths, and an unprofiled record omits
`work`. Deterministic work counters (`work_counters` in CLI stats,
`workCounters` in the project API) are always on: inference regions, region
scopes, callee body collections split into closed (memoized) and unresolved
(re-collected), solver passes and constraint visits, and occurs steps. Budget on
these, not wall time.
