# Native compiler implementation contract

This directory is a handwritten Zig 0.17 compiler. `grammar.baba`,
`compiler/guide.md`, executable behavior tests and `std/` are the source of
language behavior. Frozen reference fixtures are test data, not runtime
dependencies. No generated semantic functions or boxed `Value` runtime may be
imported into this compiler.

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
Small bodies inline with inherited cleanups, and larger or deeply composed
bodies use private functions. Runtime arguments evaluate once in their original
order. Private functions have ordinary invocation-local cleanup and provider
scopes.

Individual compilations use owned arrays and explicit deinitialization, not an
unbounded arena of obsolete inference versions. Published syntax/typed bodies
are immutable. Scratch state is released before final output publication.
Historical solver semantics use dense version records and explicit cursors;
ordinary union-find is not an assumed substitute for the reference behavior.

Solver-owned variables may retain a certified resolution in their unused node
field. A closed answer survives unrelated appended substitutions. An open answer
also checks the remaining variable's latest write against its chronological
lower bound. Only current queries of principal variable nodes use this path;
historical views keep ordinary traversal. Rollback, physical type/effect edits
and saturated certificate clocks revoke these answers. The certificate is
nonsemantic metadata and is stripped when variables leave the solver owner.

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

Call summaries give each closed first-order job its own chronological solver.
The session drains an explicit job stack keyed by source target, complete input
evidence and interface-checking mode. A caller imports only a fully solved
arrow. A declared global source function with no residual scheme predicates
already proves its quantified inputs, including callbacks and effect rows;
ordinary call checking may import that scheme without collecting its body.
Computed values still require capture proofs, and source-interface checking,
selected captures and complete demand-body checking retain ordinary collection.
Other result-directed obligations, lexical captures and higher-order boundaries
keep ordinary collection. Active recursive targets share their inline region.
Failed speculative jobs publish no diagnostic; fallback preserves the caller's
argument witness sites and deferred-member context. An independently completed
callee proof may survive an enclosing caller's failed qualification.

Summary jobs own their solver and scratch until completion or session teardown.
Evidence copied into the session may outlive a job; solver IDs and source
borrows may not. The execution depth budget applies only to executed expressions
and patterns. Structural type-depth and storage limits remain separate.

The extension contract is [General call summaries](CALL_SUMMARIES.md). It keeps
principal summaries separate from caller-selected judgments, requires explicit
capture and residual-obligation inputs, and defines component-atomic publication
and authoritative diagnostic fallback. These extended summary forms remain
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
releases each member once, without runtime graph traversal or reference
counting. Each individual recycle still frees only its own storage. Escaping a
parent also escapes its reachable children. Unknown field reads/copies,
overlapping writes, conditional field provenance, cross-segment construction and
invalidating calls reject the proof. Reference-overlap checking has a bounded
work budget and conservatively declines wider proofs. Dynamic shared/cyclic
ownership and reclamation of escaping effect payloads remain required before
tracing can be removed.

Private provider heads and State/request cell IDs never enter source values or
closures. `runtime_cleanup.Stack` records their releases at construction and
tracks a checkpoint at each return/break target. A normal exit emits its suffix;
a cancellation emits all active scopes, including inherited inlining scopes. The
cleanup calls bypass cancellation guards. Demand forcing registers a reset only
on its cancellation path. Releasing private storage does not release its
payload: callbacks, State values and demand memo results may outlive that scope.

All optimizer passes use `runtime_ir` opcode/call contracts. New opcodes require
an exhaustive stack/effect definition; there is no fallback binary arity. Memory
word types do not prove pointer roles. `runtime_pipeline` owns at most the input
and next transformed body, releasing the input after a successful replacement;
failure must not mutate the retained function or fragment.

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
and conversion. Reference-valued elements keep tracing; machine i32 alone is
never evidence that a word is scalar. Runtime list branches remain pointerful.

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
crossing. The four-word cursor stays in the previous 32-byte allocation class.
Serialized cursors start without a cached leaf. Every stored pointer remains an
allocation base and published cursors are initialized once, never mutated.
Packed-row cursors keep logical positions with a private leaf cache whose base
counts words. Direct loops retain their own leaf span and a bounded stack of
pending right subtrees. The private stack roots the original collection and is
cleared before use; its references are allocation bases. Each tree edge is
visited at most once, independently of descriptor-cache changes. Each request
consumes the immediately next leaf: direct loops read every word in order,
including fragments of crossing rows. Stack-position locals may contain private
interior addresses; the stored collection and subtree references remain
allocation bases. The balanced tree's word bound fits within 64 stack entries,
and a checked overflow traps instead of writing past the private storage.

Scalar-only row views use transient Wasm address locals while that collection
root remains live. They never enter source values, captures or heap fields. Rows
crossing leaves are copied in raw word spans to one lazily allocated scalar
buffer per loop activation. Copy sizes are selected from the checked row width;
projection offsets come from the canonical flat layout. The buffer is reused
only after the previous view's last possible use. The inner row loop is bounded
by the current leaf; the outer loop handles crossings and the final logical
length, recovering the logical row index only at a leaf boundary. Empty loops
allocate neither buffer. Normal exits, breaks, returns and cancellation release
private traversal storage exactly once; optional cleanup skips unallocated
storage. Serialized cursors start uncached and retain allocation-base fields.

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
before element evaluation. Ragged/filtered/effectful regions remain ordinary
builders. Production packed collections use the flat-row rule above; the
recursive packed scalar-row planner remains a separate fixture.

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

Static closure keys retain binding-to-value roots. Admission compares the whole
captured graph and records only proven old-to-current value correspondences; it
never clones an unvalidated value to make a key match. Dynamic capture slots
still require known layouts. Static generic slots may remain erased because
their complete evaluator graph supplies the code identity, not a reusable
principal scheme. Capture environments evaluate and store dynamic arguments once
in source order.

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

## Semantic and backend boundaries

`types.zig`: an owned compact type table and chronological constraints with
occurs checks, rollback and cursor-relative resolution. Invalid inference is a
diagnostic; unsupported features must explicitly decline. Frozen principal
schemes belong to declarations, instantiated evidence belongs to uses.

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

The CLI, native checks and executed-Wasm tests are the production gates.
Validate all declarations, including unused ones. Keep effects, staging, guest
ABI and fresh-versus-retained output checks intact during performance changes.
