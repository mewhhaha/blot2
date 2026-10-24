# Zig project API

The optional `assets` registry adds dependency-tracked host parser functions.
See [typed external assets](../compiler/assets.md) for the descriptor contract,
JSON parser, shader adapter, input overlays, manifests and ownership rules.

The package root exports `createCompiler({ entry, executable? })`. It starts the
packaged Zig compiler by default and supplies the standard prelude. For an
explicit executable and no implicit prelude, use `createZigProjectCompiler` from
`@mewhhaha/blot/zig-project`.

```ts
import { createCompiler } from "@mewhhaha/blot";

const compiler = await createCompiler({
  entry: "/project/main.blot",
  imports: { "lib/": "/project/library" },
});
try {
  const result = await compiler.build({
    sources: { "/project/main.blot": "entry const answer = fn () => 42\n" },
  });
  if (result.success) await Deno.writeFile("program.wasm", result.bytes);
  else console.error(result.diagnostics);
} finally {
  await compiler.dispose();
}
```

Every `sources` map is a complete override snapshot for that build. Omitted
paths read disk; `null` hides a file. New virtual files and unsaved imported
modules are supported. Inputs are copied before queueing; the compiler never
writes source files. Limits are 16 MiB per source, 4,096 overrides and a 64 MiB
request frame. Paths identify modules consistently across disk and buffered
builds.

`prelude: null` disables the prelude. `stdRoot` sets the `std/` alias; `imports`
supplies other directory aliases. `dependencies` accepts a compatible `.blotdep`
file created by `blot dependencies`. A mismatched bundle is rejected.
`expectedCompilerIdentity` can pin a 64-character lowercase compiler
fingerprint.

`inferenceBudget` sets the inference work allowance (default 1,000,000 steps).
The native CLI accepts the same setting as `--inference-budget`. Each module's
ordinary inference has that allowance; associated-type checking shares an
allowance across the project, and evaluator sessions start their associated
work allowance from the same setting. Larger configured values apply throughout
these stages, without an additional one-million-step cap. Budget changes alter
the compiler identity, so retained and persistent candidates cannot cross them.
An `associated_limit` diagnostic from module checking reports the actual
associated work allowance available to that module, which can be smaller after
checking its dependencies. Ordinary effect rows in a solver with no associated
projections do not consume associated normalization work merely because an
implementation is in scope.

`codegenTier: "development"` skips optional scalar replacement and automatic
vectorization. Type/effect checking, constant evaluation, explicit cleanup and
lifetime analysis still run. The default is `"optimized"`. A project session
keeps its selected tier; start a separate session to compare outputs. Optimized
body captures are valid only for the tier that produced them. This option does
not change the optimization mode used to build the native compiler itself.

An edit loop such as `pen dev` opens its session with `"development"`; every
release build (`pen build`, test runs, `bench:compile` hashes) opens with the
default, whose output the development tier never changes
(`tests/development_tier.test.ts`). pen's Blot plugin forwards its program
setting `codegenTier` on `open`, but that setting applies to every build of the
program, so `pen dev` must select the tier for its own session rather than
through `pen.json`. On gdev the tier halves assembly (197 → 99 ms); inference
and constant evaluation, which dominate an edit, are the same in both tiers.
Game, 5 pairs: population 2,367 → 2,268 ms, a literal edit 1,087 → 996 ms, a
body change 1,621 → 1,565 ms, an `ink/math` body edit 2,333 → 2,229 ms.

A test runner keeps one session per worker on one fixture entry and overlays
each test module at it. A session keeps a library of the dependency modules
its revisions froze. When a build's entry reaches other modules than the last
seed holds, the library supplies every module whose source and imports are
unchanged, renumbered as a fresh load numbers it; only modules no earlier
build froze, changed ones and the entry are checked
(`attemptStats.fallback.relocated_modules` counts the reused modules). Each
build's Wasm and diagnostics equal a fresh session's, and a rejected build
leaves the library as it was. Generated code is not shared between entries:
each test still pays its own backend.

`pen test-blot` adopts this without a protocol change. Its workers already
keep one session for the fixture entry (`run_module` in
`crates/pen/src/blot_test.rs`) and overlay each module at
`src/test_fixture.blot`. pen must keep doing exactly that: open each worker's
session on the fixture entry once, overlay only that path for every test
module, and keep the session after rejected builds rather than reopening it per
module. Each worker's first build pays for every module it reaches; later
builds pay for the test module and any module no earlier build of that worker
reached. On the gdev snapshot one session over pen's 68 test modules takes
72.9 s of CPU instead of 96.1 s (91.0 → 67.5 s wall, peak RSS 717 → 742 MiB);
`deno task bench:compile --workload tests --shared-session` measures it.

`shareMachineCode: true` enables the internal body-sharing prototype. Identical
resolved functions share one Wasm body while their source/evidence identities
and indirect table slots remain distinct. Exported functions keep distinct
identities. The default is `false`. On the frozen gdev workload this removes 272
duplicate bodies and reduces Wasm size by 7.8%; no total compile-time
improvement has been established. The `runtimeOptimization.shared` counter
counts removed duplicate bodies. Artifact statistics describe the logical
functions retained for replay.

`codegenWorkers` requests 1–16 concurrent optimizer workers (default 4). Jobs
read immutable function bodies and completed lifetime summaries, optimize them
and plan their reference counts; each worker owns its scratch arena. Small
builds and edits with fewer than four uncached bodies or 4,096 instructions
stay serial. `runtimeOptimization.workers` and `parallel_jobs` report the actual
work scheduled. Output and rejections are byte-identical to serial assembly.
This parallelizes runtime optimization, not semantic checking or evaluation. On
the gdev game, four workers cut assembly from 201 to 91 ms and build wall time
by 3.9% (a literal edit by 9.2%) with CPU within 1.3% (CT89).

The direct native client accepts `semanticWorkers: 1..16` to opt into private
semantic component jobs. Explicit `1` runs the same component path with one
worker; omission keeps the existing serial inference path. Workers own their
solver, scratch and evidence import state, join before publication, and preserve
deterministic diagnostics and Wasm. `stats.workCounters.semantic_component_jobs`
counts scheduled components. Small or unsupported jobs can stay serial. The
native CLI exposes this setting as `--semantic-workers 1..16` on `build`,
`build-project` and `serve-project`. See [SEMANTIC_JOBS.md](SEMANTIC_JOBS.md)
for ownership and failure handling, and
[SEMANTIC_WORKERS.md](SEMANTIC_WORKERS.md) for measured policy costs. The serial
default remains unchanged. `max_semantic_component_workers` reports admitted
batch capacity including the coordinator, rather than simultaneous execution.
Optional profiling reports exclusive coordination, dispatch and publication wall
clocks; the private job-time sum overlaps dispatch and must not be added to it.

`stats.principals` distinguishes projected-query rejection causes with
`projected_owner_declines`, `projected_result_declines`,
`projected_unrecorded_declines`, `projected_input_declines`,
`projected_image_declines` and `projected_import_declines`. Their sum is
`projected_empty_declines`. `call_publications_declined` instead counts optional
call memo outputs that could not be translated under the existing proof checks.
Those calls are checked normally when needed; an independently admitted
principal result can still be reused. `projected_nonempty_hits` counts imported
type/row results, and `projected_source_hits` counts projected reuse admitted by
complete observed declarations when the whole source image differs.
`call_publications_replayed` counts translated call proofs;
`summary_publications_replayed` and `summary_publications_declined` report
completed-summary outputs separately. Summary memo judgments do not become
global validated-call proofs. The legacy `projected_empty_declines` name remains
the total for all projected-query declines, including nonempty results.

`stats.principals.source_declines` reports up to eight first failed source
observations, with target/source unit and binding IDs and an exact decline reason.
Unused slots have reason `none`; module-image observations use source binding
zero. These diagnostics do not decide admission. Frontend cutoff statistics also
report the first mismatching unit, changed interface-field bit mask, binding
counts, remaining correspondence budget and comparison progress.

`stats.workCounters.normalization` counts region-solver row requests, closed and
epoch cache hits, argument rows/labels/arguments inspected, changed rows, fallback
certificate evictions and operation-interner requests/candidates/argument tests.
These are work counts, not elapsed time or cache hardware events; frontend type
stores are excluded. `lexical_region_candidates` records the candidate volume of
the former whole-region variable scan, while `lexical_scope_candidates` counts
visits through the source-scope index. Their difference is avoided scan work,
not a measured speedup percentage.

The CLI and native project server automatically persist restart candidates under
`$XDG_CACHE_HOME/blot` or `$HOME/.cache/blot` on Linux,
`$HOME/Library/Caches/blot` on macOS, and `%LOCALAPPDATA%/Blot` on Windows.
`BLOT_CACHE_DIR` overrides the complete root; an empty value disables it. The
client accepts `cacheDirectory: "/path"` or `cacheDirectory: false`. By default
it forwards only the cache-location environment variables it already has
permission to read. It never requests additional environment access or inherits
unrelated variables. With no available cache location, builds work normally
without persistence.

Files are keyed by compiler identity and entry, written atomically, and admitted
through the same source and semantic checks as explicit checkpoints. Storage
failures are ignored. A server replies to its first successful revision before
the cache is written, but on Linux a detached writer process already holds the
key's lock, so an immediate `dispose()` still leaves restart candidates: the
next compiler's open waits (at most 10 s) for that write and then loads it. A
killed writer leaves the previous file, if any. Other platforms write before
replying. Later edits avoid cache writes; `close()` saves the latest committed
revision the same way. Failed edits never replace the last successful
checkpoint. The cache also holds the saved revision's Wasm and every input it
read: a restarted compiler whose first build has exactly those inputs and the
same settings returns that Wasm without compiling (`attemptStats.restored_output`).
A restarted compiler whose sources changed starts from the saved dependency
frontend instead, so unchanged dependencies are not checked again. Keep the compiler alive for
editing; restart caching and retained edits are measured separately by
`deno task bench:compile --restart-cache`.

`exportCheckpoint()` also returns portable backend cache bytes from the last
successful revision. It queues after earlier builds without advancing the
revision. Pass those bytes as `checkpoint` when opening another compiler:

```ts
const checkpoint = await compiler.exportCheckpoint();
await Deno.writeFile("build/project.blotcache", checkpoint);
const restarted = await createCompiler({
  entry: "/project/main.blot",
  checkpoint: await Deno.readFile("build/project.blotcache"),
});
```

Explicit bytes take precedence over automatic loading and are copied at startup.
A checkpoint contains admitted principal-query proofs and optimized function
bodies, not evaluated source values or arbitrary specializations. Compiler
identity, complete source/catalog and symbol identities, observed semantic
inputs, compilation tier and optimizer dependencies govern reuse. Changed or
unsupported inputs compile afresh. Stale or corrupt cache bytes also fall back
to fresh compilation. The encoded input must be nonempty and fit the transport
frame limit (less than 63 MiB). Principal proofs currently require the same
canonical producer paths. Moving a project or extracting an embedded standard
library to a different directory can therefore lose semantic reuse even when
contents match; exact optimizer-body reuse is checked separately.

Exporting before a successful build rejects with `NoSuccessfulRevision`; the
session remains usable. A failed edit preserves the previous checkpoint.
`close()` drains exports as well as builds, and `dispose()` interrupts them.
Saving a checkpoint has its own cost and should be measured separately from
restoring it. This is an optional restart cache, not a substitute for a retained
compiler session during editing.

Concurrent builds queue in order. A successful build returns
`{ success: true,
revision, bytes, stats }`; a failure returns diagnostics and
keeps the last successful revision. Diagnostics identify files and UTF-8 byte
spans, with labelled UTF-16 spans where available. Returned data belongs to the
caller. `nativeWorkSteps` counts native work, not source-language evaluation
steps.

An unfinished `@hole` additionally publishes `diagnostic.hole`, a
`TypedHoleDiagnostic` exported from the public API. `expected` indexes `nodes`;
each node's `children` indexes a span in `edges`. Function children are
parameter and result, record edges carry field names, and `effects` points to a
row node. Rows preserve repeated operations and explicit open tails. `scope`
includes the current version of each visible binding and its requirements;
`enclosing` selects the containing binding's scheme requirements. The snapshot
owns its data and stays usable after the next edit or after disposal. Its
identities are local to that diagnostic. Do not interpret them as stable
cross-build IDs.

Snapshots have a 1,024-visit traversal budget, nest at most 32 levels, include
at most 32 bindings and 64 requirements, and retain at most 16 KiB of name
bytes. The wire bounds are 1,025 nodes (including the truncation sentinel) and
4,096 edges. `truncated` makes any omitted detail explicit. There is no implied
completion validity or proof of a dispatch choice. Native command diagnostics
publish the same snapshot at `details.hole`. The client validates references,
bounds and graph acyclicity before exposing it.

`build({ signal })` supports cancellation. Cancelling a queued request preserves
the client. Cancelling active work disposes the process and rejects queued work.
`close()` drains queued requests; `dispose()` interrupts them. Both reap the
child and are idempotent. The packaged wrapper also removes its extracted
binary. Standalone Deno/desktop executables must include `blotCompilerBinary`
and `blotStdRoot` (exported URLs). Their embedded standard library is extracted
for the native child and removed when the compiler closes. Project source paths
and explicit dependency/prelude paths must refer to files accessible to that
child.

This is an asynchronous project compilation API. The synchronous SourceCompiler,
analysis object format and exact Bend step budgets are retired. Native
evaluation limits are documented in [the architecture](ARCHITECTURE.md).
