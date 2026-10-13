# Native compiler implementation contract

This directory is a handwritten Zig 0.17 compiler. `grammar.baba`,
`compiler/guide.md`, executable behavior tests and `std/` are the source of
language behavior. Frozen reference fixtures are test data, not runtime
dependencies. No generated semantic functions or boxed `Value` runtime may be
imported into this compiler.

[Module abstraction](MODULE_ABSTRACTION.md) specifies the public/private views,
opaque identities, storage contracts and exact cutoff laws required by tasks
052–053. It adds no executable visibility feature.

[Associated contracts](ASSOCIATED_CONTRACTS.md) specifies type members,
projections, implementation coherence and owned evidence for tasks 055–056.
These declarations extend qualified evidence without changing legacy associated
dispatch. Symbolic principal projections and complete selected witnesses remain
distinct claims; neither mutable solver IDs nor private catalogs cross the
public or portable evidence boundary.

## Storage and ownership

Source bytes are immutable UTF-8. Tokens refer to byte ranges. Identifiers use
`symbols.Symbol = u32`; zero is absent. `symbols.Pool` owns one byte buffer with
offset/length entries and stable numeric IDs. Hashes locate candidates; exact
bytes decide identity. Array growth must never invalidate hash keys or handles.
Immutable Core keeps one owned spelling for each record field symbol it uses.
Runtime structural record slots follow UTF-8 spelling order, independent of
source evaluation order and symbol relocation. Constructor tuple views keep
declaration order and convert explicitly at the representation boundary.
Evaluator records retain slot names beside their values; every projection
matches names rather than assuming an annotation's field order. Merge results
intern their ordered name spans, so repeated updates do not grow shape metadata.

Specialization diagnostic provenance consists of owned unit IDs and byte spans,
scoped to the current requesting use. It never participates in semantic or
executable cache keys. Secondary filenames are copied before a project
preparation is released. An inferred-parameter bit retains source provenance
after callback inputs have been concretized; dependency schemas and exact body
stamps include this bit.

AST IDs, type IDs and instruction IDs are 32-bit indexes into contiguous owned
tables. Lists are spans in side arrays. There are no per-character nodes,
semantic linked lists or persistent tree maps in hot mutable state.

A staged callable may accept data containing unobserved open callback rows.
Selected source emission retains that callable and its exact Session-owned
captures without materializing a closed semantic header. It rechecks the body
against the selected concrete type positions and imports the caller's frozen
argument signature, preserving known effect labels beside open tails. A pure
implementation can run under a larger caller ambient; parameter and result rows
retain their exact checks. These live hints disable semantic receipts and
executable fragment reuse. They never enter a dependency archive or certify
erased type positions. A synchronous projection copies partial physical shapes
out of the solved region without retaining solver IDs; open rows stay unknown.
Ordinary selected named and closure queries also copy partial physical shapes
when semantic export cannot represent them. Those queries publish no semantic
receipt. Reconciliation fills erased positions and unknown rows while rejecting
conflicting known heads, physical slots and effect rows; it never defaults a
language type. Small bodies inline with inherited cleanups, and larger or deeply
composed bodies use private functions. Runtime arguments evaluate once in their
original order. Private functions have ordinary invocation-local cleanup and
provider scopes.

A generalized local call result with one concrete checked use may prepare its
private storage at that instance. Only quantified local holes gain physical
facts; known layouts still reconcile exactly. Captures, merges, carries and
multiple or unresolved instances decline this bounded proof. The source scheme
and semantic generalization remain unchanged. Substitutions belong to the owned
resolved Body, including encoding; they never become solver evidence.

Individual compilations use owned arrays and explicit deinitialization, not an
unbounded arena of obsolete inference versions. Published syntax/typed bodies
are immutable. Scratch state is released before final output publication.
Historical solver semantics use dense version records and explicit cursors;
ordinary union-find is not an assumed substitute for the reference behavior.

Solver-owned variables may retain a certified resolution in their unused node
field. A closed answer survives unrelated appended substitutions. An open answer
also checks the remaining variable's latest write against its chronological
lower bound. An unwritten future alias must be resolved again when the shared
type/effect clock reaches that alias's cursor, so its canonical principal view
matches ordinary traversal. Only current queries of principal variable nodes use
this path; historical variable views do not use that node-local certificate.
Rollback, physical type/effect edits and saturated certificate clocks revoke
these answers. The certificate is nonsemantic metadata and is stripped when
variables leave the solver owner.

Composite resolution certificates belong to the same solver, in a separate
bounded table keyed by root and chronological cursor. They retain owned numeric
IDs and a complete unresolved type/effect frontier, never pointers into scratch
storage. A hit checks the remaining variables, future-view clock and physical
generations. Rollback and saturated generations revoke reuse before recycled IDs
can be read. Recording a certificate requires a complete local record and
successful table allocation; failure cannot publish a partial answer. The
default cost policy retains only normalizations creating at least four nodes.
Larger frontiers and cheaper queries keep ordinary resolution. See
[resolution caching](RESOLUTION_CACHING.md) for the bounds and qualification.

Inference regions lease arenas that own their solver, constraints and scratch.
Small buffers use bump storage; larger buffers are recycled within size classes.
Large remapping preserves live neighboring buffers and every allocation header.
Reset performs no allocation. One session-owned pool retains at most 64 MiB;
oversized regions are freed. Only raw storage returns to the pool: no inference
answer, projection owner or source borrow remains accessible. Nested active
regions own separate arenas. A temporary allocator wrapper cannot take or
populate the durable allocator's slot. Published evidence uses the Session's
durable allocator. Checker pending obligations and scheme-copy spills have
separate arena leases; published Checked tables retain their original owners.
Callable-definition indexes read immutable Core and belong to the whole Session.
An emitter may memoize successful layout roots only while its source owner, type
mappings and row mappings remain immutable. Recursive conversions retain their
ordinary depth checks.

Constraint and data-alias scheduling metadata belongs to the inference region.
Regions with at most eight items of each kind use bounded scans; larger regions
own one lazily allocated pair of variable-indexed worklists. A growing region
switches before another whole pass. Reverse watches and ready bits retain
numeric IDs, never pointers into growing solver tables. Writes wake work in
source order; earlier items wait for the next pass, and aliases settle before
constraints. Rollback, physical edits and saturated generations revoke narrow
watches. Source collection and completed summary jobs explicitly wake their
dependent work. Larger or unsupported dependency frontiers retain conservative
write watches. Every queue buffer and owner is released with its region,
including partially allocated state. See
[indexed inference work](INDEXED_SOLVER.md).

Within one inference region, copies of the same closed semantic evidence may
share solver nodes. Keys include request depth; changing the depth limit revokes
the cache. Closed evidence contains no solver variables, so substitutions do not
invalidate it. Rollback, physical list edits, owner changes and saturated
physical clocks do invalidate it. Type sharing never merges independently scoped
variables. Pooled scratch clears these answers and their owners.

Closed frozen source types may likewise share one imported graph per region,
owner and request depth. Source classification belongs to the immutable Session;
open type/effect variables always keep their scoped imports. Physical mutation,
rollback and limit changes revoke the region's imported answers.

Completed refinement answers may be reused within one evidence owner only under
the same root, expected shape, type/row seeds, options and dynamic observations.
Only complete results with no evaluation or value publication qualify. Closed
call proofs accumulate monotonically within that Session; independently scoped
generic variables are never used as a principal cache key. The receipt owner
also exists in fresh CLI builds, independently of artifact recording. Keeping a
local query answer does not enable the emission journal or retain a complete
backend snapshot.

Across revisions, a refinement receipt distinguishes collected source bodies
from positive closed-call proof reads. An unchanged local body may survive a
transitive runtime-body edit only when every collected source remains exact and
every consumed call judgment has already been established in the new Session.
The ordered namespaces, semantic catalogs, expected shape, seeds, scalar reads,
plain-data facts and publication dependencies must still agree. This cutoff
grants no executable or compile-time-value reuse; those dependencies rebuild.

Call summaries give each closed first-order or callback-interface job its own
chronological solver. The session drains an explicit job stack keyed by source
target, complete input evidence and interface-checking mode. Result-directed
first-order jobs also key the complete expected result or complete arrow when
those are consumed. They use fresh source binders; open caller variables never
enter an independent job. A caller imports only a fully solved arrow. A declared
global source function with no residual scheme predicates already proves its
quantified inputs, including callbacks and effect rows; ordinary call checking
may import that scheme without collecting its body. Checked written predicates
on first-order global schemes are likewise imported with fresh scope variables
and the original argument witnesses. They must solve before a closed judgment is
published. Type-only associated/member selection and result-selected
construction may use that same checked scheme: the fresh scope already owns the
imported predicates and selected signature. The source receipt records the
implementation; selected capture/emission and complete demand checking still
collect its body. No caller-selected fact becomes a principal proof. Transitive
job admission classifies each reachable scheme once per immutable Session and
reserves capacity before publishing the complete classification. Source shape
and active-recursion checks remain local to the requesting job; a cached graph
classification does not override them. Computed values still require capture
proofs, and predicate-free source-interface checking, selected captures and
complete demand-body checking retain ordinary collection. Unsupported lexical
captures and incomplete callback boundaries keep ordinary collection. Active
recursive targets share their inline region. Failed speculative jobs publish no
diagnostic; fallback preserves the caller's argument witness sites and
deferred-member context. An independently completed callee proof may survive an
enclosing caller's failed qualification.

Admitted inferred first-order bodies also have bounded immutable principal
graphs owned by that source Session. Ordered constraints and callee edges retain
their original argument/result witnesses. Import freshens type and row binders
without copying transitive diamond paths. Optional principal inquiries may
export checked residual edges with source-owned first-order physical structure,
nominal identities, alias relationships and operation rows. They remain unsolved
and cannot certify a complete call or refinement receipt. Matching preserves
exact live alias classes; a fixed effect row cannot match an open caller tail.
Written header requirements are traversed in source order and remain mandatory
even when a body edge is deferred. Region-local header keys retain only public
slots consumed by those requirements, demanding the complete public interface
when a requirement also consumes a private binder. Open slots keep exact live
solver identity and chronology; rollback, recycled variables and saturated
history revoke reuse. Region-local header reuse schedules required work; it is
not a completed proof. Optional inquiries that use residual export retry
ordinary checking on semantic failure, preserving original witness diagnostics.
A residual edge is exported only when the callee's normalized call graph has at
least twice as many call paths as distinct bodies; a callee tree is collected
ordinarily. Both choices give equal judgments, so this is a cost policy, not a
semantic rule.

Raw and source-normalized principal graphs are separate owned objects. Source
normalization solves only immutable source equations and already-qualified
source interfaces; it never evaluates a caller or imports a caller-selected
implementation. Resolved type and row roots are copied into a fresh store with
no inference history. A newly revealed selected-method edge is checked before
its parent is published. Source dependencies follow those edges and are replayed
when the graph is consumed. Source completeness is a parametric interface
theorem, not a closed call judgment. Fixed source type heads, comparisons and
closed operation/handler rows may be proved here; unknown owners and rows stay
residual. Unsupported shapes decline without publishing a partial theorem.

Higher-order principal graphs retain a dedicated callback-use action with the
formal parameter slot, curried invocation stage, original argument/result
witness and complete source callback signature. Source solving verifies its
arrow and latent row equations but leaves the action unsolved: it is a
parametric relationship, not a proof of any executable callback or capture. An
imported graph freshens the same equations; a complete input-keyed job checks
them in its private solver. Callback input purity and concrete operation rows
remain exact, and returned or curried callbacks retain row aliases. First-order
data predicates used by dispatch and physical representation keep their original
domain. Separate bounded function-DAG checks admit summary interfaces, including
callbacks receiving or returning callbacks.

Source recipes classify the presence of lexical captures before optional graph
admission. A region carrying live capture inputs or code capture hints retains
ordinary checking for open higher-order graphs. A missing bounded recipe is also
conservative. Complete callback interfaces can still key independent type jobs;
the actual value owner checks its body, captures and provider observations. The
recipe classification schedules work and certifies no capture result.

Description and cache publication finish every ownership allocation before
installing a visible graph; out-of-memory never becomes a cached semantic
decline. Cycles currently decline optional principal publication.

Live lexical summary inputs own ordered capture bindings, complete interfaces,
alias ordinals, source/body identities, stored mappings and exact semantic graph
words. Source identities belong to the immutable session version; portable
revision keys remain separate work. Scalar bits, nested executable bodies,
provider creation identities and pending demand identities participate in key
equality. Unsupported, cyclic or incomplete graphs retain ordinary collection.
Aggregate examined-word/interface-visit budgets include declined admissions.
Interface selection projects only the scopes of values reachable from the
closure's captures; a capture-free closure has no key.

Each lexical job imports those inputs into a private solver and exports only a
complete session-owned arrow. Its owner still checks executable captured values.
It publishes no capture-free global principal proof or call receipt. Source
interface, complete demand-body and receipt/refinement observer paths retain
ordinary checking. Entry-interface and full-body view caches have distinct keys.
Complete monomorphic views preserve value aliases; generic views freshen.

Allocation failure abandons pending summary jobs without allocation, rebuilds
keys for independently finished jobs, and clears active state. It never caches
an allocation failure or resumes a partially collected job. Joint recursive
components and portable canonical keys remain tasks 007–008.

Summary jobs own their solver and scratch until completion or session teardown.
Evidence copied into the session may outlive a job; solver IDs and source
borrows may not. Compile-time evaluation counts nested function calls against
`Options.max_call_depth` (4,096) and reports `constant_recursion` at the
outermost call of the failing evaluation. `Options.max_depth` (65,536) bounds
nested executed expressions and patterns across calls; it guards the native
stack, which `main` reserves at 1 GiB for the compile thread. Structural
type-depth and storage limits remain separate.

The extension contract is [General call summaries](CALL_SUMMARIES.md). It keeps
principal summaries separate from caller-selected judgments, requires explicit
capture and residual-obligation inputs, and defines component-atomic publication
and authoritative diagnostic fallback. Component-atomic publication remains
implementation work.

Constant collection values publish immutable child spans. Session-owned growth
buffers may write outside every published span and extend only the latest span
in that buffer. Branching from an earlier version copies its visible children.
The runtime uniqueness proof never authorizes mutation of evaluator values.
Reserved slots count against the child budget; private growth metadata is not
part of snapshots or imported value templates.

An admitted indexed-construction region owns a separate child buffer, copied
from its immutable input once. Finite nested loops and scalar carries use the
ordinary evaluator; only proven unobserved indexed writes target this buffer. No
intermediate collection reference may escape, be captured, or be read by an
arbitrary expression. A frame-qualified private carry is never a published
value. Freeze once at the region boundary; discard scratch on failure.

Runtime lists use balanced trees with right-sized leaves and copy only an edited
path when shared. Ownership tokens are not GC pointers. Detaching a branch
freezes both children, so either surviving version may later be consumed
exclusively. All pointers remain allocation bases; spare words stay zero. Empty
lists reuse immutable descriptors in reserved arena metadata. Whole slices,
empty concatenations and identical-bit replacements may share a descriptor only
after freezing it: later consuming edits must detach that descriptor too.

The symbolic lifetime pass records one owning allocation and local/fixed-offset
borrows. Direct-call summaries record bounded borrows and fresh owned results;
recursive and opaque calls remain conservative. A returned allocation transfers
ownership only when it has no other escaping or embedded alias. A single-result
summary cannot transfer a self/back edge hidden in its returned storage.
Structured control-flow liveness releases storage on every edge ending a proven
lifetime, including branches, early returns and loop exits. Branch operands and
label depths remain unchanged. Conditional definitions must dominate their uses;
unknown or out-of-range offsets and multiply assigned locals reject the proof.
Calls that can invalidate arena storage form a barrier. Assembly owns scratch
and output; retained instructions and fragments remain immutable.

Known private pointer stores and dominating exact field loads form closed
allocation groups. Shared children and cycles may belong to one group; liveness
is the union of its members' uses. Every member must be constructed in the same
straight-line segment, with its own valid allocation-base local. An exit
releases each member's temporary owner once. In tracing modules each recycle
frees only its own storage; in counted modules it drops that member's counted
tracer lease and zero-count destruction follows typed edges. Escaping a parent
also escapes its reachable children. Unknown field reads/copies, overlapping
writes, conditional field provenance, cross-segment construction and
invalidating calls reject the proof. Reference-overlap checking has a bounded
work budget and conservatively declines wider proofs. Dynamic shared/cyclic
ownership and reclamation of escaping effect payloads remain required before
tracing can be removed.

[Ragged builders](RAGGED_BUILDERS.md) specifies bounded count/fill admission,
direct final storage, ownership and ordinary fallback for dependent or filtered
collection construction.

Ownership roles come from checked layouts, never from machine types. The emitter
records each created function's parameter roles and precedes each constant-size
allocation with an `ownership` annotation run giving its word roles
(`runtime_ir.Ownership`). Annotations are never encoded, never count as code for
size heuristics or machine-code sharing, and describe an allocation only when
their terminator directly precedes its size constant. The lifetime pass treats
only non-scalar `i32` parameters as candidate addresses, and a tracked
allocation stored into a scalar word escapes and counts as a `role_conflict`;
correct emission produces none. Unknown roles stay conservative. A captured
closure template's word is its environment pointer.

Private provider heads and State/request cell IDs never enter source values or
closures. `runtime_cleanup.Stack` records their releases at construction and
tracks a checkpoint at each return/break target. A normal exit emits its suffix;
a cancellation emits all active scopes, including inherited inlining scopes. The
cleanup calls bypass cancellation guards. Demand forcing registers a reset only
on its cancellation path. Releasing private storage does not release its
payload: callbacks, State values and demand memo results may outlive that scope.

Admitted local demands use the prepared dynamic use counts: never/once need no
memo slots; repeated uses share a ready bit and typed result local. Reset both
at each call-site execution, outside any callee loop. Reference-only aliases
borrow that same state. Commit the result before setting ready, only after
normal completion. Encoding borrows the lexical emitter for deferred bindings,
with a flattened snapshot of force-site cleanup obligations; the snapshot owns
its action array and preserves cancellation order without a parent cycle.
Managed memo results join the typed roots of forever-loop collection, including
active enclosing admitted calls. Emitter parent links and inline-demand slices
are synchronous stack borrows and never enter retained plans, Core or runtime
values. Unknown use summaries keep the bounded preparation proof; escaping
summaries and incomplete admission retain ordinary cells.

All optimizer passes use `runtime_ir` opcode/call contracts. New opcodes require
an exhaustive stack/effect definition; there is no fallback binary arity. Memory
word types do not prove pointer roles. `runtime_pipeline` owns at most the input
and next transformed body, releasing the input after a successful replacement;
failure must not mutate the retained function or fragment.

[Persistent roots](PERSISTENT_ROOTS.md) adds checked result roles and entry
status without widening `runtime_ir.Function`. Scope annotations lower only on
the whole-module admitted route. Each allocation's counted lease belongs to one
journal slot; moves preserve that owner and copied slots retain independently.
Lease retirement clears the slot/header links before releasing. The reserved
cycle link cannot serve both the journal and a cycle queue simultaneously.
Checked globals and mutable static reference fields publish through one typed
module owner table. Scalar fields never add edges. Optimizer context includes
root mode and owner-table geometry; start bodies cannot reuse an old table size.
ABI 3 private entry/leave hooks preserve the public value set and copy numeric
results before leave. [Suspended ownership](SUSPENDED_OWNERSHIP.md) admits exact
generated host imports and checked request graphs with the same counted journal
through JSPI. Failed leave terminalizes active evaluating demands before
retirement; request cancellation resets them to pending. Externref cleanup and
revoked-descriptor checks prevent a strong ready memo from rebinding an old host
closure. Unknown imports retain the complete tracing fallback.

Optimized body captures own their inputs and outputs. Reuse requires exact local
instructions and types, called bodies, call signatures, arena roles and
completed callee lifetime facts. Compute summaries in deterministic order before
selecting cached bodies; cache hits must not change recursive summary
observation order. Failed assembly discards its candidate capture and preserves
the previous one.

Function positions are relocations, not body identities. Relocation reuse checks
the complete direct-call graph, including cycles, imports, globals, signatures
and every completed lifetime summary. Each old call target must map consistently
to one current target. Rewrite only an owned output copy; ambiguity or bounded
proof exhaustion declines reuse.

Compilation tiers belong to the session and to optimized captures. Development
mode may omit scalar replacement and automatic vectorization, but never
checking, evaluation or required cleanup. Cross-tier optimized bodies cannot be
reused. Optional machine-code sharing compares complete instruction/type
sequences; hashes only select candidates. Source/evidence identities, logical
fragments and indirect table slots remain separate. Public functions retain
distinct Wasm identities. A previously folded body must run optimization if an
edit separates it again; absence of an optimized result is not proof that no
pass was needed.

Concurrent optimization borrows only immutable functions and fully prepared
lifetime summaries. Each worker owns a bounded reusable scratch arena and clones
surviving output into the synchronized parent allocator. Every job joins before
output publication, failure cleanup or owner destruction. Small workloads stay
serial. Scheduling cannot change emitted bytes or cache validity.

The experimental optimizer archive stores owned portable values, never native
pointers or allocator capacities. Compiler identity, bounded decoding and a
checksum protect the format; they do not authorize semantic reuse. Every loaded
body still requires the ordinary exact matcher against fresh machine inputs and
completed callee lifetime facts. Automatic disk-cache loading uses these same
admission rules; finding a file never proves semantic validity.

A backend checkpoint also owns eligible principal-query type/row results and
their closed call evidence. It contains no Core pointers, native capacities or
evaluated values. Exact ordered Core/catalog and symbol/producer images
(including literal bits) precede dynamic input validation. Re-intern imported
closed evidence into the current session, validate all targets and reserve all
publication capacity before publishing any memo or call proof. Providers,
generative identities and unbounded graphs decline. Source-image equality alone
does not authorize a query whose observed inputs differ. Every lookup clears the
preceding lookup's borrowed input key, including an in-memory hit.

Portable nonempty results validate every source variable and effect-row
variable, reject duplicates and import every evidence graph into the new owner.
Complete dynamic input recording is required. Failed imports publish no memo or
call certificate; ordinary compilation remains available.

Only a committed successful revision can export a checkpoint. Export never
advances its revision; failed edits preserve the last successful export. Loading
is optional, bounded and compiler-versioned; unsupported or corrupt candidates
fall back to fresh work, while allocation failures propagate. Source and runtime
evaluation still run. Automatic persistence is best effort: cache read, decode,
encode and write failures (including allocation failures) may discard only the
optional candidate, never a successful compilation or the last complete file.
Atomic replacement publishes complete bytes after a successful build or
committed revision. The server saves its first successful revision and the
latest one at graceful close. Explicit checkpoint import still propagates
allocation failure to its caller.

Checked scalar element layouts select pointer-free array allocation and list
leaves. The descriptor carries this fact through cloning, structural operations
and conversion. Reference-valued elements use typed owning fields when the whole
module is admitted, with tracing available during transition; machine i32 alone
is never evidence that a word is scalar. Runtime list branches remain
pointerful.

Collection elements that are flat products or structural records with 1–16
checked scalar fields use consecutive payload words. Source lengths count rows;
indexing, overflow checks, copies and edits use the checked row stride.
Constants and runtime constructors share canonical field order. Observable
extraction creates an owning row allocation; no interior pointer escapes. Direct
List loops may borrow a row only when every use selects a checked scalar field,
or a flat tuple pattern binds scalar values. Aliases, captures, returned rows,
implicit row carries and unknown forms retain owned extraction. Scalar
replacement may eliminate that box under its ordinary proof. Raw word copies
preserve floating-point bits. List descriptors and tree ranges count storage
words; typed emission converts logical counts and positions. A row may cross
leaves. Intermediate word edits stay private until the entire row is published;
only the first edit consumes a possibly shared input. Conversion copies spans
and adjusts the private Array header back to a logical row count. Direct scalar
projections retain evaluation and bounds checks without allocating an extracted
row. Nested, nominal, reference-bearing, erased and wider rows keep the one-word
element representation. Numeric host arrays retain their existing ABI.

State plus memoized demands can construct real cycles: a demand may read a
closure from State and cache a result that reaches that same demand. Clearing
the State cell must not clear the cached result. The cycle-reclamation law in
`tests/arena_gc_execution.test.ts` preserves this behavior and bounds discarded
cycles in a long-running loop. RC without cyclic ownership handling is not a
valid collector replacement. In particular, do not weaken memo fields, clear
memoized results on State writes, or assume closure graphs are always acyclic.

[Shared and cyclic ownership](SHARED_OWNERSHIP.md) specifies typed
strong/borrowed roots, iterative destruction, suspension ownership and localized
trial deletion for tasks 030–035. The tracing runtime remains until replacement
qualification. [Typed RC transition](SHARED_RC.md) describes current admission,
counted tracer leases and the shared retirement path.

Wasm values live in linear memory, with a nonmoving tracing arena collector and
free lists. This does not use the Wasm GC extension. Ownership analysis permits
in-place updates and allocation elimination; it does not prove every object's
lifetime. Forever loops collect after allocation traffic reaches the larger of
64 KiB and a quarter of the arena's high-water mark, including startup data.
Their activation floor pins earlier objects, which are traced together with loop
carries, providers and static roots. Collection must not run on a fixed
iteration cadence: that repeatedly scans large retained collections even when
each step allocates only a small cursor.

Small aggregate scalar replacement requires full initialization before aliasing
and fixed field offsets. Every lexical version and loop carry owns separate
scalar locals. ABI values, captured/escaped values and GC roots remain boxed.
Each snapshot stores only its demanded fields. Demand propagates backwards
through every alias/carry edge to a fixed point; all source field values are
read before destination writes. Dropped fields still evaluate their operands.
The pass transforms an assembly copy, preserving retained symbolic fragments.
Direct loop patterns containing only bindings, wildcards and products need no
failure blocks; their local definitions dominate the loop body. Patterns with
runtime tests retain the failure path. Generic iterator lowering still creates
step/cursor values, and these are not universally eliminated. Before scalar
replacement, small straight-line direct callees containing one bounded
allocation can be expanded at the call site. Admission excludes other calls,
control flow, global/host operations and reads of uninitialized locals.
Arguments evaluate once, and traps stay at the original call position. Expansion
is bounded to 96 callee instructions, 64 locals/parameters and approximately
4,096 caller instructions. Optimized-body reuse checks the full callee body; the
development tier skips this optional pass. Ordinary source inlining has a
four-node budget, expanded to 64 for aggregate results inside loops or known
callback arguments. Nesting is limited to six levels and expansion stops past
4,096 emitted instructions. These are structural cost limits, independent of
declaration names and source modules.

Word-element cursors own a leaf base and its logical start, separate from the
collection's lookup cache. Forks only consult that shared cache on a leaf
crossing. The four-word cursor uses a 64-byte allocation class with the 32-byte
ownership header. Serialized cursors start without a cached leaf. Every stored
pointer remains an allocation base and published cursors are initialized once,
never mutated. Packed-row cursors keep logical positions with a private leaf
cache whose base counts words. Direct loops retain their own leaf span and a
bounded stack of pending right subtrees. The private stack roots the original
collection and is cleared before use; its references are allocation bases. Each
tree edge is visited at most once, independently of descriptor-cache changes.
Each request consumes the immediately next leaf: direct loops read every word in
order, including fragments of crossing rows. Stack-position locals may contain
private interior addresses; the stored collection and subtree references remain
allocation bases. The balanced tree's word bound fits within 64 stack entries,
and a checked overflow traps instead of writing past the private storage.

Scalar-only row views use transient Wasm address locals while that collection
root remains live. They never enter source values, captures or heap fields. A
nonempty loop activation over multi-word rows allocates one scalar buffer of two
rows before its first iteration, so no allocation call sits on the per-leaf
path. Rows crossing leaves are copied in raw words into its second half. When
two leaves hold the row, two copies of one row width each end at their
fragment's end: the later leaf's block lands first, then the earlier leaf's
block overwrites the row's leading words and spills only into the first half.
Their discarded leading bytes may come from headers or neighboring objects, but
never from below the 256 reserved bytes or past a fragment's end. A row spanning
more leaves copies exact fragments with sizes selected from the checked row
width. Projection offsets come from the canonical flat layout. The buffer is
reused only after the previous view's last possible use. The inner row loop is
bounded by the current leaf; the outer loop handles crossings and the final
logical length, recovering the logical row index only at a leaf boundary. Empty
loops allocate neither buffer. Normal exits, breaks, returns and cancellation
release private traversal storage exactly once; optional cleanup skips
unallocated storage. Serialized cursors start uncached and retain
allocation-base fields.

After lifetime lowering has consumed pointer provenance, a straight-line U32 sum
may combine exact adjacent four-byte fields using vector loads and wrapping lane
addition. Every removed temporary has one definition and one read. The
transformation accesses exactly the original bytes, retains scalar tails, and
cannot cross cleanup calls or control edges. Floating-point addition retains its
original order. This pass must not move ahead of lifetime analysis.

Numeric construction proofs may use private locals defined independently on each
lane and unconditional exits from proved lexical blocks. Checked complete F32
row loads may share four same-factor products; scalar additions keep their
written order. Memory writes, calls, escaping control and exhausted proofs take
ordinary lowering. Transformed bodies own their locals/instructions without
mutating retained inputs. See[numeric SIMD qualification](NUMERIC_SIMD.md).

`function_facts` memoizes bounded source-body facts within one Generator owner.
Unknown dispatch/calls remain unknown, and inlined bodies retain the ordinary
executable dependency reads. A collection of up to eight scalar elements can use
locals when all its uses are finite traversal or intrinsic length reads;
literal-producing helpers and admitted consuming helpers share that path.
Elements and arguments evaluate once in written order. Captures, merges,
loop-carried collections, updates, returned values and opaque uses remain boxed.
Small-collection uses also justify the existing 64-node inlining budget.

`exact_builder` proves a private append region with up to four rectangular
finite generators. Bounds cannot read region binders, allocate, trap or perform
effects. The intermediate list must never escape or be observed. Admitted
regions allocate their final List or Array directly; count overflow uses the
ordinary path with its original failure order. Reference storage is cleared
before element evaluation. Effectful regions remain ordinary builders.
Production packed collections use the flat-row rule above; the recursive packed
scalar-row planner remains a separate fixture.

`ragged_builder` admits dependent bounds and filters using already selected
operation facts and bounded capture-free primitive forwarding spines. Exact body
dependencies invalidate changed adapters. A count probe borrows immutable inputs
and uses bounded traversal scratch; exhaustion resumes ordinary building.
Runtime filling reuses final-storage allocation and ownership. Staged counting
publishes no values and consumes no source fuel; ordinary filling preserves
every source charge, reserves exact private child handles and publishes once.
Neither scratch pointers nor borrowed interior row views enter published values.
See [Ragged builders](RAGGED_BUILDERS.md) and its
[qualification](RAGGED_BUILDERS_QUALIFICATION.md).

Executable fragment validity records each inlined source body and every static
value root. Exact source/catalog dependencies and complete
value/evidence/capture graph comparison authorize reuse; unsupported providers
and generative domains rebuild. Rebuilt dependency seeds may offer old pinned
fragments for admission. Candidate failure must preserve the last successful
revision and its owners. Within one compile, code and principal/query admission
share immutable semantic validation arrays through independently released
leases. Source owners, current Core, allocator and admission options must match;
executable body/value checks remain separate.

Successful revision candidates may retain frozen-Core/dependency validation
certificates. They own the validated module stamps and exactly the foreign
binding bounds and symbol/source bounds observed by validation. Retained pins
are still checked against their bytes. A certificate saves validation work; it
grants no interface, value or executable reuse. Only successful publication can
make the new certificate available to a later revision.

An already completed scalar constant no longer blocks its enclosing code
fragment when source admission, layout, scalar kind and bits match. Admission
never evaluates that constant. Replay records the ordinary constant job and
preserves evaluation counts; aggregate data and runtime globals remain separate.

Optional semantic workers reconstruct independent closed-call judgments in owned
Sessions. They borrow immutable source, scalar inputs and validation facts, and
copy all importer maps into private storage. They never share Gate reference
counts, solver state, evaluated values or diagnostic publication. Every worker
joins before the caller validates and publishes results in original input order.

The opt-in ready-component scheduler follows the same private-owner boundary.
One recursive component is one job. Exact canonical Options, closed type/effect
inputs and copied capture interfaces enter private Sessions; live value handles
and caller variables do not. All workers join before the coordinator imports
results into a staged evidence owner. Key validation and capacity reservation
precede allocation-free publication of every completed member. Source reads
touching active coordinator inference return to the serial SCC path. Completed
independent jobs and current-query certificates survive sibling failure without
granting executable or artifact admission. See
[SEMANTIC_JOBS.md](SEMANTIC_JOBS.md) for bounds, cancellation, source-unit
limits and qualification.

Static closure keys retain binding-to-value roots. Admission compares the whole
captured graph and records only proven old-to-current value correspondences; it
never clones an unvalidated value to make a key match. Dynamic capture slots
still require known layouts. Static generic slots may remain erased because
their complete evaluator graph supplies the code identity, not a reusable
principal scheme. Capture environments evaluate and store dynamic arguments once
in source order.

Refinement reuse records live in the Context-owned typed query table. Local
lookup preserves newest-first order; retained lookup preserves oldest-first
order. Hash buckets select positions, while exact source, shape, seed and
dynamic fact gates decide hits. Builders own complete dependency/result slices;
reserve all table and replay destinations before allocation-free publication.
Explicit record, payload, buffer-capacity and lookup bounds decline optional
reuse on saturation. Numeric handles remain scoped to their evidence/Context
owners. See [REFINEMENT_QUERIES.md](REFINEMENT_QUERIES.md) for limits and
qualification.

A projected principal query may retain an empty type/row result across primitive
literal edits only when its complete source input projection and recorded scalar
type reads match. It must begin without validated-call proofs and perform no
value evaluation, nested specialization or unrecorded runtime read. Nominal memo
inputs retain absence, true and false separately; internal writes preserve the
final value. Closed call publications are translated into the current evidence
owner, with source-defined nominal/effect identities checked. Reserve all memo
capacity before publication. The projected query certifies no runtime or staged
value: ordinary evaluation still runs and reports errors. Executable admission
uses its own source and captured-value checks.

The recorded region includes the independent summary jobs it drains: their
reads, publications and consumed jobs pass through the same recorder, so their
results are recorded work even when they publish no validated call. A job
finished outside that recording is an unrecorded call read. A principal-graph
description detaches the recorder but still reports its nominal memo reads and
publications to it in order. Source scopes a graph collected from another unit
are not dynamic reads for this key, which compares every module's source image;
source receipts admit sources per binding and still treat such a graph as
unknown.

Effect unification walks immutable label-span views. A left remainder keeps its
chronological cursor; extracting a right label resets that cursor just as
ordinary extraction does. Repeated operations, ordered substitutions, rollback
and the work limit retain their original behavior. Publishing fewer temporary
row headers must not collapse distinct historical variable views.

## Frontend interface

`token.zig`: `Tag`, `Token { tag, start: u32, end: u32 }`. `lexer.zig`:
`lex(allocator, source) !Result`, where Result owns a flat token array and
diagnostics; `deinit(allocator)` releases it. Preserve comments, numeric/Unicode
errors and layout behavior from source preprocessing.

`ast.zig`: `Id = u32`, absent ID zero; `Span { start: u32, end: u32 }`; `Tag`
with semantic syntax roles; compact `Node { tag, a, b, c }` and separate source
spans. `Tree` owns node/span/extra/root arrays and diagnostics. An extras list
is always `(start, len)`, never a head/tail. `Tree.node(id)` and `Tree.span(id)`
read immutable entries. Names are numeric symbols. Literal numbers carry exact
U32 or binary32 bits.

`parser.zig`: `parse(allocator, source, tokens, symbols) !ast.Tree`. Full
surface syntax is separate from semantic admission. Preserve import/declaration
order, fixity and written evaluation order. Grammar keywords `froM`/`wherE` are
private frontend markers; source accepts contextual `from`/`where` without
reserving them everywhere.

Document exact node fields in ast.zig before checker/backend consumers use them.
Lambda fields must expose parameter, annotations, and body. Declaration fields
must expose name, annotations, body and export modifier. No consumer should
recover semantic structure by reparsing source.

`check.zig` bounds each module's inference with
`ModuleOptions.max_inference_transitions` (1,000,000 steps by default).
Exhausting it rejects the module with one `inference_budget` diagnostic at the
innermost declaration being inferred (a solved field's owner, else the active
global, else the top-level declaration), naming that declaration and the budget.
The partially inferred engine is discarded; no other diagnostic from that module
is kept. Rejected modules may have empty declaration catalogs; project export
handling must preserve the diagnostic without assuming sentinel entries exist.
The budget is not a project or CLI setting.
The `budget-fixture` test executable runs these same CLI and server paths with
a build-local 256-step default and a distinct compiler identity. Routine guest
laws use it for rejection and recovery; `deno task test:compiler:stress` keeps
the production million-step exhaustion regression.

## Semantic and backend boundaries

`types.zig`: an owned compact type table and chronological constraints with
occurs checks, rollback and cursor-relative resolution. Invalid inference is a
diagnostic; unsupported features must explicitly decline. Frozen principal
schemes belong to declarations, instantiated evidence belongs to uses.

Recursive inference uses exact region-local body edges and heap scheduling.
Adding a late selected edge may merge components; restart unfinished joint
solver state before any member becomes visible. Publish a component's closed
interfaces together, while independently completed dependencies keep their
proofs. Open recursive instances share their monomorphic source root; closed
polymorphic instances require equal complete interfaces. No component key owns
or exports a solver variable. Summary scheduling has its own bounded transition
budget; exhausting an optional summary declines it and resumes ordinary bounded
inference without spending executed evaluation depth or fuel.

Frontend global bodies stay on their component stack after body checking until
selection, qualification and scheme predicates stabilize. Dependency discovery
respects lexical shadowing and uses an explicit worklist. Scheme predicates and
qualification diagnostics remain locally owned until every member can publish. A
queued selected method keeps an ordinary field obligation and yields to its
body's scheduler; an active recursive method retains its receiver requirement.
Source diagnostics retain their occurrence order. Allocation failure releases
all frames, staged predicates and diagnostic payloads.

`check.zig`: `check(allocator, tree, symbols) !Checked`; Checked owns expression
types, resolved local/global identities and diagnostics. Validate unused source
declarations too. Report unsupported semantic features explicitly; no silent
fallback or pretending an unsupported construct is valid.

Typed-hole snapshots own a bounded flat diagnostic graph and the strings inside
its node, edge, binding and requirement arrays. Cloning copies each nested name;
cleanup frees those names before the four arrays. No snapshot borrows source
storage or live inference tables. Capture the nearest 32 unshadowed bindings,
with one additional binding indicating truncation, without quadratic scope
lookup.

Dispatch explanations (`dispatch_explanation.zig`) own their operation, member
and operand strings. The checker attaches one to the diagnostic it has just
appended, built from member tables and resolved operand types without further
inference; speculative rollback frees the payloads of the diagnostics it drops.
The evaluator records a plain `DispatchRecord` inside its diagnostic, so copied
and restored diagnostics carry it without ownership. Its evidence names the
failing Session's store, and the backend spells it into `Result.explanation`
before that store is released. Explanations never change selection, its order or
which diagnostic is reported.

The CLI, native checks and executed-Wasm tests are the production gates.
Validate all declarations, including unused ones. Keep effects, staging, guest
ABI and fresh-versus-retained output checks intact during performance changes.

The Session-local canonical specialization cache owns its exact capture keys,
complete observation receipts and created value/child deltas. It never owns a
whole Session snapshot and never stores solver nodes. Its immutable evidence,
closure mapping and record-layout handles refer only to the same live Session. A
hit reconstructs fresh output values around the current capture handles after
revalidating reads. All publication capacity is reserved first; the final graph
and proof-map commit allocates nothing. Mutable creation state and unsupported
observations decline. Local canonical plans are not portable artifacts; existing
portable receipt import must prove source pairing and remap all owner handles.

Region allocation meters belong to the heap-stable leased Arena. Solver and
scratch adapters never point into a returned-by-value region and reset only on a
new exclusive lease. Logical client requests overlap backing block requests and
are reported separately. Capture collection retains handles, reacquiring child
storage after recursive growth. Frozen publication prepares scratch-owned edge
replacements, reserves all durable arrays, then reacquires/copies the original
span once; no scratch type ID or temporary allocator pointer enters the result.
Owned snapshot metering preserves the read-only copy API and returns slices
freed by its original backing allocator. See
[semantic allocation ownership](SEMANTIC_ALLOCATION.md).

The shared query tables retain distinct selected, principal, source-description
and open-residual claims. A completed selected receipt pins its evaluator owner;
a principal result never includes caller-selected implementations. Local source
templates own copied type Stores and freshly instantiate binders. Cache owner
and units pins stay outside canonical key data. Ordered fact validation and
bounded lookup precede every optional hit; budget exhaustion takes ordinary
checking. Private unsupported-source memos never become successful records.
Portable principal candidates remain archive ordinals within an immutable Reader
lease until full source/input/import/publication validation produces current
evidence. Their common index preserves wire order, and its lazy construction
releases every partial record on OOM before retry. See
[the migration and qualification](SPECIALIZATION_PRINCIPAL_QUERIES.md).

Successful revision inputs move into a typed source-validation record without
copying source bytes. Checked Core certificates own exact namespace/graph and
foreign-bound images and grant only validation reuse. Singleton source owners
retain their separate lifetimes and ordinary admission gates; optional oversized
certificates rerun validation. See [the qualification](SOURCE_VALIDATION.md).

Executable fragment and optimizer queries own complete read sets and result
ordinals within an immutable capture lease. Their shared table is sealed in
source order only after complete job/output ownership is established. Fragment
lookup preserves oldest-first order and its exact source, selected evidence,
capture, static-value and chronological replay gates. Optimizer lookup preserves
newest-first relocation order, exact instruction/signature/context comparisons
and completed transitive lifetime checks. Unsealed or saturated tables decline,
including the same-position optimizer path. Semantic interface stability never
certifies executable consumers. See [the qualification](EXECUTABLE_QUERIES.md).

Portable principal and optimizer records travel in typed sections that name one
claim, kind, schema and interpretation version. Decoding validates every
ordinal, evidence edge, body operand, control frame and record/input
correspondence before exposing an owner, then rebuilds native indexes from the
owned payload. Unknown versions or claims and corrupt or forged payloads are
optional-cache misses; no partial record survives a failed decode. Refinement,
canonical specialization, local templates, source validation and executable
fragments stay owner-local. See [portable query records](PORTABLE_QUERIES.md).

A checkpoint may also carry a complete previous-revision semantic owner: exact
checked Core per unit with certificate bytes, the namespace, evaluator snapshot,
slots, field locations and completed selected receipts. Decoding validates the
namespace, every Core graph and stamp, every snapshot ordinal and receipt before
rebuilding a Capture whose pins name the decoded Core. It serves only as the
query predecessor of a compile with no in-process previous revision, and the
ordinary Gate, Importer and Plan still admit each receipt against current
source. See [persisted semantic artifacts](SEMANTIC_ARTIFACTS.md).

Artifact pool fields are leased. A capture compares each plain pool slice with
the previous revision's leased slice and retains that lease when the content is
equal, copying otherwise; leases are taken during candidate preparation and
released by failed, rejected or discarded candidates, so commit stays
allocation-free and the published revision is unchanged. Captured slices are
immutable; a lease names one allocation, never a revision. Code that replaces a
pool slice must release its lease, never free it. See
[revision deltas](REVISION_DELTAS.md).

A retained fragment may replay an aggregate constant child when the current
value is already evaluated and its complete graph matches the old one; the child
is re-serialized in the current owner through the ordinary constant path, and
only the caller's exact root-address operands are relocated. Demand cells and
other generative or operational values rebuild their callers. See
[retained constants](RETAINED_CONSTANTS.md).

An edited module that is not structurally equal keeps the reuse gate enabled
only when its ordered semantic catalog is identical, including every operation
value entry: identity, arguments, signature, witness node and witness result.
Each entry belongs to the one declaration whose operation-value node names it;
definition equality compares the entry and scans its witness, and the dependency
walk follows it, so a changed provider, state initial value or witness dirties
exactly that declaration and its transitive consumers. An added, removed or
shifted entry still disables the gate for the program. A published dependency
certificate shares, by lease, the previous certificate's image of a unit only
when that image exactly matched the old pin and the current module is proven
stream-equal to it; every other unit is re-imaged. Matching still walks every
byte of the shared image. See [literal edits](LITERAL_EDITS.md).

A refinement receipt rooted in an edited module may replay when its root is
admitted by its own declaration: a body root by the declaration's exact
projection and identity, and a closure root when the gate recorded that such an
admitted declaration's exact projection reaches that closure catalog entry. The
receipt's facts still carry the interface cutoff: collected sources must be
exact, consumed call judgments need only unchanged identities and must already
hold in the new session. Retained executable fragments keep the transitive dirty
set, so executable callers of a changed body always regenerate. Hygienic loop
names are numbered within their top-level declaration. See
[body interface cutoff](BODY_CUTOFF.md).

A retained revision whose inputs equal the last compiled revision's except for
trivia (each changed source lexes cleanly to the same tokens and adjacency, and
size limits hold) publishes the last successful output and keeps the retained
state; the next real edit diffs against the last compiled sources. The reuse
gate compares obligations without their diagnostic spans, so shifted positions
revoke only the declarations whose node spans moved. See
[trivia-only edits](TRIVIA_EDITS.md).

## Module privacy and opaque storage

Declaration visibility is checked before publication of the public catalog.
Private declarations retain executable Core ownership but publish no names,
schemes, payload graphs or associated evidence. Public opaque interfaces expose
only nominal identity, public parameters and an exact one-word ABI/ownership
recipe. The defining Core owner proves that recipe against its private payload.
Generic recipes select a variable occurrence in the public parameter shape;
unknown or exhausted recipes cannot license a guessed pointer/F32 layout.

Opaque identity uses the original producer path and declaration name. Dependency
and backend artifact relocation translate its name handle alongside unit IDs;
reserved built-in structural identities retain their separate domain. Forwarding
preserves original kinds/targets and validates reachable producers within a
shared bounded graph walk. No private catalog can become public through a
source, dependency or checkpoint import. Delayed generic dispatch and field
resolution enforce the defining-module boundary too.

Erasure changes physical storage, never semantic identity: scalar payload bits
and reference payload addresses pass through unchanged. There is no wrapper
cell, tag, indirection or additional owned reference. Typed physical roles
govern aggregate storage, captures, callable results and staged relocations. All
new scans/proofs own their scratch, retain only plain descriptors and obey the
existing transactional revision and allocation-failure laws. See
[qualification and current conservative reuse limits](MODULE_ABSTRACTION_QUALIFICATION.md).

[Rolling reductions and summaries](ROLLING_SUMMARIES.md) specifies the ordinary
source APIs. Sequential folds preserve callback/F32 order; fast monoid/group
APIs require explicit pure, total algebra and consistent reducer captures.
Cached summaries retain checked reference roles and persistent versions. Their
implementation is ordinary source library code.

The source emitter may mark a fresh record, product or algebraic node as
immutable and acyclic only when its exact layout closes over scalar fields and
other immutable shapes. It checks every constructor of a nominal in the emitting
source unit, including unused variants. Foreign definitions, mutable containers,
callables, demands, providers, erased fields and exhausted proofs decline.
Repeated nominal layouts close an immutable recursive type proof; they do not
assert runtime pointer uniqueness. The checked canonical allocation receives the
existing no-cycle flag. Its typed edges, counts and iterative destructor remain
unchanged, and genuine trial closures still visit those edges. Copy/edit/static
routes either preserve their own exact proof or leave the allocation eligible
for candidates.

A named callable with exactly one applied argument may use that argument's
canonical reference as its environment when the checked first parameter layout
is a reference. The descriptor owns that edge directly; invocation borrows it.
Static serialization and later curry stages use the same selected layout rule.
Scalar, erased and multi-argument environments keep their ordinary boxes.
Machine signatures, typed descriptor edges and table relocation remain exact;
portable optimizer meaning distinguishes the direct representation.

A nonescaping scalar-only object may keep its fields in independent locals when
all allocations in its version/copy group have exact scalar roles. Anonymous
roots and acyclic flags for the removed object disappear; scope boundaries and
carry-slot clearing retain their original order. Unknown/owning fields and
demand-force markers decline. Source arithmetic, eager operands and F32 bits
remain exact; this grants no semantic or value-cache validity. See
[iterator state qualification](ITERATOR_STATE.md).

A closed private packed List cursor family may keep its four immutable version
fields in machine locals. Exact source uses, scalar row layouts and constructor
bodies license this representation; publication, captures and unsupported uses
retain heap cursors. Its binding/root slot contains the canonical collection
base, so collection follows the actual allocation header and owning tree. Every
backedge snapshots all fields before destination writes. Private scalar row
views and flat tuple bindings remain scoped to that live collection; no interior
pointer becomes a source or captured value. Constructor body reads participate
in retained and portable validity. See
[the cursor boundary](LIST_TRAVERSAL.md#private-packed-cursor-checkpoint).
