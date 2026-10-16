# Editor completion contract

Completion, the client method and the LSP bridge implement this contract.
[Helix configuration](../editor/helix/languages.toml) supplies highlighting and
the completion server. Language meaning comes from the
[guide](../compiler/guide.md), ownership from [CONTRACT.md](CONTRACT.md), and
transport from [PROJECT_PROTOCOL.md](PROJECT_PROTOCOL.md).

## Native request

Extend protocol version 1 with optional capability `editor-completion-v1` and
request kind `complete` (numeric enum tag 4; existing tags do not change). A
host must see that capability before sending the request; existing servers
cannot parse it. Existing requests and replies keep their shapes. A completion
query never emits Wasm, runs const initializers, advances `revision`, replaces
the retained build, or saves a restart cache.

| Field      | Type                   | Rule                                                            |
| ---------- | ---------------------- | --------------------------------------------------------------- |
| `kind`     | `"complete"`           | required                                                        |
| `id`       | u32                    | required; ordinary strictly increasing request ID               |
| `epoch`    | string                 | required; current open epoch                                    |
| `revision` | integer                | required; current successful build revision, including 0        |
| `snapshot` | u32                    | required, nonzero host document-state token                     |
| `filename` | absolute path          | required; <=4,096 UTF-8 bytes; opened entry or reachable source |
| `position` | u32                    | required; UTF-8 byte boundary, inclusive range 0..source length |
| `sources`  | array of source ranges | optional, default `[]`; same fields and payload rules as build  |

Open-only fields must remain at their protocol defaults. `snapshot`, `filename`
and `position` must be absent or null on open/build/close/checkpoint; a non-null
value there is InvalidRequest. On complete, missing/null snapshot, filename or
position is terminal InvalidCompletionRequest. Canonical JSON types are required
of hosts; native parsing preserves version 1's documented integer and enum
coercions. Unknown/duplicate JSON fields and malformed frames remain terminal
protocol errors. The filename bound keeps required reply echoes inside the
metadata budget even with JSON escaping. An over-limit filename is terminal
InvalidCompletionRequest; the client rejects it before queueing or consuming an
ID.

For example, a complete request with no overlays and empty payload is:

```json
{
  "kind": "complete",
  "id": 3,
  "epoch": "1",
  "revision": 1,
  "snapshot": 10,
  "filename": "/p/main.blot",
  "position": 0,
  "sources": []
}
```

The payload is the full overlay set for this query, not an edit or a reference
to a previous request. Omitted paths read disk; null/deleted overlays hide
files. Capture all changed open buffers together, copy their bytes before
queueing, and never borrow mutable editor buffers. The queried source uses this
snapshot exactly. No earlier failed build's overlays are inherited.

The host allocates a new `snapshot` whenever any open buffer, watched source,
import resolution or project option changes. It may reuse the token for another
cursor in the same captured state; it must not attach different captured state
to that token. Tokens reset only with a new child process. The server echoes the
token but does not treat it as a cache certificate: reuse requires its own exact
captured bytes, canonical paths and import/settings validation. Disk inputs are
captured once per query through the same input provider the checker consumes.

## Reply and client

Both replies have empty payload and always contain `kind`, `id`, `epoch`,
`revision`, `snapshot`, `filename`, `position` and `success`. The first seven
fields echo the request, with revision unchanged. All fields below are present;
nullable fields use explicit `null`.

| Successful reply field | Type                        | Meaning                                                        |
| ---------------------- | --------------------------- | -------------------------------------------------------------- |
| `success`              | `true`                      | query completed, possibly with partial information             |
| `replace`              | `{start: u32, end: u32}`    | half-open edit range in the original source                    |
| `context`              | typed-hole snapshot or null | expected type, visible bindings and enclosing obligations      |
| `items`                | array of items              | deterministic best-first order                                 |
| `truncated`            | boolean                     | any candidate, semantic detail, diagnostic or work was omitted |
| `diagnostics`          | array of diagnostics        | at most 16 ordinary positioned diagnostics                     |

An item has exactly these fields:

```
{ label: string, insertText: string,
  kind: "value"|"function"|"type"|"constructor"|"field"|"member"|"module",
  detail: string|null, match: "exact"|"compatible"|"unknown"|"incompatible" }
```

`detail` is a display spelling of the type and residual generic requirements; it
is not a parseable type or reusable evidence. Items insert plain text only,
without snippets, imports, automatic calls, casts or other edits. Every item
uses `replace`; its UTF-8 byte boundaries refer to the original snapshot. A
constructor item includes `#` only when the original source does not already
supply it. Qualified constructors are eligible only after `#namespace.`; do not
insert a marker inside an existing receiver/module prefix.

`context` uses the [typed-hole graph](PROJECT_PROTOCOL.md#build), including its
bounds, explicit rows, local nominal identities, `enclosing` requirement span
and acyclic references. It describes a private probe at this cursor, not a
successful program or proof that every item compiles. Keep its nearest 32
visible bindings; mark omitted bindings/detail as truncated. Consumers must not
compare graph IDs across responses. The item list can include bindings omitted
from this display graph; their `detail` is independently owned text.

A failed reply has `success: false` and `diagnostics`, exactly one diagnostic,
with stage `complete`; it has no replace/context/items/truncated fields. Codes:

| Code                 | Trigger                                                     |
| -------------------- | ----------------------------------------------------------- |
| `invalid_completion` | zero snapshot token or filename outside the opened project  |
| `invalid_position`   | offset beyond source or inside a UTF-8 sequence             |
| `missing_source`     | target absent, hidden or unreadable                         |
| `source_limit`       | valid request exceeds source/module acquisition budgets     |
| `duplicate_source`   | overlays name the same canonical source twice               |
| `completion_failed`  | recoverable query operation failed; message names the cause |

Use the standard diagnostic shape, including offset_encoding, utf16 and details.
For a target that cannot be read, use start/end 0, utf16/details null. For an
invalid offset, use an empty span at the nearest preceding valid in-range byte
boundary. Messages are at most 1,024 UTF-8 bytes and end at a character
boundary. OOM or failure writing a reply remains terminal; do not disguise these
as syntax failures. Bad source range partition/UTF-8/count remains a terminal
protocol error as in version 1. Wrong epoch/revision and request ordering retain
the existing terminal errors. A well-formed failed query consumes its ID, leaves
the session open and permits another query/build/close.

Add proposed client method:

```ts
complete({ filename, position, snapshot, sources?, signal? })
  -> Promise<ZigProjectCompletionResult>
```

It joins the existing serial queue, supplies the current epoch/revision when
sending, and validates every echoed field, edit bound, item enum, graph and
empty payload. It returns owned buffers/strings/arrays that remain usable after
later requests and disposal. Invalid caller input is rejected before sending or
consuming an ID. A peer reply violating the schema disposes the child.

## Visibility and ranking

Completion follows current name resolution, not a separate export index:

- Unqualified expression names: live local/parameter/pattern bindings, current
  module declarations, explicitly named imports under their local aliases, and
  the configured prelude. Later top-level declarations follow ordinary forward
  lookup; later local bindings and sibling branch bindings are absent.
- Nearest binding hides earlier versions and outer bindings of the same name. In
  a `:=` RHS, the old name and `self` have their ordinary previous-value types;
  after it, only the new binding is offered. Earlier closures retain their own
  lexical version. Do not offer shadowed duplicates.
- Namespace imports offer the namespace itself, not all its names unqualified.
  `namespace.` offers only declarations that ordinary qualified lookup permits.
  All top-level declarations are importable today; do not invent private/export
  syntax. A named type import does not import differently named constructors.
- A lexical receiver takes precedence over a same-named namespace. Receiver
  members come from its actual type's defining module, never an argument type.
  Fields must be available on every nominal variant. A field/member collision
  remains ambiguous; list both kinds as incompatible with ambiguity in detail.
- Type positions offer visible types/contracts/type parameters; expression
  positions offer legal values/functions/modules/constructors; `#` positions
  offer constructors. Match qualified type/member context using ordinary lookup.
  Do not suggest unimported names, fabricate evidence or add imports.

Prefix filtering is case-sensitive `startsWith` on the identifier after the last
`.` or `#`; @hole uses an empty prefix, and an empty prefix includes all
eligible names. No fuzzy matching or keyword/path/snippet completion is
required. Remove duplicate items only when binding identity, kind and insertion
text are all equal.

Rank lexicographically by: match class (exact, compatible, unknown,
incompatible), then lexical distance (nearest locals/parameters first, current
module, named imports, prelude), then unsigned UTF-8 insertion text, then kind
in the item's enumeration order above. Qualified member lists have equal lexical
distance. Stable name ties use unsigned UTF-8 declaration filename then
declaration byte start; no table/solver allocation order affects results.

Expected types come from annotations, function argument positions, return sites,
patterns and enclosing expressions. There is no default U32/F32, associated
owner, effect row or conversion when context is unknown. Test each candidate in
fresh isolated inference/evidence state:

- `exact`: candidate requires no quantified instantiation and its known type
  equals the known expected type, including nominal identity/rows, and its
  obligations are discharged or entailed by the enclosing declared requirements.
- `compatible`: fresh instantiation fits by ordinary language rules and all
  obligations are discharged or entailed, without an implicit conversion.
- `unknown`: expected type, candidate type, dispatch/effects or necessary
  evidence remains unresolved, or checking exceeded the budget.
- `incompatible`: ordinary fitting/dispatch/effect/evidence checks establish a
  conflict. Keep these items last; do not present them as valid solutions.

Generic candidates keep quantified types and requirements in detail/context.
Unification alone is insufficient to rank a generic candidate compatible. A
pending `associated`/field/effect obligation remains unknown unless the private
query can discharge it or prove it follows from enclosing requirements. Matching
never writes into the live checker, publishes a principal receipt, instantiates
runtime values or specializes executable code.

## Incomplete syntax and limits

The edit span covers the whole identifier token at the caret, including any
suffix to its right, excluding an existing `.`/`#`/`@` prefix. An existing
`@hole` is replaced as a whole when the caret lies in it or immediately after
it. In an empty argument/member position the span is `{position,position}`.

In private scratch, recognize an identifier prefix, a missing call argument,
trailing `receiver.`, qualified `module.`, a standalone selector `.`, and
`@hole`. Insert one semantic probe and close at most eight unmatched EOF
parentheses/ brackets. A member probe retains the receiver; a selector obtains
its receiver from a known expected function parameter. Do not guess its owner
when unknown. Do not insert declarations, alter indentation or repair unrelated
syntax. Map all diagnostic/edit offsets back to the original bytes, and suppress
the probe's own typed_hole diagnostic. Other real holes may remain in
diagnostics.

If recovery cannot identify a valid enclosing expression, return successful
lexical completion from well-formed visible binders, context null and unknown
matches, with the real syntax diagnostics. Syntax after an earlier error must
not manufacture bindings or expected types. Inside comments, strings and import
path strings, return success with empty items, context null, empty diagnostics
and an empty edit span. No query requires an entry export or guest-ABI-valid
result. No source repair or synthetic declaration reaches a build/checkpoint.

Limits are fixed for completion v1:

| Work/result                  | Bound                                                                                 |
| ---------------------------- | ------------------------------------------------------------------------------------- |
| Source acquisition           | existing 4,096 modules, 16 MiB/file, 64 MiB total limits                              |
| Query inference              | 1,000,000 transitions total across loaded modules and candidate fits                  |
| Candidate visits             | 4,096, after shadowing/prefix filtering; nearest scope then UTF-8 insertion text/kind |
| Returned items               | 128                                                                                   |
| Semantic display graph       | existing hole graph limits; 1,024 visits and 32 levels                                |
| Diagnostics                  | 16; each message at most 1,024 UTF-8 bytes                                            |
| Item label/insertText/detail | respectively 256/256/1,024 UTF-8 bytes                                                |
| Entire reply metadata        | 256 KiB, including context and diagnostics                                            |

Never truncate an identifier or insertion into another identifier. Omit an item
whose actual label/insertText cannot fit and set truncated. Display text may be
cut at UTF-8 boundaries. Budget exhaustion returns the known partial list,
unknown matches for unproved fits, truncated true, and one `completion_limit`
diagnostic within the diagnostic budget. Keep the best item prefix and
diagnostics that fit the metadata limit; drop trailing diagnostics first, then
trailing items, setting truncated. If the context graph itself cannot fit
alongside the required fields, publish context null and truncated true; already
proved item matches remain valid. An empty bounded result is preferable to a
process-ending oversized reply. Reuse immutable project inputs under the
ownership contract; completion scratch and query graphs have independent owners
and are freed on every exit.

## Cancellation and stale results

There is no new wire cancel message. Queued cancellation drops the unsent query
and consumes no request ID. Active cancellation follows
`abort-disposes-process`: kill and reap the child, reject active/queued work
with AbortError, and reopen before further requests. Previously returned Wasm
and completion snapshots remain owned and unchanged. A canceled query never
publishes a new build revision.

A UI applies a reply only if child generation, epoch, successful build revision,
snapshot token, filename and requested cursor still match its current request. A
new document version, watched-file event, root/options change or cursor query
makes older replies stale. Discard stale results without editing the buffer or
caching their context. Do not rely on the epoch string alone: it is currently
`"1"` in every process. A finite UI deadline is host policy; the bridge below
uses 250 ms from receipt of the LSP completion request and disposes the active
completion child on timeout. Unsent timed-out requests are dropped without
consuming a native ID.

## Helix LSP bridge

Task 050 adds `compiler/lsp.ts`, a small Deno stdio adapter. Helix speaks
standard LSP JSON-RPC with Content-Length framing to it; it speaks the separate
eight-byte native protocol to blotc. Keep logs on stderr. Bound LSP headers to 8
KiB and Content-Length bodies to 64 MiB before allocation. Malformed/truncated
framing closes the bridge and reaps its child; valid framing with invalid JSON
returns ParseError (-32700), and an invalid JSON-RPC request object returns
InvalidRequest (-32600). The proposed launch is:

```sh
deno run --allow-read --allow-run compiler/lsp.ts \
  --compiler /absolute/path/to/blotc \
  --prelude /absolute/path/to/std/prelude.blot \
  --std-root /absolute/path/to/std
```

Use absolute paths in the installed configuration. Repeated optional
`--import prefix=/absolute/root` arguments map directly to native import
aliases; otherwise only std/ is configured. No source-file writes or parser
functions are involved. Cache persistence is disabled for the editor child. One
child serves the active document as its opened entry; switching completion to
another document closes/reaps it and opens that document. Maintain all open Blot
buffers as complete overlays, so imports observe unsaved buffers. These children
are separate from any build client; cancellation never kills a running
application/build session.

Implement initialize/initialized, shutdown/exit, didOpen/didChange/didClose,
textDocument/completion and `$/cancelRequest`. Advertise full text
synchronization (`openClose: true`, `change: 1`), `positionEncoding: "utf-16"`,
and `completionProvider: {resolveProvider:false, triggerCharacters:[".","#"]}`.
Return a CompletionList, with isIncomplete equal to native truncated. Each item
has label, plain-text textEdit, detail, filterText excluding a constructor's
`#`, sortText as the three-digit zero-padded response index, and LSP kind mapped
as value=6, function=3, type=7, constructor=4, field=5, member=2, module=9. Do
not advertise hover, formatting, signature help, import edits or resolve. For a
whole `@hole` replacement, filterText starts with the typed hole name without
`@`, followed by the insertion spelling. This keeps Helix's local filter from
hiding valid suggestions; textEdit still replaces only the hole.

The bridge translates UTF-16 line/character positions to UTF-8 offsets against
the captured document and converts native edits back against that same copy;
handle CRLF and supplementary code points without splitting them. It accepts
file URIs only. Apply each full-text didChange only when its document version is
newer; ignore/log an out-of-order notification without regressing the buffer.
didClose removes the buffer override; didChange increments the workspace
snapshot token and invalidates older pending replies. Watch `.blot` changes
recursively under workspace/std/import roots, and root-parent events for symlink
replacement; changes also invalidate the token. An imported path outside these
watched roots is reacquired at the next query, but unsolicited stale
invalidation for its disk edits is outside this initial bridge contract. Stale
replies produce ContentModified (-32801), explicit cancellation/deadline
RequestCancelled (-32800), invalid parameters -32602, unknown methods -32601,
and child startup/protocol failures -32603. Ignore unknown notifications. Use
the
[LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
for JSON-RPC lifecycle, completion items and cancellation semantics.

Task 050 updates the existing managed block through
[helix_languages.ts](../scripts/helix_languages.ts), preserving unrelated user
configuration and the current Tree-sitter grammar/highlights/rainbows:

```toml
[language-server.blot]
command = "deno"
args = ["run", "--allow-read", "--allow-run",
        "/projects/blot2/compiler/lsp.ts", "--compiler",
        "/projects/blot2/zig-native/zig-out/bin/blotc", "--prelude",
        "/projects/blot2/std/prelude.blot", "--std-root", "/projects/blot2/std"]

[[language]]
name = "blot"
language-servers = ["blot"]
# Retain the existing language block's other fields.
```

Update the existing Blot language block rather than adding a duplicate. Update
installer health assertions and registration tests from “no language server” to
configured blot. Helix supports this server table and language assignment in
[languages.toml](https://docs.helix-editor.com/languages.html). In insert mode,
manual completion is Ctrl-x in the
[default keymap](https://docs.helix-editor.com/keymap.html#insert-mode).
Qualification must use `hx --health blot` and a real unsaved-buffer completion
session; syntax highlighting alone is insufficient.

## Acceptance transcripts for task 050

These are executable acceptance requirements, not observations. `C(text)`
removes the sole `<cursor>` marker and computes position as the UTF-8 byte
length of the preceding text. `Q(id,snapshot,text)` sends a complete request
using filename `/p/main.blot`, the current epoch/revision and a single source
range covering C(text)'s bytes. `context.expected` assertions below refer to its
indexed node, not a textual parser. Unless stated otherwise, use no prelude and
expect no real diagnostic besides errors explicitly shown.

Start: hello contains editor-completion-v1; send
`{"kind":"open","id":1,"version":1,"entry":"/p/main.blot"}`. Build disk source
`entry const answer = 42` with id 2, obtaining revision 1. All following
complete replies keep revision 1. Each scenario uses fresh increasing IDs and
tokens.

| Query source / action                                                                                              | Required reply/assertion                                                                                              |
| ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| `const work = fn (value: U32) -> U32 => va<cursor>` followed by `entry const answer = 42`                          | replace covers `va`; sole prefix match value, kind value, insertText value, match exact; expected u32                 |
| `const take = fn (value: U32) => value` then `const work = fn (value: U32) => take (<cursor>` at EOF               | close one scratch parenthesis; expected u32; value precedes take as a candidate; no scratch edit persists             |
| `type Point = { x: U32, y: F32 }` then `const work = fn (point: Point) -> F32 => point.<cursor>`                   | items y exact then x incompatible; both kind field; insertText has no dot                                             |
| `const work = fn (value: U32) -> U32 => do:` then `let original = value`, `value := #True`, `return @ho<cursor>le` | replace entire @hole; original exact precedes value incompatible; graph scope has value Bool, never earlier value U32 |
| `const work = fn (value: U32) => do:` then `value := @hole<cursor>`                                                | old value and self are U32 in RHS; no successor binding yet                                                           |
| `const work = fn (value: U32) -> U32 => @hole<cursor>`                                                             | whole-hole edit; expected u32; owned graph remains readable after another query and disposal                          |

Selector fixture, with no prelude:

```blot
type Point = { x: U32, y: F32 }
const select = fn (get: Point -> F32) => fn (point: Point) => get point
const work = fn (point: Point) -> F32 => select .<cursor> point
entry const answer = 42
```

Expected callback is Point -> F32: y inserts `y` after the existing dot and is
exact, x is incompatible. Without a known callback receiver, the query returns
no invented receiver members and context/matches stay unknown.

Import fixture `/p/library.blot` contains `const visible = 7`,
`type Choice is data = #Picked U32 | #Empty`, and
`const helper = fn value => value`. All are public under current language rules:

| Query                                                                                    | Required visibility                                                                    |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `import { visible as renamed, Choice } from "./library"`, expression prefix `re<cursor>` | renamed appears; visible does not                                                      |
| Same imports, constructor prefix `#Pi<cursor>`                                           | Picked is absent: differently named constructor was not imported                       |
| `import * as lib from "./library"`, `lib.<cursor>`                                       | visible and helper offered, preserving qualified lookup; no unqualified visible/helper |
| Same namespace import, local `let lib = { local: 1 }`, then `lib.<cursor>`               | only receiver field local; namespace does not win                                      |
| Namespace import plus type-position `const work: lib.Ch<cursor> = @hole`                 | Choice offered as type; insertion excludes lib.                                        |

Generic fixture:

```blot
type Add a is contract = { associated "add" a a a }
const twice: a -> a where { Add a } = fn value => value
const work: a -> a where { Add a } = fn value => tw<cursor>
entry const answer = 42
```

At the final function's result position, twice itself is a function and must not
be marked compatible with expected a. With the cursor instead in
`const work: a -> a where { Add a } = tw<cursor>`, twice is compatible: its
fresh requirement follows from enclosing Add a. Context and detail retain that
requirement; no inference ID or dispatch certificate escapes. Replacing Add a
with an unrelated field requirement must not yield compatible. An unannotated
missing member owner yields unknown, not a guessed scalar/member family.

Byte/limit/error transcript:

1. Prefix the first fixture with `// 雪\n`. Native byte position exceeds its
   UTF-16 absolute offset by two; bridge's UTF-16 edit still replaces only va. A
   position inside 雪 gives failed invalid_position and permits a later query.
2. A syntactically broken unrelated binding gives successful lexical fallback,
   context null and positioned syntax diagnostics; no invented expected type.
   Completion inside its comment/string has empty items.
3. A scope of 1,000 matching names yields <=128 items and truncated true;
   repeated query has identical order. Force inference/graph/metadata budgets
   separately and assert bounded partial results, not fabricated compatibility.
4. Wrong revision terminates with RevisionMismatch; repeated ID with
   RequestOrder; malformed/oversized/truncated frame and unknown JSON field keep
   protocol-v1 behavior. A missing target returns failed missing_source, without
   termination.
5. Following every incomplete/failed query, build original disk source with
   correct revision; it succeeds as revision 2 and produces the same Wasm as the
   initial build. No synthetic completion source reached its retained inputs.

Race/client/editor transcript:

```
didOpen version 10 -> snapshot 10 -> complete native id 3
hold its reply; didChange version 11 -> snapshot 11
reply id 3/snapshot 10 -> ContentModified; no old edit applied
complete native id 4/snapshot 11 -> matching edit offered
queue id-to-be-5; cancel before send -> no native frame or ID consumed
send native id 5; cancel active -> child reaped, AbortError/RequestCancelled
reopen child generation 2 (epoch may again be "1"); old replies remain stale
close document/shutdown -> overrides removed and child reaped exactly once
```

In a real Helix session: configure the new managed block, run health, open the
first fixture, leave the final va unsaved and use insert-mode Ctrl-x. Choose
value and confirm only va changes. Repeat member/import/shadow and Unicode
examples; edit rapidly while a reply is held and confirm no stale insertion.
Record the Helix version, health output, request/response trace and resulting
buffer text. Compiler/client tests additionally check owned results after
teardown, allocation failure cleanup, malformed peer disposal and last-good
output preservation.

## Scope

The implementation supplies the native query/recovery path, conservative
evidence fitting, client validation/cancellation, LSP bridge, installer changes
and actual Helix acceptance trace. Initial scope excludes path/keyword/snippet
completion, auto-imports, workspace symbol search, arbitrary syntax repair and
new language visibility rules. The 250 ms editor deadline is policy. The
measured workloads below fit within it; this is not a latency guarantee for
arbitrary projects. Completion must work without a successful build, even for a
module with no entry declaration; revision 0 is a required acceptance case.

## Original specification qualification

Implementation: `d7e2b89`. Deno formatting, seven local links/anchors and the
JSON/TOML examples pass review. Incomplete call/member/hole, imported/shadowed
names, generic evidence, Unicode edits, revisions, cancellation and rapid
overlay changes have explicit acceptance transcripts. At that milestone the
documentation supplied no executable feature or demonstrated latency; the
implementation evidence follows below.

## Implemented ownership and limits

[editor_completion.zig](src/reuse/editor_completion.zig) acquires a private
input snapshot, canonicalizes and captures each disk input once, then
substitutes one exact-span marker. It verifies project membership even inside
comments/strings. At most eight missing EOF closing delimiters are repaired;
diagnostics map back to the original bytes. Ordinary checking has no marker.
Queries publish no build, evaluator values, previous-revision owner or restart
cache.

The checker captures actual lexical/import/member names and the expected type at
that marker. RHS rebinding exposes the previous binding through both its
original name and self. The query owns its symbol pool and seeds legal implicit
names before checking; borrowed checker pools never grow. Candidate collection
keeps the nearest deterministic 4,096 names, then fits/ranks before retaining
128. The context owns at most 32 visible bindings. Syntax fallback uses the
actual enclosing lexical path and supplies unknown matches without fabricated
expected/member types.

Checking and candidate fitting share one million work units. Each normalized
copy has at most 1,024 visits and depth 32. Expected generic variables stay
rigid; candidate parameters are fresh. Compatible requires entailed enclosing
requirements; unresolved associated dispatch/effect evidence stays unknown.
Names, details, graphs and diagnostics own their bytes after teardown. Replies
have at most 16 diagnostics and 256 KiB metadata. Limit exhaustion preserves a
completion_limit diagnostic and marks truncated; an oversized context is removed
before proved items. Filename admission is bounded at 4,096 UTF-8 bytes so
required echoes fit too.

[The client](../compiler/editor_completion.ts) validates complete DTOs, echoes,
UTF-8 edits and owned diagnostic graphs. It captures overlays/options before
queueing on the existing serial transport. Queued cancellation consumes no ID;
active cancellation reaps the child and rejects pending work. Native assets and
host asset-parser sources are available privately without publishing resource
handles or build caches. Failed/incomplete queries leave successful compilation
and its Wasm unchanged.

[The bridge](../compiler/lsp.ts) owns full document snapshots and process
generations, converts UTF-16/UTF-8 including CRLF/supplementary code points, and
rejects stale versions/snapshots/cursors. It watches source/import roots and
parent replacements, aborts at 250 ms from request receipt and reaps on
teardown. Framing is independent of the native transport, bounded before
allocation. Installer updates preserve adjacent unmanaged language configuration
and the existing grammar/highlight/rainbow assets; they add no formatter.

## Implementation measurements, 11 October 2026

The measured release compiler is SHA-256
`f3d02fee0e8886881e0dffaaebb23fa3c93b77847e68708a1d9b155b478e6c15`; Zig 0.17.0,
Deno 2.9.7, restart caches disabled. Both ordinary comparisons and query
measurements are pinned to CPU 6. Load averages were approximately 3.8; other
compiler jobs remained active on other CPUs. Raw samples, source/compiler pins
and measurement harnesses are ignored under
`build/bench/editor-completion/measurement`.

For each public query, 13 fresh native processes, 31 repeated queries and seven
queries following a successful build use the standard prelude. The first-query
measurement covers the request/reply, excluding spawn/open; repeated queries do
not imply semantic cache reuse. After every sequence, rebuilding the original
valid overlay preserves its exact Wasm.

| Query            | First median / p95 ms | Repeated median / p95 ms |
| ---------------- | --------------------- | ------------------------ |
| Value prefix     | 3.411 / 3.637         | 2.977 / 3.289            |
| Member           | 3.365 / 3.476         | 2.977 / 3.169            |
| Imported alias   | 3.847 / 4.278         | 3.352 / 3.555            |
| Generic evidence | 3.504 / 3.939         | 3.055 / 3.401            |
| Shadowed hole    | 3.894 / 3.964         | 3.411 / 3.846            |
| 4,200 names      | 33.682 / 50.725       | 32.819 / 36.536          |

A separate ReleaseFast probe copies the frozen compiler inputs and adds only two
counter reads, retaining query behavior and budgets. Twenty samples after one
warmup measure 2.879–3.228 ms process CPU for value/member/import/generic
queries, 3.109 ms for the hole and 31.666 ms for the large scope. Small queries
consume 2,880–2,892 inference transitions; the large scope consumes 19,679 and
exhausts the shared one-million-unit fitting budget. It returns 128
deterministic items, unknown for unproved fits, and truncated=true. Requested
allocation is 2.47–2.75 MB for small queries and 16.82 MB for the large scope;
peaks are 0.83–0.90 MB and 6.23 MB. Every sample tears down to zero live
requested bytes. Query cost is extra work; there is no retained semantic-query
cache.

Seven alternating release pairs against the qualified 028/036 compiler
`8a7dd393ab4768eebcdf8859135345fd44700dae5c2ebb4391577d75006aa8bc` preserve
Wasm, diagnostics and old work counters on all 13 public examples. Requested
allocation increases 352 bytes per two-module project and 528 per three-module
project from optional editor capture fields; all teardown counts are zero. CPU
ratios range 0.924–0.985 on this host; no general speedup is claimed. Four
synthetic workloads preserve exact fresh/retained Wasm through population, edit,
revert, rejection and no-op phases. Retained CPU is mostly below the 10 ms
process-accounting resolution. Earlier comparisons using a pre-compaction
baseline or enabled restart caches are retained as exploratory runs and excluded
from these conclusions.

## Actual editor and gate evidence

Helix 25.07.1 (3dae6a17), Deno 2.9.7 and Tree-sitter 0.27.1 were exercised with
an isolated XDG configuration. Grammar generation/corpus/example parsing,
installer idempotence/neighbor preservation and hx --health blot pass. The real
PTY session left text unsaved, requested Ctrl-x, accepted an item and saved each
public fixture. Value, member, imported alias, shadowed hole and Unicode/CRLF
edits affect only the reported token. The held-peer race ends as valzz; the old
reply is canceled and never inserts text. Logs and owned traces are retained in
`build/bench/editor-completion/helix/acceptance.json`; the five ordinary
sessions use the measured release pin, while the race deliberately uses a held
test peer.

The frozen full gate passes native laws and 788 guest/client laws, including all
eight unchanged allocation budgets; analyzer findings are zero across 328 Zig
files. Focused native/OOM, generic fitting, protocol echo/defaults,
queue/disposal, active/queued cancellation, deadline, disk-watch invalidation
and actual stdio malformed/oversized-frame recovery laws pass. The later
filename admission bound passes focused client/raw-wire validation and the joint
compiler gate below.

## Main integration qualification (11 October 2026)

Implementation `2226d50` jointly includes tasks 043 and 050 over qualified 031.
Zig 0.17.0, Deno 2.9.7: `deno task test:compiler` passes the full native suite
and 807 guest/client laws (6m21s guest phase), with all eight allocation budgets
unchanged. `deno task lint:zig` with the pinned local analyzer checks 336 Zig
files with zero findings. The staged tree remained
`fccba545f83a668fc3c75bcfbd916c3fbebe20fe` through this gate. Release SHA-256:
`272f028932b0cc563049fe7e5f6f51139304f0ae4cf7213351fd55f5f5f7a127`;
compiler-identity file SHA-256:
`15cc1fda4ca4969090b5876a2f181813e4b9ff889bc288851984d6bfe3371a96`. Ignored gate
logs and input patches are retained in `build/bench/joint-043-050/`.

The final main release repeats the six-fixture raw-wire run on CPU 6 with cache
loading disabled: 13 first, 31 repeated and seven post-build queries per
fixture, plus warmups. Ordinary repeated medians are 2.967–3.445 ms. The
4,200-name fixture is 33.672 ms repeated median, 33.922 ms p95; first-query p95
is 51.078 ms. Every query preserves the successful revision and following Wasm.
This rerun includes the filename bound and integrated 031/043 source; the
detailed allocation/CPU probe and actual Helix traces above retain their
explicitly recorded earlier pin.
