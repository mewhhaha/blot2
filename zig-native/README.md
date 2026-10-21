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
`zig build install compiler-identity -Doptimize=fast -Dllvm=true` for a final
release. Development always uses Zig's native backend without LLVM: build with
`zig build install compiler-identity -Doptimize=safe -Dllvm=false --prefix zig-out-dev`.
Run development native tests with
`zig build test -Doptimize=safe -Dllvm=false --prefix zig-out-native-dev`;
the runner sets the fixture working directory.
Use `deno task test:compiler:dev` from the root for Safe/noLLVM
development and focused laws. Add `-Dllvm=false --prefix zig-out-native-dev`
to a development `zig build test-compile -Doptimize=safe` to build the native
test binary separately. Native tests import immutable inputs through
the `fixtures` module rooted at `fixtures/root.zig`; production builds have no
fixture-module dependency. All 126 Blot fixtures and both frozen oracle files
live outside `src/`. Their relocation byte manifest and focused discovery checks
are in `build/bench/finish-rest-20261015/fixture-relocation/`. The full gate
still qualifies the final combined source.
For full native qualification, `zig build test -Doptimize=safe -Dllvm=false
--prefix zig-out-native-dev -Doom-profile=true -Dtest-force-run=true --summary all`
reports allocation-failure sweep timings while running the full suite.
Native unit tests always compile with Zig's backend. The installed executable
supports `--test=EXACT_INVENTORY_NAME`, and records individual durations,
leaks, logged errors and allocation-failure mode as `BLOT_NATIVE_TEST` JSON.
`deno task check:dev --area static-sharing` runs a bounded development family
with sampled allocation faults; full execution remains exhaustive by default.
`--list-areas` also lists syntax, type/effect and retained body-checking families.
The full Deno gate compiles once, then directly launches one to four native
shards, verifies every inventory entry and records their actual overlap. Shard
logs and completion records participate in verified resume evidence.

For smaller native builds, use `-Dtest-suite=syntax`, `types` or `runtime` with
`test` or `test-compile`. The default `all` remains the complete production
suite. `deno task test:compiler:dev --native-suite types` selects a
Safe/noLLVM check. Reserve LLVM for the actual final release compiler and release
performance measurements.

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
