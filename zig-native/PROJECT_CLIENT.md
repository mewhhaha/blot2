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

`codegenTier: "development"` skips optional scalar replacement and automatic
vectorization. Type/effect checking, constant evaluation, explicit cleanup and
lifetime analysis still run. The default is `"optimized"`. A project session
keeps its selected tier; start a separate session to compare outputs. Optimized
body captures are valid only for the tier that produced them. This option does
not change the optimization mode used to build the native compiler itself.

`shareMachineCode: true` enables the internal body-sharing prototype. Identical
resolved functions share one Wasm body while their source/evidence identities
and indirect table slots remain distinct. Exported functions keep distinct
identities. The default is `false`. On the frozen gdev workload this removes 272
duplicate bodies and reduces Wasm size by 7.8%; no total compile-time improvement
has been established. The
`runtimeOptimization.shared` counter counts removed duplicate bodies. Artifact
statistics describe the logical functions retained for replay.

`codegenWorkers` requests 1–16 concurrent optimizer workers (default 1). Jobs
read immutable function bodies and completed lifetime summaries; each worker
owns its scratch arena. Small builds and edits with fewer than four uncached
bodies or 4,096 instructions stay serial. `runtimeOptimization.workers` and
`parallel_jobs` report the actual work scheduled. Output is byte-identical to
serial assembly. This prototype parallelizes runtime optimization, not semantic
checking or evaluation. Four workers reduced the measured cold assembly phase
from about 30 ms to 18 ms on gdev, but total latency was too noisy to establish
a speedup. It remains opt-in.

`exportCheckpoint()` returns portable backend cache bytes from the last
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

The caller owns persistence; the compiler does not read or write cache files
automatically. Startup copies the provided bytes. A checkpoint contains admitted
principal-query proofs and optimized function bodies, not evaluated source
values or arbitrary specializations. Compiler identity, complete source/catalog
and symbol identities, observed semantic inputs, compilation tier and optimizer
dependencies govern reuse. Changed or unsupported inputs compile afresh. Stale
or corrupt cache bytes also fall back to fresh compilation. The encoded input
must be nonempty and fit the transport frame limit (less than 63 MiB).
Principal proofs currently require the same canonical producer paths. Moving a
project or extracting an embedded standard library to a different directory can
therefore lose semantic reuse even when contents match; exact optimizer-body
reuse is checked separately.

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
