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

Small aggregate scalar replacement requires full initialization before aliasing
and fixed field offsets. Every lexical version and loop carry owns separate
scalar locals. ABI values, captured/escaped values and GC roots remain boxed.
The pass transforms an assembly copy, preserving retained symbolic fragments.
Ordinary source inlining has a four-node budget, expanded to 64 for aggregate
results inside loops or known callback arguments. Nesting is limited to three
levels and expansion stops past 4,096 emitted instructions. These are structural
cost limits, independent of declaration names and source modules.

Executable fragment validity records each inlined source body and every static
value root. Exact source/catalog dependencies and complete
value/evidence/capture graph comparison authorize reuse; unsupported providers
and generative domains rebuild. Rebuilt dependency seeds may offer old pinned
fragments for admission. Candidate failure must preserve the last successful
revision and its owners. Within one compile, code and principal/query admission
can share an independently owned copy of the same semantic validation. Source
owners, current Core, allocator and admission options must match; executable
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
