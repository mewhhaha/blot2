# Zig compiler

This is Blot's production compiler, written directly in Zig 0.17.0. It owns
lexing, parsing, type/effect inference, staging, incremental revisions and Wasm
emission. There is no Bend runtime or compiler dependency.

From the repository root:

```sh
deno task build:compiler
deno task test:compiler
```

Without Deno, build in this directory with
`zig build install compiler-identity -Doptimize=fast`. Run native tests with
`zig build test -Doptimize=safe`; the runner sets the fixture working directory.
Use `deno task test:compiler:dev` from the root for incremental Safe/noLLVM
development and focused laws. `zig build test-compile -Doptimize=safe` builds
the native test binary separately.
`zig build test -Doptimize=safe
-Doom-profile=true -Dtest-force-run=true --summary all`
reports allocation-failure sweep timings while running the full suite.

For smaller native builds, use `-Dtest-suite=syntax`, `types` or `runtime` with
`test` or `test-compile`. The default `all` remains the complete production
suite. `deno task test:compiler:dev --native-suite types` selects an incremental
Safe/noLLVM check; add `--native-llvm` for faster execution of long fault
sweeps.

`blotc build ENTRY OUTPUT.wasm --prelude std/prelude.blot --std-root std`
compiles a project. `dependencies ENTRY OUTPUT.blotdep` produces reusable typed
dependencies. `serve-project` serves the framed retained-project protocol used
by [the client](PROJECT_CLIENT.md).

The language distinguishes chunked `List a` from contiguous `Array a`. Indexing
and indexed rebinding are array-only. Shared list edits copy the chain; proven
exclusive end edits reuse storage. See the
[collection guide](../compiler/guide.md#lists-arrays-and-libraries).

[Architecture](ARCHITECTURE.md), [ownership contract](CONTRACT.md),
[validation and performance](STATUS.md).
