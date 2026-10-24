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
`zig build test -Doptimize=safe -Dllvm=false --prefix zig-out-native-dev`; the
runner sets the fixture working directory. Use `deno task test:compiler:dev`
from the root for Safe/noLLVM development and focused laws. Add
`-Dllvm=false --prefix zig-out-native-dev` to a development
`zig build test-compile -Doptimize=safe` to build the native test binary
separately. Native tests import immutable inputs through the `fixtures` module
rooted at `fixtures/root.zig`; production builds have no fixture-module
dependency. All 126 Blot fixtures and both frozen oracle files live outside
`src/`. Their relocation byte manifest and focused discovery checks are in
`build/bench/finish-rest-20261015/fixture-relocation/`. The full gate still
qualifies the final combined source. For full native qualification,
`zig build test -Doptimize=safe -Dllvm=false
--prefix zig-out-native-dev -Doom-profile=true -Dtest-force-run=true --summary all`
reports allocation-failure sweep timings while running the full suite. Native
unit tests always compile with Zig's backend. The installed executable supports
`--test=EXACT_INVENTORY_NAME`, and records individual durations, leaks, logged
errors and allocation-failure mode as `BLOT_NATIVE_TEST` JSON.
`deno task check:dev --area static-sharing` runs a bounded development family
with sampled allocation faults; full execution remains exhaustive by default.
`--list-areas` also lists syntax, type/effect, retained body-checking,
numeric-aggregate and structured-task families. Use `--area tasks` while
changing task-region, receive and ownership contracts. The full Deno gate
compiles once, then directly launches one to four native shards, verifies every
inventory entry and records their actual overlap. Shard logs and completion
records participate in verified resume evidence.

For smaller native builds, use `-Dtest-suite=syntax`, `types` or `runtime` with
`test` or `test-compile`. The default `all` remains the complete production
suite. `deno task test:compiler:dev --native-suite types` selects a Safe/noLLVM
check. Reserve LLVM for the actual final release compiler and release
performance measurements.

Use `deno task bench:compiler-build --out build/bench/build-next` from the
repository root to measure isolated cache initialization, compiler/native builds,
source edits and reverts. The [initial build measurements](../COMPILE_MEASUREMENTS.md)
record roughly 3.4 s real compiler edits and a 4.64 s warm development cycle;
the expanded development family below is measured separately.
Keep ordinary writable Zig caches; explicit incremental mode did not improve
the measured edit cycle. [Build hills](../BUILD_HILLS.md) track the remaining
iteration and qualification costs separately from
[application compile hills](../COMPILE_HILLS.md).

[Principal dependency reuse and row normalization](CT103_QUALIFICATION.md)
reduce literal-edit CPU by 24.8%, body-edit CPU by 4.2% and fresh-game CPU by
6.1% against `5412320` in seven alternating pairs, with identical Wasm. The
literal edit reuses all 20 principal results; body edits still rebuild four
regions. Shared-host literal/body wall medians are 7.60 / 12.46 s, with no body
wall improvement. Sub-second editing remains open. The percentages belong to the
pinned measured candidate. The final release also fixes portable restart replay,
includes `faf3f78` and separately passes 2,551 exhaustive native laws and 1,654
guest checks. The measured development cycle takes 26.05 s; its 3.59 s compiler
build and 6.90 s native compilation are individual observations. The
[review](../PERFORMANCE_REVIEW.md) separates first-edit frontend work from
steady inference and records the remaining dependencies to investigate.

`blotc build ENTRY OUTPUT.wasm --prelude std/prelude.blot --std-root std`
compiles a project. `dependencies ENTRY OUTPUT.blotdep` produces reusable typed
dependencies. `serve-project` serves the framed retained-project protocol used
by [the client](PROJECT_CLIENT.md).
The client `inferenceBudget` setting and native `--inference-budget` option
control ordinary inference and associated work through checking and evaluation.
See [budget accounting](PROJECT_CLIENT.md) and the
[associated-work qualification](ASSOCIATED_WORK_QUALIFICATION.md).

The language distinguishes chunked `List a` from contiguous `Array a`. Indexing
and indexed rebinding are array-only. Shared list edits copy the chain; proven
exclusive end edits reuse storage. See the
[collection guide](../compiler/guide.md#lists-arrays-and-libraries).

Structured tasks support checked ordinary scope wrappers, exact explicit spawn
wrappers through aliases/imports/partial calls, and generic task receives over
one handle or a tuple of up to sixteen handles. Frozen Core validates capture
transfer at the actual spawn call. Collection retains partial results until all
selected tasks succeed or cleanup completes. See
[structured concurrency](STRUCTURED_CONCURRENCY.md) for the implemented
contracts and remaining language/runtime work. The repository
[installation instructions](../README.md#build-and-use) install both the raw
compiler and a CLI containing its matching release binary.

[Architecture](ARCHITECTURE.md), [ownership contract](CONTRACT.md),
[validation and performance](STATUS.md).
