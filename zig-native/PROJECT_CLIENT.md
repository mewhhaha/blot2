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
