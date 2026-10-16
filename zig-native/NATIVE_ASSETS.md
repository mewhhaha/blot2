# Native asset imports

`native-assets-v1` extends [project protocol version 1](PROJECT_PROTOCOL.md):
`blotc` captures external bytes and generates typed Blot modules. Hosts send
sources and options; parsing and dependency tracking run inside the compiler.
Source-only sessions retain their existing request/reply behavior. The
TypeScript parser wrapper in [compiler/assets.ts](../compiler/assets.ts) remains
available for custom parsers.

Implementation: [native_assets.zig](src/backend/native_assets.zig),
[native_asset_readers.zig](src/backend/native_asset_readers.zig),
[native_asset_wgsl.zig](src/backend/native_asset_wgsl.zig). Independent framing
and conformance tests live in
[native_asset_protocol.test.ts](tests/native_asset_protocol.test.ts).

## Open and acquire inputs

The hello's capabilities include `native-assets-v1`. A host checks it before
sending `nativeAssets` on `open`:

```json
{
  "kind": "open",
  "id": 1,
  "version": 1,
  "entry": "/game/main.blot",
  "nativeAssets": {
    "imports": [
      {
        "module": "/game/settings.json.blot",
        "path": "/game/settings.json",
        "kind": "json"
      },
      {
        "module": "/game/image.bin.blot",
        "path": "/game/image.bin",
        "kind": "reference",
        "type": "Image",
        "export": "image",
        "mediaType": "application/octet-stream"
      }
    ],
    "roots": ["/game"]
  }
}
```

`nativeAssets` absent or null disables native assets. `{}` enables an empty
native session. `imports` and `roots` default to empty arrays; send arrays, not
null. The open reply remains `{kind,id,epoch,revision}` with no payload.

| Field       | Required       | Meaning                                                                  |
| ----------- | -------------- | ------------------------------------------------------------------------ |
| `module`    | yes            | Absolute virtual module filename, ending in `.blot`.                     |
| `path`      | yes            | Absolute input filename.                                                 |
| `kind`      | yes            | `json`, `catalog`, `text`, `tunables`, `wgsl`, or `reference`.           |
| `type`      | reference only | Nominal Blot type identifier, beginning uppercase.                       |
| `export`    | reference only | Blot value identifier, beginning lowercase or `_`.                       |
| `mediaType` | reference only | Nonempty valid UTF-8 media type, at most 256 UTF-16 units; no CR/LF/NUL. |

Other readers require `type`, `export`, and `mediaType` to be absent or null.
Reference readers require all three as nonnull values. Names cannot be `_`, a
language keyword, or a reserved primitive type. Paths must be absolute,
well-formed UTF-8, and contain no NUL. All native configuration is fixed at
open; changing it requires a new process. The reference client accepts relative
configuration paths and supplies defaults before sending this canonical schema;
those conveniences are host behavior, not raw-wire defaults.

Each root is a directory containing these optional inputs:

| Input                                | Reader   | Virtual module              |
| ------------------------------------ | -------- | --------------------------- |
| `assets/catalog.json`                | catalog  | `assets/catalog.json.blot`  |
| `text.json`                          | text     | `text.json.blot`            |
| `tunables.json`                      | tunables | `tunables.json.blot`        |
| direct regular `assets/*.wgsl` files | WGSL     | input filename plus `.blot` |

Discovery runs every build. New and removed files change the candidate's module
set; a supplied asset overlay can add a nonexistent discovered input or hide
one. Subdirectories are not recursively scanned. Explicit mappings can point at
symlinked inputs. Filesystem and overlay identity resolve existing prefixes
through symlinks, including the parents of nonexistent virtual files.
Retargeting an input symlink changes the captured canonical input and revokes
parse reuse.

Explicit mappings and root discovery are combined. Discovery deduplicates its
own lexical virtual module spellings, including repeated roots and disk/overlay
observations. Distinct symlinked root spellings can still collide after
canonicalization. An explicit alias pointing at the same input does not suppress
its normal discovered module; distinct modules can share one captured input.
Canonical virtual module collisions between explicit mappings and discovery
reject with `DuplicateAssetModule`, even when they otherwise describe the same
input. Explicit duplicate mappings and collisions with source overlays or the
entry also reject. These are build failures rather than terminal open errors.
Canonical duplicate asset overlay paths reject with `DuplicateSourcePath`.

## Build payload

Native builds accept `assetSources` beside ordinary `sources`. Both use
`{path,start,length,deleted?}` entries and one shared frame payload. Source
ranges partition its prefix, starting at zero; asset ranges partition the rest,
starting at the end of that prefix. There are no gaps, overlaps, or unused
bytes. Metadata array order is payload order. Omitted or empty arrays have no
ranges. A deleted range has `deleted:true` and length zero.

```json
{
  "kind": "build",
  "id": 2,
  "epoch": "1",
  "revision": 0,
  "sources": [
    { "path": "/game/main.blot", "start": 0, "length": 32 }
  ],
  "assetSources": [
    { "path": "/game/settings.json", "start": 32, "length": 13 },
    { "path": "/game/image.bin", "start": 45, "length": 3 }
  ]
}
```

This example describes a 48-byte payload; its byte contents are illustrative.
Source bytes must be UTF-8. Asset bytes are raw: a binary reference can contain
NUL, `0xff`, or an empty file. JSON and WGSL readers independently validate
their text encoding. Each build sends its complete override set: omitted paths
read disk; null/deleted paths hide the input for that build. Previous overrides
are never inherited. Neither source nor asset overlays write to disk.

`assetSources` with nonempty ranges requires a native session. Native options
cannot be changed on `build`. `close` and `checkpoint` accept no source or asset
ranges. Range failures are terminal `InvalidSources`; too many ranges are
terminal `SourceLimit`, as in the base protocol. Configuration objects follow
the base protocol's explicit unknown/duplicate-field rejection and Zig parsing
rules. Canonical hosts emit string enum names and JSON numbers. Zig also accepts
reader enum tags `0..5`, in the order json/catalog/text/tunables/wgsl/reference.

## Successful snapshot

A successful native reply adds four fields to the ordinary build metadata:

| Field               | Meaning                                               |
| ------------------- | ----------------------------------------------------- |
| `wasmBytes`         | Length of the Wasm prefix in the frame payload.       |
| `assets`            | Owned resource ranges, ordered by positive handle ID. |
| `assetDependencies` | Input paths and their captured SHA-256 digests.       |
| `assetStats`        | `{parsed,reused,inputBytes,generatedBytes}` counters. |

`assets` entries have exactly `{id,path,mediaType,sha256,start,length}`. IDs are
contiguous `1..N`; zero is never a content handle. `start` offsets are relative
to the whole payload, first at `wasmBytes`, then contiguously after the
preceding resource. The final range ends at payload length. A zero-length
resource still gets an ID and a range. `path` is canonical and absolute;
`sha256` is lowercase hexadecimal.

References deduplicate by canonical input path, media type, and content digest.
Sort JSON strings for `[path,mediaType,sha256]` by JavaScript UTF-16 lexical
order to assign IDs. Mapping order does not affect the result. Different paths
or media types remain separate resources even when their bytes match. IDs belong
to a snapshot: adding/removing/changing resources can renumber them. Hosts pair
the Wasm and resource array from the same successful reply.

`assetDependencies` entries have exactly `{path,sha256}` and sort by JavaScript
UTF-16 path order. `path` is the configured/discovered spelling; a resource's
canonical path can therefore differ from its dependency path. The schema permits
a null digest for an absent input. Current successful snapshots list acquired
inputs with 64-digit digests; absent optional discovered inputs are omitted,
while missing required inputs reject the build. Multiple mappings of one
spelling share one dependency. A symlink retarget captures its new target; the
digest changes when those bytes differ, while the reported spelling stays
unchanged. Changing the canonical input revokes parse reuse even when its bytes
match.

Counters are nonnegative integers. `parsed` counts freshly generated mappings,
including reference mappings; `reused` counts mappings whose canonical module,
canonical input, reader kind, and exact bytes match the last successful
candidate. Reading unchanged disk bytes still counts toward `inputBytes`: reuse
saves parsing, not acquisition. Bytes shared through one canonical input are
counted once. `generatedBytes` sums generated Blot modules. Resources are
included only by the reference reader; catalog indexes are unrelated.

The payload owns Wasm and captured resource bytes. A host copies the slices it
retains before reusing its read buffers. Later builds, failed builds, checkpoint
operations, and process disposal cannot mutate an already copied snapshot.
Content upload uses these bytes rather than reopening the reported path.

## Reader interfaces

All exported value/field names obey Blot identifiers. Readers generate imports
in memory; no `.blot` file is written. Imports use the original input spelling,
for example `import * as config from "./settings.json"` resolves its configured
`settings.json.blot` virtual module.

**JSON.** Export `value` and `Data`. An object root gives nominal
`type Data is data = #Data { ... }`; other roots give a transparent `Data`
alias. Nested object shapes use shared nominal `JsonRecordN` types. Object
fields sort by spelling. Duplicate JSON members use the last value, like
`JSON.parse`; this is distinct from protocol metadata, where duplicates reject.

| JSON value                                                    | Blot representation                             |
| ------------------------------------------------------------- | ----------------------------------------------- |
| null                                                          | Unit, `()`                                      |
| boolean                                                       | Bool                                            |
| nonnegative integral number fitting U32, except negative zero | U32                                             |
| other finite numbers fitting finite binary32                  | F32, rounded to binary32                        |
| string                                                        | `Utf8 { bytes: Array U32 }`, actual UTF-8 bytes |
| array with one common element shape                           | `Array` of that shape                           |
| heterogeneous array                                           | Exact tuple; empty array is `()`                |

Numbers first use JSON binary64 semantics; unsafe integral values reject.
Strings must contain well-formed Unicode. Preserve negative zero. Recursive
structures are limited to depth 128 and 1,000,000 visited nodes.

**Catalog.** Export nominal `Meshes`, `Materials`, `Sounds` and values `meshes`,
`materials`, `sounds`; each record field contains its zero-based list index.
Missing/null categories are empty. Categories must be arrays of filename
strings. Strip a terminal `.mesh.json`/`.material.json`, then terminal
`.wav`/`.ogg`/`.json`; replace other non-ASCII letters/digits/underscore with
underscore. This does not truncate at the first dot. Duplicate normalized names
reject. Unknown root keys are ignored. These indexes do not capture mesh,
material, or sound file bytes and do not create content resources.

**Text.** Export nominal `Text` and value `text`. Each root field must be a
string (`Array U32`) or string list (`Array (Array U32)`); values contain
Unicode code points. Accept printable ASCII U+0020..U+007E and exactly this
`fontExtra`:

```
åäöÅÄÖéüÉ‹›•…×–—
```

Any other glyph rejects with `asset_font`; the message lists distinct missing
code points in first-occurrence order, bounded to 512 encoded bytes. Newline is
not a glyph. A supplementary character is one code point, not two UTF-16 units.

**Tunables.** Read `{tunables:[...]}`; export nominal `Tunables`, value
`tunables`, nominal `Declaration`, and `declarations: Array Declaration`.
Entries require `name`, `default`, `min`, and `max`; `step` and `doc` are
optional. Names are lowercase dotted words; digits and underscore can occur
after each word's first letter. Replace dots with underscore for record fields.
Duplicate names/normalized fields/IDs reject. ID is FNV-1a32 of the name, then
`((hash >> 24) ^ hash) & 0xffffff`.

Each field is `(id:U32, initial:F32, least:F32, most:F32)` as a tuple. Check
finite binary32 bounds and compare rounded values: `least < most` and
`least <= initial <= most`. Unknown entry fields reject. Optional `step` must
fit finite binary32 and its original binary64 value must be positive; a tiny
positive value rounding to zero is accepted. Step is not exported. Declaration
records contain
`{name:Array U32,id:U32,initial:F32,least:F32,most:F32,doc:Array U32}` in input
order. Name/doc use `shown`: unsupported code points become decimal 63. An
astral glyph becomes one `?`; newline also becomes `?`. Missing doc is empty.
This replacement applies to metadata only; the text reader rejects missing
glyphs.

**WGSL.** Reflect `struct Parameters`, when present, as nominal Blot
`Parameters` with at most four fields, all resolving to f32, including aliases.
Empty Parameters is allowed. Export module constants only when the pinned
`wgsl_reflect` 1.6.0 parser folds them to scalar literal expressions with type
f32, u32, or bool. i32, bare integer x32, vectors, matrices, and other
expressions are not exported. Declared annotations do not convert an expression:
even `const x:u32=2` remains an unexported x32.

The native reader recognizes bounded declarations, attributes, nested comments,
types, expressions, and structured function-body syntax. Its scalar evaluator
supports constant references, casts, arithmetic/bitwise/comparison/boolean
operators, vectors/arrays and indexing/swizzles, common scalar math and bit
builtins, component-wise vector math, dot/length/distance, and select/all/any.
It is a reflection reader rather than a WGSL semantic checker or GPU validator.
Complex matrix operations and packing/struct-result reflection builtins in
module constants currently reject with `asset_wgsl_evaluation`; they are not
silently accepted with missing exports. No qualified private shader needs them.

Public laws preserve observed 1.6.0 asset ABI quirks: hexadecimal floats fold to
zero; direct bitcast is not exported but a surrounding scalar cast can fold it;
arrayLength yields reflected byte size; unsigned extractBits is declined; cosh
dispatches cosine. Malformed missing initializers and unterminated comments are
rejected even though the pinned parser has accepted those forms. Syntax limits
are 128 nesting levels, 1,000,000 tokens/work visits, and 16 MiB input. Shared
constant graphs consume the same work budget.

**Reference.** Export `type T is data = #T U32` and the configured value
containing its positive snapshot handle. Capture the file unchanged, including
arbitrary binary data. Only this reader contributes resources; it does not parse
content.

## Rejection and publication

Reader issues return ordinary unsuccessful build replies with one diagnostic:
`stage:"asset"`, the input filename, byte `start`/`end`, static `code`, bounded
message (at most 1024 UTF-8 bytes, truncated at code point boundaries),
`offset_encoding:"utf8_bytes"`, `utf16:null`, `details:null`, and
`attemptStats:null`. The payload is empty. Codes include `asset_json`,
`asset_unicode`, `asset_catalog`, `asset_text`, `asset_font`, `asset_tunables`,
`asset_wgsl`, `asset_wgsl_parameters`, `asset_wgsl_evaluation`,
`asset_identifier`, `asset_number`, `asset_limit`, `asset_input`, and
`asset_missing`. Acquisition and mapping-operation errors can use
`stage:"build-project"` with an error-name code instead. Missing explicit inputs
fail; deleted optional root inputs simply leave discovery.

A compiler rejection after valid asset parsing keeps the same revision too.
Neither rejection publishes a new asset cache. Both compiler and asset
candidates transfer only after successful encoding and bounds validation of the
whole metadata-plus-Wasm-plus-resources reply. `response_limit` leaves both old
owners intact. A subsequent identical build can reuse the last successful parsed
modules; a failed candidate cannot seed that reuse. Allocation failures
propagate; no partial snapshot is reported as success.

Bounds remain the base protocol's 1 MiB metadata and 64 MiB complete frame.
Configuration admits at most 4096 imports and roots combined; discovery plus
explicit imports admit at most 4096 generated mappings. Inputs/generated modules
have 16 MiB per-file and 64 MiB total budgets. Source and asset overlay arrays
each have their own 4096-entry bound. The per-file byte limit is inclusive. Disk
acquisition uses a one-byte larger read bound before applying that limit.

Cancellation follows the base protocol: aborting an active request kills and
reaps the process. There is no wire cancel message. Already copied successful
Wasm and resources remain valid. Checkpoints capture the compiler's successful
semantic candidate, not a permission to skip reacquiring external inputs in a
new process; native asset configuration must be supplied again on reopen.

## Qualification

Zig 0.17.0: `deno task test:compiler` passes the full native suite and 743
guest/client tests. The analyzer reports zero findings across 318 Zig files.
Typechecking, formatting and the package publish dry run pass. The release
compiler SHA-256 is
`3829910fe42565c754d78f3437a873d218ef0f2c17206cb2263f8f8d3c5fd47b`.

The raw-wire suite exercises real executed Wasm, every reader, non-UTF-8 binary
references, combined request/reply ranges, deterministic resource deduplication,
parse reuse, disk/overlay edits and deletion, compiler and asset rejection
recovery, root additions/removals, symlink retargeting, collisions, old snapshot
ownership, terminal malformed requests, and oversized reply publication. All 37
independent wire cases pass; native reader/session laws sweep allocation
failures, and client laws validate replies and own captured inputs/results.

Read-only comparisons against the normative sibling parser matched generated
WGSL source for all 33 private shaders and 73 public synthetic expressions.
Private source/assets remain outside this repository; ignored bench storage
contains reproduction and aggregate qualification evidence. These comparisons
qualify the current private corpus, not every valid WGSL program.

Three alternating host/native pairs using the same release compiler preserve
Wasm, asset snapshots and dependency digests through fresh/no-op builds, source
edits/reverts, text edits/reverts, malformed JSON and recovery. The frozen game
discovers 34 modules from 294,841 input bytes and generates 14,296 source bytes.
A text edit reparses one module and reuses 33; unchanged inputs and recovery
reuse all 34. Both paths report the same counters. The frozen parser has no
tunables input; public wire tests cover that reader separately.

The frozen game Wasm remains 840,534 bytes, SHA-256
`3158216b0b7cb072245d9aa149887a39bbadbc305430569ae3e033818e3edef0`. Its manifest
has 34 dependencies and no content resources. Binary reference ownership, IDs
and nonempty snapshots are qualified by public wire/client laws. Current game
fixtures pass 472 cases across 54 regular modules, plus 12 split-hauling exports
with 25 assertions. All 13 public examples and every fresh/retained phase of the
four synthetic workloads preserve Wasm bytes against the preceding compiler.

[Measurements](qualification/native-assets.csv) and
[pins](qualification/native-assets-pins.json) separate child compiler CPU from
the Deno host's CPU. Fresh medians are 1,540/1,470 ms child CPU and 410/10 ms
host CPU (host/native imports). Source-edit child medians are 640/620 ms,
text-edit 710/720 ms, and no-op 10/10 ms. Host parsing leaves the application
process; retained semantic compilation costs remain similar. Samples overlap
native test compilation and other local work. These three pairs do not establish
a general compiler speedup or a quiet-machine latency target. Input acquisition
still reads and hashes unchanged disk bytes.

```sh
deno test --allow-read --allow-write --allow-run \
  zig-native/tests/native_asset_protocol.test.ts -- /absolute/path/to/blotc
```
