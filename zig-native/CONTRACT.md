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

Individual compilations use owned arrays and explicit deinitialization, not an
unbounded arena of obsolete inference versions. Published syntax/typed bodies
are immutable. Scratch state is released before final output publication.
Historical solver semantics use dense version records and explicit cursors;
ordinary union-find is not an assumed substitute for the reference behavior.

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
exclusively. All pointers remain allocation bases; spare words stay zero.
Empty lists reuse immutable descriptors in reserved arena metadata. Whole slices,
empty concatenations and identical-bit replacements may share a descriptor only
after freezing it: later consuming edits must detach that descriptor too.

The symbolic lifetime pass records one owning allocation and local/fixed-offset
borrows. Direct-call summaries record bounded borrows and fresh owned results;
recursive and opaque calls remain conservative. A returned allocation transfers
ownership only when it has no other escaping or embedded alias. A single-result
summary cannot transfer a self/back edge hidden in its returned storage.
Structured control-flow
liveness releases storage on every edge ending a proven lifetime, including
branches, early returns and loop exits. Branch operands and label depths remain
unchanged. Conditional definitions must dominate their uses; unknown or
out-of-range offsets and multiply assigned locals reject the proof. Calls that
can invalidate arena storage form a barrier. Assembly owns scratch and output;
retained instructions and fragments remain immutable.

Known private pointer stores and dominating exact field loads form closed
allocation groups. Shared children and cycles may belong to one group; liveness
is the union of its members' uses. Every member must be constructed in the same
straight-line segment, with its own valid allocation-base local. An exit releases
each member once, without runtime graph traversal or reference counting. Each
individual recycle still frees only its own storage. Escaping a parent also
escapes its reachable children. Unknown field reads/copies, overlapping writes,
conditional field provenance, cross-segment construction and invalidating calls
reject the proof. Reference-overlap checking has a bounded work budget and
conservatively declines wider proofs. Dynamic shared/cyclic ownership and reclamation of escaping effect payloads
remain required before tracing can be removed.

Private provider heads and State/request cell IDs never enter source values or
closures. `runtime_cleanup.Stack` records their releases at construction and
tracks a checkpoint at each return/break target. A normal exit emits its suffix;
a cancellation emits all active scopes, including inherited inlining scopes.
The cleanup calls bypass cancellation guards. Demand forcing registers a reset
only on its cancellation path. Releasing private storage does not release its
payload: callbacks, State values and demand memo results may outlive that scope.

All optimizer passes use `runtime_ir` opcode/call contracts. New opcodes require
an exhaustive stack/effect definition; there is no fallback binary arity. Memory
word types do not prove pointer roles. `runtime_pipeline` owns at most the input
and next transformed body, releasing the input after a successful replacement;
failure must not mutate the retained function or fragment.

Checked scalar element layouts select pointer-free array allocation and list
leaves. The descriptor carries this fact through cloning, structural operations
and conversion. Reference-valued elements keep tracing; machine i32 alone is
never evidence that a word is scalar. Runtime list branches remain pointerful.

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
Their activation floor pins earlier objects, which are
traced together with loop carries, providers and static roots. Collection must
not run on a fixed iteration cadence: that repeatedly scans large retained
collections even when each step allocates only a small cursor.

Small aggregate scalar replacement requires full initialization before aliasing
and fixed field offsets. Every lexical version and loop carry owns separate
scalar locals. ABI values, captured/escaped values and GC roots remain boxed.
The pass transforms an assembly copy, preserving retained symbolic fragments.
Ordinary source inlining has a four-node budget, expanded to 64 for aggregate
results inside loops or known callback arguments. Nesting is limited to six
levels and expansion stops past 4,096 emitted instructions. These are structural
cost limits, independent of declaration names and source modules.

Immutable cursors own a leaf base and its logical start, separate from the
collection's lookup cache. Forks only consult that shared cache on a leaf
crossing. The four-word cursor stays in the previous 32-byte allocation class.
Serialized cursors start without a cached leaf. Every stored pointer remains an
allocation base and published cursors are initialized once, never mutated.

`function_facts` memoizes bounded source-body facts within one Generator owner.
Unknown dispatch/calls remain unknown, and inlined bodies retain the ordinary
executable dependency reads. A collection of up to eight scalar elements can
use locals when all its uses are finite traversal or intrinsic length reads;
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
builders. The packed scalar-row experiment is a separate fixture and does not
change the production collection ABI.

Executable fragment validity records each inlined source body and every static
value root. Exact source/catalog dependencies and complete
value/evidence/capture graph comparison authorize reuse; unsupported providers
and generative domains rebuild. Rebuilt dependency seeds may offer old pinned
fragments for admission. Candidate failure must preserve the last successful
revision and its owners. Within one compile, code and principal/query admission
share immutable semantic validation arrays through independently released leases.
Source owners, current Core, allocator and admission options must match; executable
body/value checks remain separate.

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
