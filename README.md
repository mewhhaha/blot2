# Blot 2

Blot is a functional language with type and effect inference, source-defined
operators, algebraic data, closures, providers, request handlers, and bounded
compile-time evaluation. The handwritten Zig compiler emits WebAssembly.

Zig is the only Blot compiler. The TypeScript files in `compiler/` provide the
CLI, native-process client, editor integration and Wasm guest host. Its Baba
parser supports formatting and source generation; it does not type-check Blot or
compile it to Wasm. There is no TypeScript compiler or fallback backend to
select. See [the host tools](compiler/README.md).

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

The [CT110 qualification](zig-native/CT110_QUALIFICATION.md) shares immutable
effect lists and their argument proofs, reduces temporary graph allocations, and
memoizes successful structural job imports. Seven alternating release pairs
against CT109 pass exact outputs and fresh CPU guards: fresh CPU falls **2.9%**,
literal-edit CPU **4.4%**, and body-edit CPU **3.0%**. Shared-host wall medians
are **7.34 s** fresh, **3.03 s** for a literal edit and **5.03 s** for a body
edit. Two-second and sub-second ordinary edits remain open.

The [compiler architecture review](COMPILER_ARCHITECTURE_REVIEW.md) traces the
remaining work through checking, evaluation, specialization and emission. It
recommends stable semantic interfaces and reusable elaborated bodies, and
examines language changes for faster development compilation. These are
architectural proposals, separate from the qualified CT110 implementation. The
[CT111 work record](COMPILER_CT111_WORK.md) records bounded inferred interfaces,
retained source graphs, module-aware fragment lookup and inference-stage
measurements. Its frozen candidate passes 2,584 exhaustive native laws, 1,659
release guests, 48 smoke tests and 57 tooling checks. The five-part program and
sub-second target remain open. The
[final screen](zig-native/CT111_QUALIFICATION.md) shows no speedup, so CT110
remains installed. Optional written conversion requirements
(`where { result "from" a b }`) are described in the
[language guide](compiler/guide.md#qualified-bindings).

The [CT112 follow-up](zig-native/CT112_QUALIFICATION.md) preserves completed
closure and capture proofs across validated replay, without syntax changes. Its
three-pair screen measures 2.86 s literal edits and 4.75 s body edits, but the
work reduction is small and fresh CPU rises; a repeatable speedup is not
established. The frozen candidate passes 2,586 exhaustive native laws, 1,660
release guests, 48 smoke tests, 57 tooling checks and the selected zero-lint
development check. CT110 remains installed and the broader architecture program
remains open.

The [qualified CT113 follow-up](zig-native/CT113_QUALIFICATION.md) adds a
bounded request census and raises the refinement cache to 8,192 records. Three
release pairs measure fresh gdev compilation at 7.55 → 7.08 s (paired CPU
-5.2%); literal/body edits remain about 3.0/5.2 s. It retains about 4.82 MiB
more cache storage and passes 2,587 exhaustive native laws, 1,660 release
guests, 48 smoke and 57 tooling checks, plus the selected zero-lint development
check. Missing call-proof provenance remains an architectural bottleneck;
unsuccessful recheck trials were removed. CT110 remains installed.

The [CT114 frontend changes](zig-native/CT114_QUALIFICATION.md) compact
generic-requirement storage and omit unused sharing analysis. The profiled fresh
frontend median is 1.872 → 1.784 s; checking is 1.421 → 1.344 s. Checker
allocation requests fall 27.0% and requested bytes 17.6%. Unprofiled whole-build
measurements do not establish a latency improvement. The exact frozen candidate
passes full correctness qualification. These instrumented timings are separate
from whole-build latency; the fresh frontend is still above one second. The
[architecture review](COMPILER_FRONTEND_REVIEW.md) prioritizes immutable import
interfaces and requirement dependency tracking. CT110 remains installed.

The [CT115 SIMD and parallelism review](COMPILER_BIG_LEVERS.md) finds a larger
algorithmic target: one application module consumes 34.5% of checker CPU and
91.5% of selected generic-requirement candidates. A four-worker scheduling model
leaves the fresh frontend around 1.24 s; further gains require less work on the
dependency chain. These are diagnostic measurements and proposals, with no new
parallel implementation or installation.

The [CT116 frontend changes](zig-native/CT116_QUALIFICATION.md) cache
requirement dependencies, reuse imported sharing analysis, index larger
inference sets and check independent modules with four workers by default. Fresh
profiled frontend time falls from 1.600 to 1.036 s; checking from 1.214 to 0.649
s. These clocks include profiling overhead. Canonical interface graph copies
remain; this does not establish sub-second ordinary edit builds. The frozen
candidate passes 2,596 exhaustive native laws and release guest qualification.
Concurrent owned-array work is preserved and excluded; CT110 remains installed.
The public Blot/Rust compile-time and runtime table appears below.

All eight previously “Remaining” proposals have implementations or measured
trials. The [86-item ledger](COMPILER_CT109_LEDGER.md) distinguishes those from
partial and conditional architectures. The
[CT110 work record](COMPILER_CT110_WORK.md) preserves two more rejected cache
experiments. Literal operation-list visits fall 86%, but inference-region counts
and the three expensive body-principal misses remain unchanged. Peak RSS is
effectively flat; a work-count reduction does not imply the same percentage
improvement in latency or memory.

The installed CT110 gate passes 2,576 exhaustive native laws, 1,656 guests, 48
smoke tests and 57 tooling tests, with zero Zig lint findings. A guest-fixture
cleanup race is fixed by joining detached cache writers before removing their
directory. The selected Safe/noLLVM development cycle passes in **25.54 s** with
99 native laws and 56 guests; this is one observation, not a paired build
speedup.

The earlier [CT109 qualification](zig-native/CT109_QUALIFICATION.md) records its
bounded optimizer/RC/encoded-body reuse and 200-distinct-edit memory series.
[CT106](zig-native/CT106_QUALIFICATION.md) records its separate 19.1%
first-literal CPU gain and 20-cycle development distribution (25.35 s median,
27.64 s observed p95). Those historical comparisons retain their own baselines
and source pins.

Use `deno task check:dev --area static-sharing` for Safe/noLLVM development and
`deno task test:compiler` for complete qualification. Compiler identity now
recomputes build configuration after a stale-digest bug was reproduced; normal
compiled-artifact caches remain reusable. The historical LLVM release trace
spends 220.88 of 227.76 seconds in emission. The
[experiment tools](scripts/bench/README.md),
[compile measurements](COMPILE_MEASUREMENTS.md),
[compile hills](COMPILE_HILLS.md), [build hills](BUILD_HILLS.md) and
[turnaround measurements](DEVELOPMENT_TURNAROUND.md) keep construction,
verification and application performance separate.

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

## Idiomatic Blot and Rust benchmarks

Eighteen public program pairs, measured on 25 October 2026 with an AMD Ryzen 7
7800X3D (Linux, 16 logical CPUs). Both languages target WebAssembly and run in
the same Deno 2.9.7 / V8 15.0.245.2-rusty engine. Blot uses the frozen CT116
LLVM release compiler built with Zig 0.17.0; Rust uses
`rustc 1.96.0-nightly (3645249d7)`, `wasm32-unknown-unknown`, optimization level
3 and aborting panics. This measures small programs, not whole application
builds.

Blot compiles these programs in roughly **6–10 ms**, versus Rust's **42–83 ms**.
Rust has the lower median runtime in all eighteen cases; GCD is close, while
text formatting and persistent-list pipelines show much larger gaps.

Compile columns are **milliseconds**, medians of five fresh compiler processes
with warm filesystem caches, including code generation and linking. Runtime
columns are **microseconds per call**, medians of 31 warmed batches; each call
includes generated input, computation and allocation/release. Every workload
passes seven independent output witnesses. Lower is better in every column.

| Program            | Blot compile ms | Rust compile ms | Blot Wasm µs | Rust Wasm µs |
| ------------------ | --------------: | --------------: | -----------: | -----------: |
| fibonacci          |             6.5 |            45.4 |        15.86 |         7.50 |
| gcd                |             6.6 |            41.9 |       175.35 |       172.82 |
| prime sieve        |             8.9 |            61.4 |        47.11 |        20.40 |
| integer recurrence |             6.3 |            42.8 |        67.12 |        32.54 |
| array map reduce   |             8.7 |            59.6 |        50.20 |         5.77 |
| array filter       |             9.6 |            62.0 |       456.28 |         8.57 |
| prefix scan        |             9.2 |            62.6 |       102.37 |         4.88 |
| histogram          |             8.8 |            50.1 |        21.67 |        12.36 |
| dot product        |             9.1 |            72.0 |        19.05 |         9.09 |
| matrix multiply    |             9.2 |            79.4 |        26.92 |         5.07 |
| binary search      |             8.7 |            64.6 |       138.63 |        44.13 |
| list pipeline      |             9.5 |            62.2 |       430.80 |         3.23 |
| option pipeline    |             6.8 |            43.9 |       310.06 |        11.89 |
| decimal format     |             9.4 |            63.8 |      2498.19 |        18.02 |
| csv numbers        |             9.6 |            83.1 |      1661.76 |        18.41 |
| tree reduce        |             6.8 |            47.7 |       116.23 |        37.49 |
| expression eval    |             7.2 |            50.4 |        58.44 |        19.27 |
| run length         |             9.4 |            69.5 |       382.90 |        14.79 |

Rust links its precompiled standard library; Blot checks imported library
source. Rust iterators can fuse pipelines, while Blot collection functions may
construct intermediates. Persistent Lists, strings and tree ownership also
differ. These are idiomatic implementations of the same computations, not
identical low-level algorithms. Runtime includes required Blot ownership hooks
and Rust allocation/ drop code; module instantiation and host argument
validation are excluded. Native Rust is not measured. Shared-host timing and
this fixed workload set limit generalization.

See [sources, sizes and methodology](benchmarks/idiomatic/README.md),
[all raw samples and hashes](benchmarks/results/ct116-2026-10-25.json), and the
[compiler qualification](zig-native/CT116_QUALIFICATION.md). Reproduce with
`deno task bench:idiomatic --rounds 5 --samples 31 --out build/bench/my-run`.

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

`frontendWorkers` selects 1–16 independent module checker workers (default 4).
Small projects and retained edit checking keep their existing paths. The native
CLI accepts `--frontend-workers`; evaluator and codegen workers are separate.

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
