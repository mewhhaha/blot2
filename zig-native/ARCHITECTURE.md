# Native compiler architecture

The compiler uses one native project pipeline for full builds and retained
revisions. Deno supplies the optional client, formatter and guest host; it does
not parse, infer or stage source for compilation.

The [25 October architecture review](../COMPILER_ARCHITECTURE_REVIEW.md)
separates this implemented design from proposed changes to semantic completion,
incremental queries and development specialization. Current measurements and
qualification are in [CT110](CT110_QUALIFICATION.md).

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

[Source areas](SOURCE_AREAS.md) groups parsing, checking, evaluation, emission,
reuse and runtime code by responsibility. Mutable construction and immutable
publication have separate owners:

- [Checker](CHECKER_OWNERSHIP.md): Engine owns catalog indexes; scheme import
  owns its temporary maps and borrows only Source and the destination store.
- [Core](CORE_OWNERSHIP.md): Module owns frozen tables; CoreBuilder owns mutable
  tables and scratch through transactional freeze.
- [Evaluator](EVALUATOR_OWNERSHIP.md): value storage, inference-region capacity,
  specialization caches and retained receipts have distinct lifetimes.
- [Backend](BACKEND_OWNERSHIP.md): planning, representations, static data and
  function emission own their state; CompileRun owns one fallible attempt.

The owned body auxiliary schema covers every checked metadata table and nested
catalog edge. Relocation follows actual declaration syntax and parser ordinals;
borrowed AST pointers and old proof receipts do not supply current authority.
The ownership reports retain their original focused parity evidence. The
installed compiler passes the CT110 full gate; later compiler changes still
require qualification of their exact final source.

Specialization lives in `src/eval/specialization.zig`: it binds layout
expectations, solves type/effect obligations and returns owned mappings for a
source body. The service has no instruction builder or Wasm module. Retained
refinement hooks keep the existing stable artifact-owner identity and validity
checks. Dynamic member selection, closure captures and staging still request
semantic work as needed; this boundary does not assume every expression was
monomorphized early.

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

Task syntax retains an unresolved region until checking. Ordinary scope wrappers
carry a once callback universally quantified over its fresh region; generic
receive helpers carry a deferred input/result/effect relation. Frozen Core
validates exact spawn-wrapper bodies and the actual action captures at each
completed call. Partial spawn calls retain their already evaluated group in a
private carrier, and tuple collection uses one guest operation with ownership
transfer before result publication. These mechanisms preserve ordinary
aliases/imports without granting arbitrary higher-order functions transfer
authority. See [structured concurrency](STRUCTURED_CONCURRENCY.md).

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
Complete callback interfaces admit parametric jobs. Lexical jobs key the actual
captured value and alias graph; bounded recursive components infer jointly.
Incomplete inputs retain ordinary shared-region inference. Occurs checks visit
each resolved node once even when the type is a shared DAG.

[General call summaries](CALL_SUMMARIES.md) records the implemented principal
and call judgments, callback obligations, owned captures, recursive scheduling
and canonical session keys, with qualification and remaining fallback
boundaries.

Current variable resolution can reuse a node-local certificate across unrelated
substitutions. Closed results remain stable; open aliases watch the remaining
chronological variable. Physical type/effect edits and rollback invalidate the
certificate generation, and historical cursor queries retain their original
traversal. Published source variables carry no solver certificate. Composite
resolution and constraint scheduling retain separate bounded dependency and
epoch validity rules.

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
optimization or reuse. Structural candidates and exact graph correspondence
allow optimized IR to survive moved function IDs; references are relocated into
the current graph. Encoded body bytes additionally require unchanged physical
indices. Final Wasm assembly still runs.

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
replacement. The CLI writes only successful builds. On Linux the server's first
committed revision is written by a detached process that holds the cache-key
lock before the reply; other platforms write before replying. Graceful close
writes the latest committed revision if it changed; editing does not add a
checkpoint write per build. Immediate disposal does not join detached writers.
See the [project client](PROJECT_CLIENT.md) for cache waiting and directory
ownership. Missing, corrupt and unavailable caches fall back to ordinary
compilation. Explicit checkpoint import/export remains available. This is
separate from `.blotdep` frontend bundles and from the more permissive in-memory
literal projection.

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
up to 244 words. Exclusive end edits reuse slack and tree nodes; shared edits
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
cursor and constant paths use the same checked row stride. Observable extracted
rows own their storage; ordinary scalar replacement can eliminate temporary
boxes and transfer only fields demanded by each snapshot. List trees store spans
of words; typed operations translate logical row counts and positions. Rows may
cross leaves, and List/Array conversions copy spans directly. Scalar field
projections can read packed data without a box. Packed cursors retain checked
leaf caches. Direct loops walk pending subtrees with a bounded private stack
that roots the original collection. Scalar-only row uses and flat tuple bindings
can read private leaf views; crossing rows use a scoped scalar buffer. Escaping
rows keep owned extraction. A bounded direct-call expansion pass exposes
ordinary allocation producers and their forwarding wrappers to scalar
replacement. Bounded selected readers use guarded direct calls and retain the
owned indirect fallback. Exact identity-generated arrays share immutable
storage; emission and uniqueness analysis consume the same structural proof. See
[the runtime boundary report](RUNTIME_BOUNDARIES_QUALIFICATION.md). Generic
iterator step/cursor allocation remains a separate limit.

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
regions as `backend_timing.work`, and whole-build exclusive phase clocks (load,
lex, parse, check, lower, freeze, validation, backend and the rest) with each
phase's requested bytes, allocation count and peak-RSS growth as `phase_profile`
(`phaseProfile`). The counting allocator is inserted only for profiled builds.
Profiled project replies also expose `sessionHeap`: small-slab capacity, free
capacity, unused tails and rounded allocated capacity by size class, sampled
before publication while both revision owners can still be alive. It excludes
direct large mappings and is distinct from RSS and requested allocation bytes.
Detailed clocks are disabled by default so profiling does not tax ordinary hot
paths: an unprofiled record omits `work` and publishes an empty phase profile.
Deterministic work counters (`work_counters` in CLI stats, `workCounters` in the
project API) are always on: inference regions, region scopes, callee body
collections split into closed (memoized) and unresolved (re-collected), solver
passes and constraint visits, and occurs steps. Budget on these, not wall time.

### CT111 bounded implementation

The correctness-qualified CT111 snapshot extends checked interfaces to supported
inferred requirements with independent current-body proof, including checked
source aliases. Ordinary type nodes can exceed the proof reader's small lexical
table size; actual binders and storage definitions retain their bounds. Sparse
copyable row facts admit high row IDs. The source-only proof follows reached
declarations; package readers retain whole-module authority. An unsupported
proof returns to ordinary inference. Selected bodies, higher-order interfaces
and inferred member projections still need the existing body path.

A bounded retained family now shares immutable source principal graphs between
Sessions. It excludes mutable memo facts and evaluated inputs, checks exact
source/body correspondence, and releases unused graph leases at the next
successful publication. This does not retain the complete Generator-local
resolved body. Fragment lookup translates the current module owner into the old
capture before choosing a declaration bucket; full request, value, body and
capture comparisons still authorize every reuse.

Inference counters now attribute each region and its solver-node count to its
innermost stage at creation: general semantic work, specialization, body
preparation or prepared-body lowering. Those categories are disjoint counts, not
CPU time. Profiled region clocks also group caller sites by stage. They make the
remaining elaboration boundary observable. Written `result` requirements retain
the selected invocation row through checking and lowering; inferred conversions
keep their existing syntax. See
[the current work record](../COMPILER_CT111_WORK.md) for coverage, measurements
and qualification status.

### CT112 completed selected results

A completed selected query now carries its outer closure's completion and the
closure results frozen by the same solved region. After exact dependency and
resource checks, replay imports their semantic evidence and reserves all
publication storage before publishing the graph and completed keys together.
Canonical session replay remaps those IDs with the selected graph. Consuming a
restored result at its proved interface therefore needs no new inference region.

This is a bounded completed-result family. It does not grant completion from
typed views, does not drop observed negative memo facts, and does not retain
every elaborated body. Native receipts own the additional claims; the existing
portable schema omits nested claims and rechecks those closures after restart.
See the [CT112 work record](../COMPILER_CT112_WORK.md) for verification and
measurements. The generic development ABI remains a separate unfinished step.

### CT114 frontend ownership and work accounting

Each generalization now owns a flat candidate table, a type-variable buffer and
an effect-row buffer. Candidates hold checked numeric spans into those buffers;
growth cannot invalidate a stored pointer. Type-component scratch is reused
between candidates, and cleanup releases the whole unpublished workspace.
Discovery order and requirement closure are unchanged. Predicate-free schemes
retain their complete quantifiers but omit public-slot sharing analysis, since
they cannot produce a shared callee requirement.

`phaseProfile.checking` merges work from completed project-check invocations,
including candidate scans, imported schemes and normalization visits. Checker
calls during backend inference are excluded by phase. These measurements do not
participate in identities, admission checks or semantic decisions.

The [frontend review](../COMPILER_FRONTEND_REVIEW.md) proposes direct
instantiation from immutable producer interfaces, requirement dependency
tracking, and fewer copies across checked/Core/frozen boundaries. Those larger
representation changes remain unimplemented. The current changes preserve the
language and do not establish a sub-second fresh frontend.

### CT113 refinement work and cache limits

The refinement profile now counts whole fresh requests with exact admission,
publication and candidate-rejection flags, plus solver-node cost. It keeps 32
groups, an explicit overflow total, and eight heavy individual requests without
allocating per request. Private independent-call checks report their own work;
workers return counts for the coordinator to join.

The refinement Context has its own 8,192-record / 8 MiB buffer budget. This
removes measured fresh-build saturation without changing evidence admission.
Payload and lookup-work bounds remain fixed. The failed proof-recheck trials are
not included: missing proof provenance still prevents replay of many otherwise
matching body queries. See [the CT113 record](../COMPILER_CT113_WORK.md) for the
trial boundaries, memory tradeoff, measurements and qualification status.

### CT116 dependency reuse and fresh module workers

`check/scheme_dependencies.zig` caches the ordered free-type and free-row sets
of pending requirements. It reuses the solver's reverse frontier watches and
invalidates on relevant writes, physical edits, rollback, future IDs and ordinal
reuse. Projection queries retain their original work charging. Membership
indexes complement ordered buffers; they do not determine iteration order.

Live producer interfaces may supply completed immutable sharing summaries.
Imports relocate their public type/row positions and copy flags into the
consumer's owned store. Frozen interfaces and unpublished summaries fall back to
recomputation. This removes repeated analysis, while canonical graph copies and
checked/Core/frozen representation boundaries remain.

`reuse/project_check.zig` checks dependency-ready fresh modules in joined
batches. Workers own separate engines and stores, borrow immutable producer
interfaces and symbol storage, and publish into distinct slots. Generated names
are prepared before dispatch. A name miss, diagnostic or aggregate budget
failure discards speculation and replays serially. Allocation failures join
before returning; retained store allocators cannot refer to a temporary lock
adapter. Module checking defaults to four workers, independently of semantic
evaluation and codegen policy. Retained edits use their existing cutoff checks.

See [CT116 qualification](CT116_QUALIFICATION.md) for measured effects and the
remaining canonical interface-copy boundary.
