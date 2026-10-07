# Typed external assets

`createCompiler` and `createZigProjectCompiler` accept explicit parser functions
in an `assets` map. The map keys are virtual Blot module paths, relative to the
entry file. Input paths are also relative to the entry, or absolute local paths.
Normal source imports refer to those modules. No generated source file is
written to disk, and the native compiler has no JSON or shader name checks.

```ts
import { createCompiler, jsonAssetParser } from "@mewhhaha/blot";

const compiler = await createCompiler({
  entry: "./src/main.blot",
  assets: {
    "./settings.json": {
      path: "../assets/settings.json",
      parser: jsonAssetParser,
    },
  },
});
try {
  const build = await compiler.build();
  if (!build.success) throw new Error(JSON.stringify(build.diagnostics));
  // build.bytes is Wasm. build.assetDependencies lists input paths/digests.
} finally {
  await compiler.dispose();
}
```

For a JSON file containing `{"width":1280,"height":720}`, source can use:

```blot
import { Data, value } from "./settings.json"
const width = fn (settings: Data) => settings.width
entry const initial_width = fn () => width value
```

The JSON parser exports `value` and its `Data` type. Nested objects get ordinary
nominal record types. Equal nested shapes share a type. All generated
declarations pass the ordinary checker and backend. Use named imports or
parentheses to project from a qualified module value: `(settings.value).width`.

## Parser contract

A parser receives `path`, a copy of the input `bytes`, an optional cancellation
`signal`, and tracked `read(path)` / `reference(path?, mediaType?)` functions.
These paths resolve relative to the canonical input file. It returns:

```ts
import type { AssetModule, AssetParser } from "@mewhhaha/blot";

const parseSettings: AssetParser = (context): AssetModule => {
  const settings = JSON.parse(new TextDecoder().decode(context.bytes));
  return {
    values: {
      value: {
        type: { name: "Settings", fields: { width: "U32" } },
        value: { width: settings.width },
      },
    },
  };
};
```

Supported descriptions are `"Unit"`, `"Bool"`, `"U32"`, `"F32"`,
`{ array: elementType }`, `{ tuple: elementTypes }`,
`{ name: "RecordName", fields: { field: fieldType } }`, and
`{ reference: "ResourceName" }`. `Unit` values use `null`. Record values must
contain exactly the described fields. Names, numeric ranges, nesting and source
sizes are checked. Types can be exported without values using `types: [...]`.
Use `aliases: { Name: description }` for transparent names of scalar, array or
tuple types; these do not add a nominal wrapper or allocation.

The supplied JSON parser infers U32 for nonnegative 32-bit integers and F32 for
other representable numbers; F32 conversion rounds to binary32. Integers outside
JavaScript's exact range are rejected. Homogeneous arrays become `Array`; empty
and heterogeneous arrays become exact tuples. Custom parsers can specify the
element type of an empty array or require a fixed schema instead.

JSON field names must currently be Blot identifiers. Strings become a generated
`Utf8 { bytes: Array U32 }` record containing UTF-8 bytes. This uses one U32 per
byte and is not a compact runtime Text implementation. A parser for larger text
or binary content should return a host reference. General compact Text remains
separate language work. Structural records are available in the language; this
adapter currently emits named records so shader and JSON descriptions can export
constructors as well as types.

## Shader input types and host references

A shader adapter can use a real WGSL/SPIR-V/other parser or consume validated
reflection metadata, then return just its input record types and a reference:

```ts
import type { AssetParser, AssetRecordType } from "@mewhhaha/blot";

// reflectInputs is supplied by the application or shader parser package.
function shaderParser(
  reflectInputs: (bytes: Uint8Array) => AssetRecordType,
): AssetParser {
  return async (context) => ({
    types: [reflectInputs(context.bytes)],
    values: {
      shader: {
        type: { reference: "Shader" },
        value: await context.reference(undefined, "text/wgsl"),
      },
    },
  });
}
```

If the parser describes `Inputs { scale: F32 }`, application code can use the
type without embedding shader source or fabricating a runtime input value:

```blot
import { Inputs, Shader, shader } from "./triangle.wgsl"
const scale = fn (inputs: Inputs) => inputs.scale
entry const upload = fn (send: U32 -> U32 ! {Foreign}) => case shader of
  #Shader id => send id
entry const example_scale = fn () => scale (#Inputs { scale: 1.0 })
```

Each successful build returns `assets`, an array of
`{ id, path, mediaType, sha256, bytes }`. Match the received U32 to this build's
manifest and upload those `bytes` to the host API. `path` records the origin;
reopening it could load a different revision. Keep a manifest with its guest
instance. IDs are deterministic for a complete build, but can change when the
set of resources changes. Different nominal reference types distinguish APIs;
the host still validates IDs against its manifest.

This repository supplies the typed adapter interface and tests the shader
boundary. It does not include a shader-language parser or infer shader inputs
using regular expressions.

## Retained builds, ownership and limits

All configured assets are prepared before native compilation. Keep the compiler
open: unchanged tracked inputs reuse their parser results, and unchanged
generated modules reuse the native compiler's retained work. `assetStats`
reports parsed/reused module counts and input/generated byte counts. Reading and
comparing inputs remains part of every build; initial cache population is not
hidden.

Parsers must be deterministic and read dependencies through the context. A
caught missing `read` also becomes a dependency. Include additions, deletions,
contents, and symlink destinations are checked. Parser closures/configuration
are fixed for one compiler instance; create a new instance when parser code or
options change. Native dependency bundles hold the generated language modules,
while parser results currently live only in the host session.

`assetDependencies` lists tracked paths and SHA-256 digests, with `null` for
absent inputs. A host watcher should also observe parent directories to detect
the appearance of optional files. Host references retain immutable content
snapshots; caller-owned buffers, parser-returned descriptions, and published
manifest buffers cannot mutate cached data.

Unsaved input bytes can be supplied using
`build({ assetSources: { path: bytes } })`. Strings are UTF-8 encoded and `null`
hides a file for that build. This is separate from the existing Blot `sources`
overlays. Both maps are complete per-build overrides; omitting a key reads disk
again. Asset paths resolve relative to the entry; Blot source overlays retain
the client's current-directory convention.

Failed parsing or native compilation publishes no candidate manifest and retains
the previous successful revision. The default budgets are 16 MiB per input or
generated module, 64 MiB total input/generated source, 4,096 input
files/modules, and bounded descriptor nesting/work. Source expansion also
consumes ordinary native compiler limits. Aborting a request or disposing the
compiler rejects waiting builds promptly. Parsers receive a signal that also
aborts on disposal. Stopping the parser's own work is cooperative; it must
observe that signal. A parser result arriving after cancellation cannot publish
a native revision or asset manifest.
