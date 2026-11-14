# The `serve-project` protocol

`blotc serve-project` keeps one Blot project open in a child process and builds
it on request. Each build loads, checks, lowers and compiles its revision from
the sources it names with the direct backend; no checked or compiled module is
carried from one build to the next. A host talks to it over the child's stdin
and stdout in length-prefixed frames. This document is enough to write a host
without `@mewhhaha/blot`. It describes protocol version 1 as implemented by this
repository:

- the server:
  [zig_project_server.zig](../../compiler/src/reuse/zig_project_server.zig) and
  [zig_project_frames.zig](../../compiler/src/reuse/zig_project_frames.zig);
- the reference client:
  [host/zig_project_client.ts](../../host/zig_project_client.ts), behind
  `createCompiler` and `createZigProjectCompiler`
  ([PROJECT_CLIENT.md](PROJECT_CLIENT.md));
- protocol conformance laws:
  [protocol conformance laws](../../tests/guest/zig_project_protocol.test.ts);
- native typed imports and resource snapshots:
  [NATIVE_ASSETS.md](NATIVE_ASSETS.md);
- editor completion: [EDITOR_COMPLETION.md](EDITOR_COMPLETION.md).

Where the server and the reference client differ, both are stated. Example IDs
and revisions are illustrative; replies always echo the request ID and use the
session revision rules below.

## Starting the compiler

```
blotc serve-project
blotc serve-project --frontend-workers N    (N in 1..16, default 4)
blotc serve-project --semantic-workers N    (N in 1..16, default serial)
blotc serve-project --inference-budget STEPS
```

The options may be combined, and each takes exactly one value.
`--frontend-workers` checks independent modules on N workers.
`--semantic-workers` lowers the modules a build checked to Core on N workers.
`--inference-budget` sets the process-local inference limit (default 1,000,000);
a value other than the default changes `compilerIdentity`. Worker counts never
change the emitted bytes. Any other argument, a missing value or a worker count
outside 1..16 makes the process print `blotc: InvalidServeArguments` to stderr
and exit 1; an inference budget that is not a positive integer prints its own
error name.

- **stdin** carries request frames and **stdout** reply frames, nothing else.
- **stderr** is free text for people. With `profileTrace` (open) it also carries
  progress records. When the process stops on an error, its last line is
  `blotc: <ErrorName>`. The reference client keeps the last 64 KiB of it to put
  in its error messages.
- **Environment.** The server reads no environment variables. The reference
  client starts the child with a cleared environment.
- **Where blotc comes from.** `@mewhhaha/blot` bundles a gzipped Linux x86-64
  `blotc` (`generated/compiler/blotc.gz`). The reference client unpacks it to a
  temporary `blotc-*` file before spawning it. A host can run any `blotc`
  instead; the hello's `compilerIdentity` says which one it got.

## Frames

Every message, in either direction, is one frame:

| Bytes      | Contents                                              |
| ---------- | ----------------------------------------------------- |
| 0..4       | metadata length `M`, unsigned 32-bit little-endian    |
| 4..8       | payload length `P`, unsigned 32-bit little-endian     |
| 8..8+M     | metadata: one JSON object, UTF-8                      |
| 8+M..8+M+P | payload: raw bytes (sources/assets or Wasm/resources) |

- `M` is from 1 to 16,777,216, and `8 + M + P` is at most 67,108,864
  (`maxFrameBytes`).
- Lengths are checked before anything is allocated.
- End of input is allowed only between frames; a partial header or body is an
  error.
- The server writes each reply whole and flushes it.

## Session

```
server: hello
client: open      server: open
client: build     server: build       (repeat)
client: complete  server: complete    (any time after open)
client: close     server: close, then exits 0
```

- **Strictly one at a time.** The host sends a request, then waits for its reply
  before sending the next. The server reads the next frame only after replying.
- **`kind` and `id`.** Every request has a `kind` and an `id`. The reply has the
  same `kind` and `id`. `id` is an unsigned 32-bit integer, at least 1 and
  larger than every earlier request's.
- **`epoch`.** The open reply names it (`"1"` today). Every later request
  carries it unchanged. A process accepts one open and never reopens.
- **`revision`.** The number of successful builds so far, starting at 0. Every
  request after open carries the revision the host last saw, and it must equal
  the server's.
  - A successful build commits revision `n + 1`.
  - A rejected build leaves `n`.
  - The largest revision is 2^53 − 1.
- **JSON.** Requests explicitly reject unknown and duplicate fields (including
  nested objects) with `UnknownField` and `DuplicateField`. A value of the wrong
  type that the parser cannot coerce stops the process with its error.
  Conforming hosts must send the JSON types in the tables. Zig 0.17 also accepts
  integral numeric forms such as `1.0` and numeric strings such as `"1"` or
  `"1e0"` for integer fields, subject to the same range checks. This includes
  `version`: `"1"` is accepted as value 1. Enum fields also accept numeric tags
  or their decimal strings: `kind` tags are open 0, build 1, close 2, complete
  3. Booleans, arrays and objects are not coerced to integers. Optional fields
  may be left out. Replies normally write an optional field with no value as
  `null`. The reference client ignores reply fields it does not read. Hosts
  should ignore unknown reply fields; incompatible request or reply changes
  require a new version.

## hello

The server sends it unprompted, before reading anything. It has no payload.

| Field              | Value                       |
| ------------------ | --------------------------- |
| `kind`             | `"hello"`                   |
| `protocol`         | `"blot-zig-project"`        |
| `version`          | `1`                         |
| `compilerIdentity` | 64 lowercase hex characters |
| `capabilities`     | array of strings (below)    |
| `maxFrameBytes`    | `67108864`                  |

`compilerIdentity` is a build-time fingerprint of the compiler: its sources,
target, optimization mode and whether LLVM built it (`build.zig`,
`compiler_fingerprint.zig`), combined with a non-default `--inference-budget`.
Two processes with the same identity are the same compiler. A dependency bundle
is only accepted under the identity that made it.

| Capability               | Meaning                                                           |
| ------------------------ | ----------------------------------------------------------------- |
| `project-build`          | builds a project from an entry file                               |
| `utf8_bytes`             | diagnostic offsets are UTF-8 byte offsets                         |
| `abort-disposes-process` | there is no cancel request: a host cancels by killing the process |
| `source-overlays`        | a build may carry `sources`                                       |
| `native-assets-v1`       | native readers, asset overlays and owned content snapshots        |
| `editor-completion-v1`   | `complete` requests work                                          |

The reference client checks the hello:

- `protocol`, `version` and `maxFrameBytes` match exactly;
- the identity has the right form;
- the first three capabilities are present;
- the identity is the one the caller asked for, if it asked
  (`expectedCompilerIdentity`);
- with no `source-overlays`, it refuses builds that carry `sources`;
- with no `native-assets-v1`, it refuses an open configured with `nativeAssets`;
- with no `editor-completion-v1`, it refuses completion queries.

It allows 30 s by default (1 to 300 s) for the hello and the open together.

## open

| Field            | Type                      | Rule                                                         |
| ---------------- | ------------------------- | ------------------------------------------------------------ |
| `kind`           | `"open"`                  |                                                              |
| `id`             | integer                   | see Session                                                  |
| `version`        | unsigned 32-bit integer   | required, exactly `1`                                        |
| `entry`          | path                      | required: the program's entry file                           |
| `prelude`        | path or null              | the prelude module; absent or null: none                     |
| `stdRoot`        | path or null              | the root of the `std/` alias                                 |
| `imports`        | array of `{prefix, root}` | more directory aliases                                       |
| `dependencies`   | path or null              | a `.blotdep` bundle from `blot dependencies`                 |
| `profileBackend` | boolean                   | phase clocks and allocation counts per build (default false) |
| `profileTrace`   | boolean                   | progress records on stderr (default false)                   |
| `storage`        | object or null            | data-stack budgets; validated, then ignored (below)          |
| `nativeAssets`   | object or null            | optional native input configuration; absent/null disables it |

- **Paths.** Every path is absolute, non-empty and free of NUL bytes.
- **`imports`.** Each `prefix` is non-empty, ends in `/`, has no NUL and is
  unique; each `root` is a path.
- **`storage`.** Any of `temporaryBytes`, `growerBytes`, `persistentBytes`,
  `transportBytes` and `ownerCapacity`, each an unsigned 32-bit integer. The
  byte budgets must be positive multiples of 16 and `ownerCapacity` positive;
  otherwise the open is invalid. The direct backend lays out its own fixed
  regions and ignores these values. The field is accepted because Pen forwards
  it from a program's settings.
- **`profileTrace`.** While each build runs, the server writes stderr lines that
  start with `BLOT_PROFILE`, a space and one JSON record. The reference client
  parses them into `profileProgress`.
- **`nativeAssets`.** Requires `native-assets-v1`; `{}` enables an empty native
  session. `imports` and `roots` default to `[]`. Import definitions, discovery,
  paths and reader-specific fields are specified in
  [NATIVE_ASSETS.md](NATIVE_ASSETS.md#open-and-acquire-inputs).
- **Other fields:** `epoch` and `revision` must be absent or `null`; `sources`
  and `assetSources` must be absent or `[]`; `snapshot`, `filename` and
  `position` must be absent or `null`. Arrays and booleans do not accept `null`.
- **Defaults:** `imports` defaults to `[]`, the booleans to `false`; optional
  paths, `storage` and `nativeAssets` default to `null`. All optional
  configuration fields may be omitted.
- **Payload.** Empty.
- **Reply:** `{"kind": "open", "id": 1, "epoch": "1", "revision": 0}`, with no
  payload.

`dependencies` is read once at open, with its canonical settings; a bundle that
cannot be read, decoded for this compiler and these settings, or validated stops
the process. Every build resolves paths again. A build whose canonical settings
still match takes as checked every bundle module whose source and imports are
unchanged, and checks the rest (`cachedModules` and `freshModules`). If the
bundle cannot be used for a build, or loading, checking or lowering with it
rejects, the build loads and checks every module from source, and that result is
the reply.

`@mewhhaha/blot`'s `createCompiler` passes its own `std/` as `stdRoot` and
`std/prelude.blot` as `prelude`, unless the caller passes `null`.

## build

| Field          | Type                                       | Rule                                                   |
| -------------- | ------------------------------------------ | ------------------------------------------------------ |
| `kind`         | `"build"`                                  |                                                        |
| `id`           | integer                                    | see Session                                            |
| `epoch`        | string                                     | from the open reply                                    |
| `revision`     | integer                                    | the current revision                                   |
| `sources`      | array of `{path, start, length, deleted?}` | optional overlays                                      |
| `assetSources` | array of `{path, start, length, deleted?}` | optional raw asset overlays; requires a native session |

The payload contains source ranges followed by `assetSources` ranges. Each array
retains its own order; together they partition the whole payload. `assetSources`
defaults to `[]`, rejects null, and carries raw bytes rather than requiring
UTF-8. These overrides use the same per-build disk/deletion rules as sources.
Their full schema is in [NATIVE_ASSETS.md](NATIVE_ASSETS.md#build-payload).

A build, complete or close may carry the open's fields only at their defaults
(absent, `null`, `false`, `[]`); any other value stops the process with
`InvalidRequest`. `version` must be absent or `null` after open. `storage` and
`nativeAssets` must also be absent or `null`; an empty object is still an
open-only configuration. `snapshot`, `filename` and `position` must be absent or
`null` on a build or close.

**Source overlays.** `sources` is a complete override for this build only; the
next build does not inherit it.

- **Omitted files** are read from disk as they are at this build.
- **Present entries** replace a file's contents, or create a new virtual file.
- **Deleted entries** (`deleted: true`) hide a file for this build.

The rules (any break stops the process):

- At most 4,096 entries.
- Each `path` is absolute, non-empty and NUL-free. `start` and `length` are
  unsigned 32-bit integers; `deleted` is a boolean, default `false`. `sources`
  defaults to `[]` and does not accept `null`.
- Source ranges cover the payload prefix exactly, in order. The first `start` is
  0; each next is the previous `start + length`. With no asset ranges, this
  prefix is the whole payload. Otherwise the first asset range starts exactly at
  its end, and asset ranges cover all remaining bytes.
- A deleted entry has `length` 0.
- Every range is valid UTF-8.

Limits checked during the build reject it rather than stopping the process:

- **Duplicate paths.** Two overlays for the same canonical path reject the build
  with `stage: "build-project"` and `code: "DuplicateSourcePath"`; the revision
  is unchanged.
- **Overlay bytes.** An overlay over 16 MiB, or overlays totalling over 64 MiB,
  rejects the build as a failed operation with `code` `"SourceLimit"` (below).
- **Files read from disk.** A project of more than 4,096 files, a file over 16
  MiB or over what is left of the 64 MiB total, a missing file and a read error
  are ordinary diagnostics. Their `code` names the problem (`file_limit`,
  `source_limit`, `missing_file`, `io_error`).

Paths are made canonical, symbolic links included, so one module has one
identity whether it comes from disk or an overlay. The compiler never writes
source files.

**Success.** In a source-only session, the payload is the compiled Wasm module
and the metadata shape below is unchanged. The server does not validate Wasm;
the reference client rejects an empty or invalid module.

```json
{
  "kind": "build",
  "id": 7,
  "epoch": "1",
  "revision": 3,
  "success": true,
  "stats": {
    "frontend": {},
    "sourceBytes": 0,
    "freshModules": 0,
    "cachedModules": 0,
    "emittedFunctions": 0,
    "phaseProfile": {}
  }
}
```

`revision` is the previous revision plus one.

A native session (including an empty `nativeAssets` object) adds four required
fields: `wasmBytes`, `assets`, `assetDependencies`, and `assetStats`. The
payload is a Wasm prefix of `wasmBytes` bytes followed by contiguous resource
ranges. `assets` entries are `{id,path,mediaType,sha256,start,length}` with IDs
`1..N`; `assetDependencies` entries are `{path,sha256}`; `assetStats` is
`{parsed,reused,inputBytes,generatedBytes}`. Exact ordering, digest and snapshot
ownership rules are in [NATIVE_ASSETS.md](NATIVE_ASSETS.md#successful-snapshot).
The revision and the native asset snapshot commit only after the whole reply has
been encoded and bounded; a rejection leaves both as they were.

`stats` holds exactly these fields:

- `frontend`: an object of `syntax_nodes`, `body_elaborations`, `body_lowerings`
  and `imported_schemes` for the modules this build checked and lowered, and
  `normalization`, an object of checker normalization counters;
- integers: `sourceBytes`, `freshModules` (modules this build checked),
  `cachedModules` (modules taken from `dependencies`) and `emittedFunctions`;
- `phaseProfile`: an object, empty unless the session opened with
  `profileBackend`.

A profiled build's `phaseProfile` reports `total_us`, the process's
`peak_rss_kib`, exclusive `phases` (`other`, `assets`, `inputs`, `load`, `lex`,
`parse`, `check`, `lower`, `freeze`, `validation`, `backend`), which partition
the build up to its stats, and `checking`, frontend work counters aggregated
over the build's project checks. Each phase is
`{us, requested_bytes, allocations, rss_growth_kib}`: session allocator requests
charged while it was active, and how far it raised peak RSS.

The objects are measurements for people, and their insides are not part of the
contract. The reference client validates the four integers as nonnegative safe
integers and `frontend` and `phaseProfile` as objects. It refuses `const_steps`
and `remaining_steps` anywhere in `stats` (source fuel, which this protocol does
not support), and it validates the Wasm before accepting it.

**Rejection.** There is no payload, and the metadata is exactly `kind`, `id`,
`epoch`, `revision`, `success` and `diagnostics`. This example is illustrative;
the fictitious source is ASCII, so its byte and UTF-16 offsets coincide:

```json
{
  "kind": "build",
  "id": 8,
  "epoch": "1",
  "revision": 3,
  "success": false,
  "diagnostics": [
    {
      "filename": "/p/src/main.blot",
      "stage": "check-project",
      "code": "unknown_constructor",
      "start": 120,
      "end": 134,
      "message": "unknown record constructor: Thing",
      "offset_encoding": "utf8_bytes",
      "utf16": { "start": 120, "end": 134 },
      "details": null
    }
  ]
}
```

`revision` is unchanged. The server sends exactly one diagnostic; the reference
client requires at least one. Native reader failures use `stage:"asset"`, input
byte offsets and null `utf16`/`details`; native sessions keep the same rejection
metadata shape and empty payload.

| Diagnostic field  | Type                   | Meaning                                                                                                        |
| ----------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------- |
| `filename`        | string                 | the file it is in, else the entry                                                                              |
| `stage`           | string                 | where it was found (below)                                                                                     |
| `code`            | string                 | a stable name for the problem                                                                                  |
| `start`, `end`    | integers, start ≤ end  | UTF-8 byte offsets in `filename`                                                                               |
| `message`         | string                 | for people                                                                                                     |
| `offset_encoding` | `"utf8_bytes"`         |                                                                                                                |
| `utf16`           | `{start, end}` or null | the same span in UTF-16 code units; set only for frontend diagnostics that carry a publication, null otherwise |
| `details`         | null or object         | below                                                                                                          |

`stage` values the server reports are `parse-project`, `load`, `check-project`,
`lower`, `emit`, `asset` and `build-project`. The set is not defined as closed;
hosts should treat an unknown stage as text.

`details` is `null` except for these frontend diagnostics, all from
`check-project`:

- **A typed hole** (`code` `"typed_hole"`): `{"hole": ...}`, the hole's
  snapshot.
- **A failed dispatch**: `{"explanation": ..., "contexts": [...]}`, the
  operation, the member looked up, and each candidate type in the order dispatch
  considered it, with why it was rejected or that it was selected and its result
  conflicted.
- **A mismatch at an application or binary operator**: `{"contexts": [...]}`.

A frontend publication's details are forwarded only when they hold `hole`,
`explanation` or `contexts`; other publications send `null`. `emit` diagnostics
have no details. Their version-one shapes follow. Every named field is present,
including null optionals, unless stated otherwise; numbers are unsigned 32-bit
integers unless stated otherwise.

A `hole` is a bounded, acyclic type graph:

| Field          | Type / meaning                                                             |
| -------------- | -------------------------------------------------------------------------- |
| `expected`     | index in `nodes` of the expected type                                      |
| `nodes`        | at most 1,025 type nodes                                                   |
| `edges`        | at most 4,096 `{name: string or null, type: node index}` edges             |
| `scope`        | at most 32 `{name: string, type: node index, requirements: span}` bindings |
| `requirements` | at most 64 requirement objects (below)                                     |
| `enclosing`    | span in `requirements` for the enclosing binding                           |
| `truncated`    | boolean; some semantic information was omitted                             |

A span is `{start, len}` and selects consecutive entries in the named array.
Every node is `{kind, name, identity, variable, children, effects}`: `name` is
string or null, `identity` is `{unit, decl}` or null, `variable` is an integer
or null, `children` is a span in `edges`, and `effects` is a node index or null.
Child spans of different nodes do not overlap. Function children are
parameter/result; record edges are named. Kinds are `truncated`, `absent`,
`unit`, `boolean`, `u32`, `f32`, `never`, `variable`, `function`, `product`,
`record`, `nominal`, `projection`, `array`, `list`, `cursor`,
`type_constructor`, `resolver`, `provider`, `state_provider`, `effects`,
`operation`, `row_variable` and `row_parameter`.

Every requirement is
`{kind, name, subject, argument, result, signature,
explicit}`. `subject` is a
node index; `argument`, `result` and `signature` are node indexes or null;
`name` is string or null; `explicit` is boolean. Kinds are `arithmetic`,
`ordered`, `equality`, `integer`, `field`, `writable_field`, `dispatch`,
`result_dispatch`, `monad_factory`, `resolver_dispatch`, `resolver_shape`,
`effect_operation`, `effect_handler`, `receiver`, `update`, `type_rep`,
`effect_rep`, `type_head`, `collection`, `record_merge`, `type_eq`, `contract`
and `task_receive`. The last relates a generic task receiver or tuple of
receivers to its result and latent effects. All indexes and spans must be in
bounds. All strings together contain at most 16,384 UTF-8 bytes; identities are
local to this diagnostic.

An `explanation` is `{operation, member, candidates, truncated}`, with `steps`
and `contexts` present only when they are nonempty. `operation` and `member` are
strings or null, at most 256 UTF-8 bytes each. `truncated` is a boolean.
`candidates` holds at most four `{side, operand, outcome}` objects, in lookup
order; a candidate may also carry `origin`, `{name, path, span}` with `name` and
`path` strings or null and `span` `{start, end}` or null. `operand` is string or
null, at most 256 UTF-8 bytes. `side` is `left`, `builtin`, `right`,
`destination`, `receiver` or `implementation`. `outcome` is `head_mismatch`,
`requires_evidence`, `incompatible_type`, `incompatible_effect`, `selected`,
`overlap`, `limit`, `unknown_operand`, `no_member`, `incompatible`,
`unsupported_scalar` or `result_mismatch`. `steps` holds at most eight
`{member, ty, outcome}` objects, with `member` and `ty` strings or null. The
explanation's `contexts` holds at most two
`{kind: "left_operand" | "right_operand", path: string or null, span: {start, end}}`
objects. An explanation with steps, contexts or an `implementation` candidate
encodes to at most 2,048 bytes; the server drops spellings to fit and sets
`truncated`.

The details' own `contexts` holds at most two `{kind, span: {start, end}}`
objects: the source expressions that explain the mismatch, as UTF-8 byte offsets
in the diagnostic's `filename`. `kind` is `callee`, `argument`, `left_operand`
or `right_operand`.

The reference decoders, `readTypedHole` and `readDispatchExplanation` in
[host/type_diagnostics.ts](../../host/type_diagnostics.ts), enforce these bounds
before exposing convenience fields to callers; the client also checks the
details' `contexts` before exposing them.

**Failed operations.** An error while preparing the revision, or while encoding
or bounding its reply, is reported as a rejection with `stage`
`"build-project"`, `start` and `end` 0 and `filename` the entry:

- preparing: `code` is the error's name (`SourceLimit` or `DuplicateSourcePath`
  for overlays, for example), `message` `"Compiler operation failed"`, or
  `"Unable to prepare native asset inputs"` for native asset inputs;
- a reply over the frame limits: `code` `"response_limit"`;
- a reply that cannot be encoded: `code` is the encoder's error name.

The set of error names is not defined as closed. Running out of memory while
preparing sources or compiling, and an error from code generation itself rather
than a diagnostic, stop the process instead.

**When a revision is committed.** Only after its whole reply has been encoded
and fits the limits. If writing a committed reply then fails, the process exits
rather than leave the host and the server disagreeing about the revision.

## complete

With `editor-completion-v1`, a `complete` request asks for completions at a
UTF-8 byte `position` in `filename`, with optional source overlays in the same
form as a build's `sources` and no `assetSources`. It carries `kind`, `id`,
`epoch`, `revision`, a nonzero `snapshot`, `filename` and `position`. It never
advances the revision and emits no Wasm; its reply echoes `snapshot`, `filename`
and `position`. Fields, replies and limits are specified in
[EDITOR_COMPLETION.md](EDITOR_COMPLETION.md#native-request).

## close

The request carries `kind`, `id`, `epoch` and `revision`, with no payload,
`sources` or `assetSources`. Other fields must have the defaults described under
build. The reply is `{"kind": "close", "id": 3, "epoch": "1", "revision": 1}`;
the server then exits 0.

Closing stdin at a frame boundary instead also ends the process with exit 0,
with no reply.

## Errors and cancellation

**Protocol errors.** There is no error reply. On any of the following the server
stops reading, prints `blotc: <ErrorName>` to stderr and exits 1:

- a malformed or oversized frame (`TruncatedFrame`, `FrameTooLarge`);
- invalid JSON, or an unknown, duplicate or mistyped field;
- a missing, null or incompatible open `version` (`VersionMismatch`);
- an `id` out of order (`RequestOrder`);
- a request before open (`NotOpen`) or a second open (`AlreadyOpen`);
- an invalid open (`InvalidOpen`): a missing or bad path, a bad import alias or
  `storage` budget, an `epoch` or `revision`, or overlays or a payload on open;
- an invalid native configuration (`InvalidNativeAssets`) or native
  configuration count (`AssetLimit`);
- a `dependencies` bundle that cannot be read, decoded or validated (its error
  name);
- an open-only field with a non-default value on a later request, `snapshot`,
  `filename` or `position` on a request other than `complete`, nonempty
  `assetSources` in a source-only session or on `complete`, or overlays or a
  payload on `close` (`InvalidRequest`);
- a `complete` without `snapshot`, `filename` or `position`, or whose `filename`
  is not an absolute path of at most 4,096 bytes (`InvalidCompletionRequest`);
- a missing or wrong epoch or revision (`RevisionMismatch`), or a build at
  revision 2^53 − 1 (`RevisionLimit`);
- bad overlay ranges (`InvalidSources`), or more than 4,096 overlays
  (`SourceLimit`).

Requests violating several rules may report the first error detected. JSON
errors print the parser's own error name. Any other error a request causes
outside the build itself also stops the process, and the list of names is not
defined as closed.

A rejected build is not a protocol error: it is the program failing to compile,
and the session goes on.

**The host's side.** The reference client treats as fatal:

- end of output, or a reply whose `kind` or `id` doesn't match its request;
- a missing or wrong `epoch`, a revision that is not the expected one;
- an empty or invalid Wasm payload on success, or a payload on rejection.

It then kills the process, and every queued build fails with that error.

**Cancellation.** A build in progress cannot be cancelled by message
(`abort-disposes-process`). The host kills the process and starts another. A
build still waiting in the host's own queue can simply be dropped, because it
was never sent.

## Typed asset imports

With `native-assets-v1`, the compiler parses configured JSON, catalog, text,
tunables and WGSL inputs and captures reference resources itself. A host sends
`nativeAssets` at open and optional raw `assetSources` at build. See
[NATIVE_ASSETS.md](NATIVE_ASSETS.md) for reader interfaces, discovery, budgets,
errors, snapshot ownership and supported WGSL reflection.

The host `assets` option ([docs/host/assets.md](../host/assets.md)) runs custom
parser functions, sends their generated Blot as source overlays, and retains its
own resource manifest. It uses source-only replies. The reference client
requires a caller to choose either `assets` or `nativeAssets` for one session.

## Versioning

The server advertises `version: 1` in hello. The host must check that exact
version before sending `open` with `version: 1`. The server rejects a missing,
null or different unsigned integer version value with terminal
`VersionMismatch`, exit 1 and no reply. Numeric strings are parsed as described
under Session; their numeric value must be exactly 1. Other uncoercible values
are JSON parser errors. There is no negotiation or fallback. The reference
client rejects a wrong hello version with
`ZigProjectProtocolError("Zig project hello mismatch")` and reaps the child.

The independent conformance host is
[zig_project_protocol.test.ts](../../tests/guest/zig_project_protocol.test.ts).
Run it against any compiler with
`deno test --allow-read --allow-write --allow-run
tests/guest/zig_project_protocol.test.ts -- /absolute/path/to/blotc`.

## Source-only qualification, 11 October 2026

This record qualifies implementation revision `4eabecb` only. That server still
retained sessions and served checkpoints and a restart cache; the record does
not qualify the fresh-build server this document describes.

Implementation revision: `4eabecb`. Zig 0.17.0. The full compiler gate passes
the native suite and 690 guest/client tests. Zero analyzer findings are required
for the local milestone.

[The independent wire host](../../tests/guest/zig_project_protocol.test.ts)
imports neither the production client nor its frame codec. It covers version
admission, canonical request/reply fields, malformed and oversized frames,
ordering, epochs/revisions, source ranges, positioned Unicode diagnostics, owned
hole/dispatch details, rejection recovery, checkpoints, cancellation and close.
Client tests separately cover malformed peers, required stats objects and
booleans, and disposal.

Integer/enum parser allowances are deliberately documented and pinned: a
conforming host emits canonical JSON types, while native admission retains Zig's
existing numeric-string and enum-tag coercions. Unknown and duplicate members
are explicitly rejected. Exhausting 2^53 revisions, native OOM and a naturally
oversized successful Wasm reply are not exercised by the raw host; their limits
and ownership rules remain specified.

Protocol admission adds no compilation pass. Public examples, synthetic
fresh/retained phases and frozen gdev preserve Wasm bytes in the shared
[qualification candidate](PENDING_SELECTIONS.md). These short measurements do
not establish a protocol throughput improvement. The pinned executable for that
qualification has SHA-256
`b4daa696f19692489ac75bc46f9114cf86b7714777099280af2323f78c21c3ff`.
