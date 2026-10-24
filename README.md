# Blot 2

Blot is a functional language with type and effect inference, source-defined
operators, algebraic data, closures, providers, request handlers, and bounded
compile-time evaluation. The handwritten Zig compiler emits WebAssembly.

`[a]` is a `List a`; `#[a]` is an `Array a`. Both support comprehensions and
append/prepend spreads. Indexing and indexed updates belong to arrays. Lists use
balanced trees of dense leaves, sharing unchanged paths between versions.
Declaration tags use `@[f]`. See the [language guide](compiler/guide.md).

## Build and use

Requires Zig **0.17.0** and Deno 2. The compiler itself has no Deno dependency.

```sh
deno task build:compiler
deno task blot check examples/lists.blot
deno task blot build examples/lists.blot build/lists.wasm
deno task blot guide
deno task test
```

The executable is `zig-native/zig-out/bin/blotc`. Projects can declare Git or
local dependencies in `blot.json`; `deno task bpm install PROJECT` caches their
locked revisions. Packages declare exports in `blot-workspace.yaml`. A manifest
project selects its prelude explicitly; omission means no prelude. See
[bpm](compiler/packages.md).

Without a manifest, the Deno CLI supplies the standard prelude by default; the
raw executable requires `--prelude std/prelude.blot --std-root std`. Always use
`deno task build:compiler:dev` for development. It uses Zig's native backend
without LLVM and writes to `zig-native/zig-out-dev`. Add `--incremental` to
enable Zig's experimental incremental compilation. Final releases and release
measurements use LLVM through `deno task build:compiler`.

To install a release locally on Linux x86-64, build the compiler above, then
bundle the CLI and its matching compiler, parser, guide and standard library:

```sh
deno task package:pack
deno compile --allow-read --allow-write --allow-run \
  --allow-env=HOME,XDG_CACHE_HOME,BPM_CACHE_DIR \
  --include generated/compiler/blotc.gz --include generated/wasm \
  --include std --include compiler/guide.md \
  --output build/install/blot compiler/installed_cli.ts
mkdir -p "$HOME/.local/bin"
install -m 755 build/install/blot "$HOME/.local/bin/blot"
install -m 755 zig-native/zig-out/bin/blotc "$HOME/.local/bin/blotc"
```

Put `$HOME/.local/bin` on `PATH`. `blot` is the self-contained project CLI;
`blotc` is the raw native compiler and takes explicit prelude/library paths.

For a five-minute development cycle, run
`deno task check:dev --area static-sharing`. It compiles the complete native
inventory with Zig, executes the affected regression family with
first/middle/last allocation-failure sampling, runs guest/client smoke and local
static checks. Per-test durations and explicit pending full qualification are
recorded in `build/bench/check-dev`. It fails rather than reporting an
incomplete check as passed. See
[the turnaround plan](DEVELOPMENT_TURNAROUND.md). List focused areas with
`deno task check:dev --list-areas`. Besides `static-sharing`, choose `syntax`,
`type-effects`, `body-checking`, `numeric-aggregates` or `tasks`; each runs
existing positive, rejection/recovery and ownership regressions plus guests.

The [latest performance changes](zig-native/CT105_QUALIFICATION.md) reduce
frozen gdev fresh-build CPU by **13.3%**, body-edit CPU by **12.9%** and
literal-edit CPU by **3.3%** against `5cfb411` in seven alternating release
pairs, with identical Wasm. Shared-host wall medians are 8.33 s fresh, 4.16 s
first literal, 3.10 s literal revert and 5.42 s body edit. The 10% literal-CPU
and sub-second editing targets remain open. Scope indexing, row certificates,
worklist masks, exact frontend indexes and cache fixes remove repeated work;
four body regions and first-edit graph correspondence still need attention. The
report records memory costs, unseen/fresh controls, exhaustive qualification and
the disposition of all 50 observations in the preceding
[CPU/memory audit](PERFORMANCE_REVIEW.md#current-cpu-memory-and-algorithm-audit--24-october-2026).

The matching release CLI and native compiler are installed locally. The expanded
Safe/noLLVM development cycle takes 21.28 s, including a 3.31 s compiler build
and 5.91 s complete native compilation. These are individual observations, not
p95 estimates or paired compiler-build gains. Keep stable writable Zig caches;
the measured incremental mode did not improve real edits. Use
`deno task bench:compiler-build --out build/bench/build-next` for isolated
build/edit/revert measurements. The
[compile measurements](COMPILE_MEASUREMENTS.md),
[compile hills](COMPILE_HILLS.md), [build hills](BUILD_HILLS.md) and
[performance review](PERFORMANCE_REVIEW.md) separate completed work from the
remaining targets.

For a smaller development check, run `deno task test:compiler:dev`. It checks
the project protocol, client and inference-budget recovery against the
Safe/noLLVM compiler. Select guest files and native laws when working on a
particular area:

```sh
deno task test:compiler:dev --native-filter "test name" zig-native/tests/list_runtime.test.ts
deno task test:compiler:dev --native-suite syntax
deno task test:compiler:dev --native-suite types
deno task test:compiler
deno task test:compiler --oom-profile
```

The full gate runs the quick contract checks first, then the release build,
native compilation, native execution and guest tests. Guest files use four
workers; `--jobs 1` through `--jobs 4` selects bounded parallelism. Timings and
logs are written to `build/bench/iteration`; `--timings-dir PATH` keeps a
separate record. Cached native results are reported explicitly. `--oom-profile`
executes every native law and records the ten slowest allocation-failure sweeps;
`--force-native` reruns native laws without profiling. The full gate is required
before compiler commits. Native execution launches the installed test binary
directly in `--native-shards 1` through `--native-shards 4` isolated processes
(default two). The gate verifies exact inventory coverage and records actual
overlap and per-shard logs under `build/bench/iteration/native-execution`.
Failures cancel sibling processes; resume requires unchanged raw evidence as
well as inputs.

All native unit-test compilation uses Safe/noLLVM, including the full gate. The
full gate retains exhaustive allocation-failure sweeps. Select `syntax`, `types`
or `runtime` with `--native-suite` to compile only that subsystem; `all` keeps
every native law. `deno task test:native` also uses the Zig backend and installs
its test executable separately in `zig-native/zig-out-native-dev`. Reserve LLVM
for the actual release compiler and release measurements. The installed native
executable accepts `--test=EXACT_INVENTORY_NAME` and emits a `BLOT_NATIVE_TEST`
JSON timing/result line for each executed law.

The project API accepts `inferenceBudget` (default 1,000,000) for ordinary
inference and associated work through checking and evaluation. See
[budget behavior](zig-native/PROJECT_CLIENT.md) for accounting and diagnostics.
The [associated-work qualification](zig-native/ASSOCIATED_WORK_QUALIFICATION.md)
records the gdev repair and fresh release compile times. Inference-budget
rejection and recovery use a small-budget executable fixture.
`deno task test:compiler:stress` separately checks the production million-step
limit against an adversarial stage chain.

## Structured tasks

Spark `*(function argument)` starts an invocation in the checked enclosing task
scope. Receive its result with `|receiver|`; `|(left, right)|` collects task
results together in written order. Stored tuples work through the same receive
helper, while one task returning a tuple keeps that payload intact.

```blot
const scope = fn body => @task.scope body
const spawn = fn group => fn action => @task.spawn group action
const await = fn receivers => |receivers|

entry const answer = fn () => scope (fn group => do:
  let here = spawn group
  let left = here (fn () => 20)
  let right = here (fn () => 22)
  let (first, second) = await (left, right)
  break @u32.add first second)
```

These are ordinary user-defined helpers. Their checked contracts survive aliases
and imports; spawn partial calls retain their selected group. Scope exit drains
children and cleanup, and task handles cannot escape their region. Execution is
cooperative within one guest, with synchronous and JSPI support. Caller-region
inference in arbitrary helpers, general higher-order spawn forwarding, stream
channels, select-one, scoped nonlocal exits and CPU workers remain unfinished.
See the [language guide](compiler/guide.md#structured-tasks) and
[task contracts](zig-native/STRUCTURED_CONCURRENCY.md). The
[qualification record](zig-native/TASK_SURFACE_QUALIFICATION.md) lists the
tested boundaries and remaining work.

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

The native compiler caches validated restart candidates in the platform cache
directory. `BLOT_CACHE_DIR` selects another directory; an empty value disables
it. The project API also accepts `cacheDirectory` (a path or `false`). Its
default uses cache-location environment variables only when the host already has
permission to read them. `close()` saves the latest successful revision;
`dispose()` stops immediately. Source validation always runs.

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

## Helix

`deno task helix:install` installs the Tree-sitter grammar, highlighting and the
completion server. In insert mode, Ctrl-x requests suggestions from the current
buffers; accepting one replaces only the typed token. The server uses Deno and
the native compiler, with a 250 ms request deadline. It supplies completion;
formatting remains a separate task. `DESIGN.md` records proposals, while the
language guide and executable tests define supported behavior.
