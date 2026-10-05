# Zig project API

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
