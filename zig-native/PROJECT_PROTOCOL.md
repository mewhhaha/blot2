# The `serve-project` protocol

`blotc serve-project` keeps one Blot project open in a child process and builds
it on request, reusing unchanged work between revisions. A host talks to it over
the child's stdin and stdout in length-prefixed frames. This document is enough
to write a host without `@mewhhaha/blot`. It describes protocol version 1 as
implemented by this repository:

- the server: [zig_project_server.zig](src/zig_project_server.zig) and
  [zig_project_frames.zig](src/zig_project_frames.zig);
- the reference client:
  [compiler/zig_project_client.ts](../compiler/zig_project_client.ts), behind
  `createCompiler` and `createZigProjectCompiler`
  ([PROJECT_CLIENT.md](PROJECT_CLIENT.md));
- making it a versioned public contract with conformance tests:
  [task 095](../tasks/095-specify-and-version-the-project-protocol.md);
- native typed imports and resource snapshots:
  [NATIVE_ASSETS.md](NATIVE_ASSETS.md).

Where the server and the reference client differ, both are stated. Example IDs
and revisions are illustrative; replies always echo the request ID and use the
session revision rules below.

## Starting the compiler

```
blotc serve-project
blotc serve-project --semantic-workers N    (N in 1..16)
```

Any other arguments make the process print `blotc: InvalidServeArguments` to
stderr and exit 1. `--semantic-workers` opts into private semantic jobs; the
default is serial.

- **stdin** carries request frames and **stdout** reply frames, nothing else.
- **stderr** is free text for people. When the process stops on an error, its
  last line is `blotc: <ErrorName>`. The reference client keeps the last 64 KiB
  of it to put in its error messages.
- **Environment.** Only the restart cache reads it, and only to find its root:
  1. `BLOT_CACHE_DIR`: an absolute path is the complete root; empty or relative
     disables the cache.
  2. Windows: `%LOCALAPPDATA%\Blot`.
  3. `$XDG_CACHE_HOME/blot`, if that variable holds an absolute path.
  4. `$HOME/Library/Caches/blot` on macOS, `$HOME/.cache/blot` elsewhere.

  The reference client starts the child with a cleared environment holding only
  those four variables.
- **Where blotc comes from.** `@mewhhaha/blot` bundles a gzipped Linux x86-64
  `blotc` (`generated/compiler/blotc.gz`). The reference client unpacks it to a
  temporary `blotc-*` file before spawning it. A host can run any `blotc`
  instead; the hello's `compilerIdentity` says which one it got.

## Frames

Every message, in either direction, is one frame:

| Bytes      | Contents                                                          |
| ---------- | ----------------------------------------------------------------- |
| 0..4       | metadata length `M`, unsigned 32-bit little-endian                |
| 4..8       | payload length `P`, unsigned 32-bit little-endian                 |
| 8..8+M     | metadata: one JSON object, UTF-8                                  |
| 8+M..8+M+P | payload: raw bytes (sources/assets, Wasm/resources or checkpoint) |

- `M` is from 1 to 1,048,576, and `8 + M + P` is at most 67,108,864
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
client: checkpoint server: checkpoint (any time after open)
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
  or their decimal strings: `kind` tags are open 0, build 1, close 2, checkpoint
  3; `codegenTier` tags are optimized 0 and development 1. Booleans, arrays and
  objects are not coerced to integers. Optional fields may be left out. Replies
  normally write an optional field with no value as `null`. A diagnostic's
  `related` field is omitted when there is no secondary location. The reference
  client ignores reply fields it does not read. Hosts should ignore unknown
  reply fields; incompatible request or reply changes require a new version.

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
`compiler_fingerprint.zig`). Two processes with the same identity are the same
compiler. Checkpoints, dependency bundles and the restart cache are only reused
under the identity that made them.

| Capability               | Meaning                                                           |
| ------------------------ | ----------------------------------------------------------------- |
| `project-build`          | builds a project from an entry file                               |
| `utf8_bytes`             | diagnostic offsets are UTF-8 byte offsets                         |
| `abort-disposes-process` | there is no cancel request: a host cancels by killing the process |
| `source-overlays`        | a build may carry `sources`                                       |
| `backend-checkpoints`    | an open may carry a checkpoint, and `checkpoint` requests work    |
| `native-assets-v1`       | native readers, asset overlays and owned content snapshots        |

The reference client checks the hello:

- `protocol`, `version` and `maxFrameBytes` match exactly;
- the identity has the right form;
- the first three capabilities are present;
- the identity is the one the caller asked for, if it asked
  (`expectedCompilerIdentity`);
- with no `source-overlays`, it refuses builds that carry `sources`;
- with no `native-assets-v1`, it refuses an open configured with `nativeAssets`.

It allows 30 s by default (1 to 300 s) for the hello and the open together.

## open

| Field              | Type                             | Rule                                                                       |
| ------------------ | -------------------------------- | -------------------------------------------------------------------------- |
| `kind`             | `"open"`                         |                                                                            |
| `id`               | integer                          | see Session                                                                |
| `version`          | unsigned 32-bit integer          | required, exactly `1`                                                      |
| `entry`            | path                             | required: the program's entry file                                         |
| `prelude`          | path or null                     | the prelude module; absent or null: none                                   |
| `stdRoot`          | path or null                     | the root of the `std/` alias                                               |
| `imports`          | array of `{prefix, root}`        | more directory aliases                                                     |
| `dependencies`     | path or null                     | a `.blotdep` bundle from `blot dependencies`                               |
| `profileBackend`   | boolean                          | detailed backend timings (default false)                                   |
| `codegenTier`      | `"optimized"` or `"development"` | default `"optimized"`; development skips optional scalar and vector passes |
| `shareMachineCode` | boolean                          | prototype; default false                                                   |
| `codegenWorkers`   | integer 1..16                    | default 1                                                                  |
| `checkpoint`       | boolean                          | true exactly when the payload holds checkpoint bytes                       |
| `nativeAssets`     | object or null                   | optional native input configuration; absent/null disables it               |

- **Paths.** Every path is absolute, non-empty and free of NUL bytes.
- **`imports`.** Each `prefix` is non-empty, ends in `/`, has no NUL and is
  unique; each `root` is a path.
- **`nativeAssets`.** Requires `native-assets-v1`; `{}` enables an empty native
  session. `imports` and `roots` default to `[]`. Import definitions, discovery,
  paths and reader-specific fields are specified in
  [NATIVE_ASSETS.md](NATIVE_ASSETS.md#open-and-acquire-inputs).
- **Other fields:** `epoch` and `revision` must be absent or `null`; `sources`
  and `assetSources` must be absent or `[]`. Arrays and booleans do not accept
  `null`.
- **Defaults:** `imports` defaults to `[]`, `checkpoint` to `false`; optional
  paths default to `null`. All optional configuration fields may be omitted.
- **Payload.** Checkpoint bytes from an earlier `checkpoint` reply when
  `checkpoint` is true; otherwise empty.
- **Reply:** `{"kind": "open", "id": 1, "epoch": "1", "revision": 0}`, with no
  payload.

A checkpoint, and the restart cache when no checkpoint is given, are only
candidates. Bytes that do not decode for this compiler are ignored, and they
never replace checking the sources. `dependencies` is read once at open, with
its canonical settings; every revision still resolves paths again.

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

A build, checkpoint or close may carry the open's fields only at their defaults
(absent, `null`, `false`, `[]`, `"optimized"`, `codegenWorkers` 1, `checkpoint`
false); any other value stops the process with `InvalidRequest`. `version` must
be absent or `null` after open. `nativeAssets` must also be absent or `null`; an
empty object is still an open-only configuration.

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
  with `stage: "build-project"`, `code: "DuplicateSourcePath"` and
  `attemptStats: null`; the revision is unchanged.
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
    "nativeWorkSteps": 0,
    "sourceBytes": 0,
    "freshModules": 0,
    "cachedModules": 0,
    "restartCacheLoaded": false,
    "frontend": {},
    "backend": {},
    "optimization": {},
    "runtimeOptimization": {},
    "backendTiming": {},
    "workCounters": {},
    "principals": {},
    "refinements": {},
    "selectedQueries": {},
    "attemptStats": {}
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
Both compiler and asset candidates commit only after the whole reply has been
encoded and bounded; a rejection preserves both previous successful owners and
the revision.

`stats` holds these fields:

- integers: `nativeWorkSteps`, `sourceBytes`, `freshModules` and
  `cachedModules`;
- objects: `frontend`, `backend`, `optimization`, `runtimeOptimization`,
  `backendTiming`, `workCounters`, `principals`, `refinements`,
  `selectedQueries` and `attemptStats`;
- a boolean: `restartCacheLoaded`.

The objects are measurements for people, and their insides are not part of the
contract. The reference client validates the four integers as nonnegative safe
integers, all ten named objects as objects, and `restartCacheLoaded` as a
boolean. It refuses `const_steps` and `remaining_steps` anywhere in `stats`
(source fuel, which this protocol does not support), and it validates the Wasm
before accepting it.

**Rejection.** There is no payload. This example is illustrative; the fictitious
source is ASCII, so its byte and UTF-16 offsets coincide:

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
      "stage": "check",
      "code": "unknown_constructor",
      "start": 120,
      "end": 134,
      "message": "unknown record constructor: Thing",
      "offset_encoding": "utf8_bytes",
      "utf16": { "start": 120, "end": 134 },
      "details": null
    }
  ],
  "attemptStats": {}
}
```

`revision` is unchanged. The server sends exactly one diagnostic; the reference
client requires at least one. Native reader failures use `stage:"asset"`, input
byte offsets, null `utf16`/`details` and `attemptStats:null`; native sessions
retain the same rejection metadata shape and empty payload. `attemptStats` is an
object, or null when no attempt counters survived (a failed preparation).

| Diagnostic field  | Type                   | Meaning                                                                                                                         |
| ----------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `filename`        | string                 | the file it is in, else the entry                                                                                               |
| `stage`           | string                 | where it was found (below)                                                                                                      |
| `code`            | string                 | a stable name for the problem                                                                                                   |
| `start`, `end`    | integers, start ≤ end  | UTF-8 byte offsets in `filename`                                                                                                |
| `message`         | string                 | for people                                                                                                                      |
| `offset_encoding` | `"utf8_bytes"`         |                                                                                                                                 |
| `utf16`           | `{start, end}` or null | the same span in UTF-16 code units; set only for frontend diagnostics that carry a publication, null otherwise                  |
| `related`         | object or null         | original callee location: `{filename, start, end, offset_encoding: "utf8_bytes"}` for a caller-dependent specialization failure |
| `details`         | null or object         | below                                                                                                                           |

`stage` values the code uses are `parse`, `parse-project`, `load`, `check`,
`check-project`, `lower`, `emit`, `asset` and `build-project`. The set is not
defined as closed; hosts should treat an unknown stage as text.

`related` is optional and omitted when there is no secondary location. Hosts
also accept null. Its filename is a nonempty, well-formed string without NUL;
its offsets are nonnegative safe integers with start ≤ end. The reference client
rejects malformed coordinates and copies only those four fields. The primary
location remains the outermost caller use whose types caused the failure; a
concrete failure inside a callee stays at its own operation.

`details` is `null` except in two cases:

- **A typed hole** (`code` `"typed_hole"`): `{"hole": ...}`, the hole's
  snapshot, forwarded from the frontend's publication.
- **A failed dispatch**: `{"explanation": ...}`, the operation, the member
  looked up, and each candidate type in the order dispatch considered it, with
  why it was rejected or that it was selected and its result conflicted. It
  comes from the check stage (`check`, `check-project`), forwarded from the
  frontend's publication, and from the backend for `emit` diagnostics.

A frontend publication's details are forwarded only when they hold `hole` or
`explanation`; other publications send `null`. Their version-one shapes follow.
Every named field is present, including null optionals; numbers are unsigned
32-bit integers unless stated otherwise.

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
`record`, `nominal`, `array`, `list`, `cursor`, `demand`, `type_constructor`,
`resolver`, `provider`, `state_provider`, `effects`, `operation`, `row_variable`
and `row_parameter`.

Every requirement is
`{kind, name, subject, argument, result, signature,
explicit}`. `subject` is a
node index; `argument`, `result` and `signature` are node indexes or null;
`name` is string or null; `explicit` is boolean. Kinds are `arithmetic`,
`ordered`, `equality`, `integer`, `field`, `writable_field`, `dispatch`,
`result_dispatch`, `monad_factory`, `resolver_dispatch`, `resolver_shape`,
`effect_operation`, `effect_handler`, `receiver`, `update`, `type_rep`,
`effect_rep`, `type_head`, `collection` and `record_merge`. All indexes and
spans must be in bounds. All strings together contain at most 16,384 UTF-8
bytes; identities are local to this diagnostic.

An `explanation` is `{operation, member, candidates, truncated}`. `operation`
and `member` are strings or null, at most 256 UTF-8 bytes each. `truncated` is a
boolean. `candidates` holds at most four `{side, operand, outcome}` objects, in
lookup order. `operand` is string or null, at most 256 UTF-8 bytes. `side` is
`left`, `builtin`, `right`, `destination` or `receiver`; `outcome` is
`unknown_operand`, `no_member`, `incompatible`, `unsupported_scalar` or
`result_mismatch`. These are failures: a selected member can appear with
`result_mismatch` when its result conflicts with the destination.

The reference decoders, `readTypedHole` and `readDispatchExplanation` in
[compiler/type_diagnostics.ts](../compiler/type_diagnostics.ts), enforce these
bounds before exposing convenience fields to callers.

**Failed operations.** An error while preparing the revision, or while encoding
or bounding its reply, is reported as a rejection with `stage`
`"build-project"`, `start` and `end` 0 and `filename` the entry:

- preparing: `code` is the error's name (`SourceLimit` for overlays, for
  example), `message` `"Compiler operation failed"`, `attemptStats` null;
- a reply over the frame limits: `code` `"response_limit"`;
- a reply that cannot be encoded: `code` is the encoder's error name.

The set of error names is not defined as closed.

**When a revision is committed.** Only after its whole reply has been encoded
and fits the limits. If writing a committed reply then fails, the process exits
rather than leave the host and the server disagreeing about the revision.

**The restart cache.** It is saved after the first successful build and again at
close. Its file sits under the cache root, keyed by the compiler identity and
the entry.

## checkpoint

The request carries `kind`, `id`, `epoch` and `revision`, with no payload. Other
fields must have the defaults described under build. It never advances the
revision.

- **Success:**
  `{"kind": "checkpoint", "id": 2, "epoch": "1", "revision": 1, "success": true}`,
  with the checkpoint as payload: portable backend candidates of the last
  successful revision. Open a later process of the same compiler with it
  (`checkpoint: true`) to start warm.
- **Failure:** the same fields with `"success": false`, a `code` (the error's
  name, or `"checkpoint_limit"` when the bytes would exceed `maxFrameBytes`
  − 1024) and no payload.

## close

The request carries `kind`, `id`, `epoch` and `revision`, with no payload. Other
fields must have the defaults described under build. The reply is
`{"kind": "close", "id": 3, "epoch": "1", "revision": 1}`. The server saves the
restart cache, then exits 0.

Closing stdin at a frame boundary instead also ends the process with exit 0,
with no reply and no cache save.

## Errors and cancellation

**Protocol errors.** There is no error reply. On any of the following the server
stops reading, prints `blotc: <ErrorName>` to stderr and exits 1:

- a malformed or oversized frame (`TruncatedFrame`, `FrameTooLarge`);
- invalid JSON, or an unknown, duplicate or mistyped field;
- a missing, null or incompatible open `version` (`VersionMismatch`);
- an `id` out of order (`RequestOrder`);
- a request before open (`NotOpen`) or a second open (`AlreadyOpen`);
- an invalid open (`InvalidOpen`), native configuration (`InvalidNativeAssets`)
  or native configuration count (`AssetLimit`);
- an open-only field with a non-default value on a later request, nonempty
  `assetSources` in a source-only session, or source/asset ranges or a payload
  on `checkpoint` or `close` (`InvalidRequest`);
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
(`abort-disposes-process`). The host kills the process and starts another; the
restart cache, or a checkpoint taken earlier, makes the new one's first build
warm. A build still waiting in the host's own queue can simply be dropped,
because it was never sent.

## Typed asset imports

With `native-assets-v1`, the compiler parses configured JSON, catalog, text,
tunables and WGSL inputs and captures reference resources itself. A host sends
`nativeAssets` at open and optional raw `assetSources` at build. See
[NATIVE_ASSETS.md](NATIVE_ASSETS.md) for reader interfaces, discovery, budgets,
errors, retained ownership and supported WGSL reflection.

The existing host `assets` option ([compiler/assets.md](../compiler/assets.md))
still runs custom parser functions, sends their generated Blot as source
overlays, and retains its own resource manifest. It uses source-only replies.
The reference client requires a caller to choose either `assets` or
`nativeAssets` for one session.

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
[zig_project_protocol.test.ts](tests/zig_project_protocol.test.ts). Run it
against any compiler with
`deno test --allow-read --allow-write --allow-run
zig-native/tests/zig_project_protocol.test.ts -- /absolute/path/to/blotc`.

## Source-only qualification, 11 October 2026

Implementation revision: `4eabecb`. Zig 0.17.0. The full compiler gate passes
the native suite and 690 guest/client tests. Zero analyzer findings are required
for the local milestone.

[The independent wire host](tests/zig_project_protocol.test.ts) imports neither
the production client nor its frame codec. It covers version admission,
canonical request/reply fields, malformed and oversized frames, ordering,
epochs/revisions, source ranges, positioned Unicode diagnostics, owned
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
