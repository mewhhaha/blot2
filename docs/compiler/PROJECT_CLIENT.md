# Zig project API

The optional `assets` registry adds dependency-tracked host parser functions.
See [typed external assets](../host/assets.md) for the descriptor contract, JSON
parser, shader adapter, input overlays, manifests and ownership rules.

The package root exports `createCompiler({ entry, executable? })`. It starts the
packaged Zig compiler by default and supplies the standard prelude. For an
explicit executable and no implicit prelude, use `createZigProjectCompiler` from
`@mewhhaha/blot/zig-project`. Either one runs `blotc serve-project` as a child
process with a cleared environment and speaks
[the project protocol](PROJECT_PROTOCOL.md) to it. Every build loads, checks,
lowers and compiles the project from its sources with the direct backend; no
checked or compiled module carries over from one build to the next.

```ts
import { createCompiler } from "@mewhhaha/blot";

const compiler = await createCompiler({
  entry: "/project/main.blot",
  imports: { "lib/": "/project/library" },
});
try {
  const result = await compiler.build({
    sources: {
      "/project/main.blot": "entry const answer = func () => return 42\n",
    },
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
file created by `blot dependencies`. Each build takes the bundle's modules whose
sources are unchanged as checked and checks the rest; if checking with the
bundle rejects, the build is checked fresh from source. A mismatched bundle is
rejected when the compiler starts. `expectedCompilerIdentity` can pin a
64-character lowercase compiler fingerprint.

`inferenceBudget` sets the inference work allowance (default 1,000,000 steps).
The native CLI accepts the same setting as `--inference-budget`. Each module's
ordinary inference has that allowance; associated-type checking shares an
allowance across the project. Larger configured values apply throughout these
stages, without an additional one-million-step cap. Budget changes alter the
compiler identity, so a dependency bundle made under another budget is rejected.
An `associated_limit` diagnostic from module checking reports the actual
associated work allowance available to that module, which can be smaller after
checking its dependencies. Ordinary effect rows in a solver with no associated
projections do not consume associated normalization work merely because an
implementation is in scope.

`storage` accepts `temporaryBytes`, `growerBytes`, `persistentBytes`,
`transportBytes` and `ownerCapacity`, because Pen forwards them from a program's
settings. Byte values must be positive U32 multiples of 16; owner capacity must
be a positive U32. The client and the compiler validate them, and the direct
backend ignores them: it lays out its own fixed regions.

`frontendWorkers` requests 1–16 module checker workers (default 4). The native
CLI accepts `--frontend-workers` on `build`, `build-project` and
`serve-project`. Projects with at least two eligible modules and 4,096 syntax
nodes check independent modules in dependency-ready batches. Each worker owns
its solver; producer interfaces and the shared symbol pool remain immutable
until join. Diagnostics, an unprepared generated name or combined project-budget
exhaustion replay the original serial order. Source validation, editor queries
and small projects check serially. Optional phase profiling reports
`checking.parallel_batches`, `parallel_jobs` and `parallel_retries`. This
setting is independent of `semanticWorkers`.

`semanticWorkers: 1..16` lowers the modules a build checked to Core on that many
workers. Omitted or `1`, lowering is serial. The native CLI exposes this setting
as `--semantic-workers 1..16` on `build`, `build-project` and `serve-project`.
Worker counts never change the emitted bytes.

With `profileBackend`, `stats.phaseProfile` reports exclusive phase clocks,
allocation requests and requested bytes. Its `checking` object aggregates
project-check invocations across modules: generic-scheme construction, pending
positions scanned, selected requirements and type/row components, scheme
imports, directly read imported bindings and normalization work. Checker work
outside the `check` phase is excluded. Unread imports may still serve shared
callees, coherence or publication; their count is not removable work. Requested
bytes are allocation traffic, not live memory. Compare unprofiled build costs
separately because profiling adds work. Without `profileBackend`, `phaseProfile`
is empty.

`profileTrace: true` streams bounded phase, module and region progress records
over the child's stderr. The client keeps a bounded tail of them in
`profileProgress`, which remains readable after disposal or cancellation.

Concurrent builds queue in order. A successful build returns
`{ success: true, revision, bytes, stats }`. `stats` is
`{ frontend, sourceBytes, freshModules, cachedModules, emittedFunctions, phaseProfile }`:
the frontend's work counts for the modules this build checked, source bytes
read, the modules checked for this build and those reused from the session or
its dependency bundle,
the number of emitted functions, and the optional phase profile. A
`nativeAssets` session also returns `assets`, `assetStats` and
`assetDependencies`. A failure returns
`{ success: false, revision, diagnostics }` and keeps the last successful
revision. Diagnostics identify files and UTF-8 byte spans, with labelled UTF-16
spans where available. Returned data belongs to the caller. `complete()` answers
editor completion queries in the same queue without advancing the revision; see
[the editor completion contract](EDITOR_COMPLETION.md).

An unfinished `@hole` additionally publishes `diagnostic.hole`, a
`TypedHoleDiagnostic` exported from the public API. `expected` indexes `nodes`;
each node's `children` indexes a span in `edges`. Function children are
parameter and result, record edges carry field names, and `effects` points to a
row node. Rows preserve repeated operations and explicit open tails. `scope`
includes the current version of each visible binding and its requirements;
`enclosing` selects the containing binding's scheme requirements. The snapshot
owns its data and stays usable after the next edit or after disposal. Its
identities are local to that diagnostic. Do not interpret them as stable
cross-build IDs. A failed dispatch publishes `diagnostic.explanation`, and a
mismatch at an application or binary operator publishes up to two
`diagnostic.contexts` source spans.

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
analysis object format and exact Bend step budgets are retired.
