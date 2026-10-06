# Blot 2

Blot is a functional language with type and effect inference, source-defined
operators, algebraic data, closures, providers, request handlers, and bounded
compile-time evaluation. The handwritten Zig compiler emits WebAssembly.

`[a]` is a `List a`; `#[a]` is an `Array a`. Both support comprehensions and
append/prepend spreads. Indexing and indexed updates belong to arrays. Lists use
balanced trees of dense leaves, sharing unchanged paths between versions. Declaration tags
use `@[f]`. See the [language guide](compiler/guide.md).

## Build and use

Requires Zig **0.17.0** and Deno 2. The compiler itself has no Deno dependency.

```sh
deno task build:compiler
deno task blot check examples/lists.blot
deno task blot build examples/lists.blot build/lists.wasm
deno task blot guide
deno task test
```

The executable is `zig-native/zig-out/bin/blotc`. The Deno CLI supplies the
standard prelude by default; the raw executable requires
`--prelude std/prelude.blot --std-root std`. `deno task build:compiler:dev`
enables Zig's incremental compiler build in `zig-native/zig-out-dev` for
development. Release measurements use `deno task build:compiler`.

## Project API

Keep a compiler open across edits to reuse unchanged syntax, typed modules,
evidence and generated function bodies:

```ts
import { createCompiler, instantiateGuest } from "@mewhhaha/blot";

const compiler = await createCompiler({ entry: "/project/main.blot" });
try {
  const result = await compiler.build();
  if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
  const guest = await instantiateGuest(result.bytes);
  try {
    console.log(guest.call("answer", null));
  } finally {
    guest.dispose();
  }
  // compiler.build({ sources: { "/project/main.blot": editorText } })
  // accepts unsaved files without writing them to disk.
} finally {
  await compiler.dispose();
}
```

The package bundles a Linux x86-64 executable. Set `executable` to use your own
build on other supported platforms or in a checkout. `prelude: null` disables
the default prelude. See [project API details](zig-native/PROJECT_CLIENT.md).
The low-level `createZigProjectCompiler` API requires explicit executable and
prelude paths. Compilation is asynchronous; source analysis objects and the old
synchronous compiler API are retired.

Unchanged dependencies can be compiled separately:

```sh
deno task blot dependencies /project/main.blot build/project.blotdep
deno task blot build /project/main.blot build/main.wasm --dependencies build/project.blotdep
```

Bundles carry compiler and semantic identities; regenerate them after compiler
or dependency changes. See [compiler architecture](zig-native/ARCHITECTURE.md),
[current validation](zig-native/STATUS.md), and
[guest ABI](compiler/guest-abi.md). The targets are about **500 ms cold** and
**under 100 ms incremental** for gdev.

## Development

`deno task check` checks formatting, types, native laws, Wasm execution and
client behavior. `deno task package:check` builds and validates the
distributable package without publishing it. Behavioral fixtures and frozen
reference results remain in `zig-native/src` and `zig-native/tests`.

The Bend implementation, generated compiler, protocol adapters, experimental
backends and old compiler-coupled ECS prototype have been removed. The previous
working tree, including uncommitted changes, is preserved locally under
`build/zig-only-migration/`; committed history remains in Git.

## Helix highlighting

`deno task helix:install` generates and installs the Tree-sitter grammar and
highlighting. The formatter uses the Baba grammar; compilation uses the native
Zig frontend. `DESIGN.md` records language proposals, while the language guide
and executable tests define supported behavior.
