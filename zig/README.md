# Zig compiler

A native Zig backend for Blot's existing source language, guest ABI and
version-13 compiler protocol. It does not invoke Bend, embed Bend's runtime, or
fall back to JavaScript. The existing Deno/Baba source frontend is retained, not
reimplemented. The original backend remains available; selecting Zig does not
replace it.

## Build and use

The supported development target is **x86-64 Linux**, with **Zig 0.16.0** and
**Python 3.10+**. Source-file commands additionally need the repository's
Deno/Baba frontend dependencies. Bend and the generated JavaScript reference are
not needed for these commands.

From the repository root:

```sh
(cd zig && zig build)
deno task blot:zig check examples/syntax.blot
deno task blot:zig build examples/syntax.blot build/syntax.wasm
```

`zig build` is the quick, checked Debug build. For optimized compiler execution:

```sh
(cd zig && zig build -Doptimize=ReleaseSafe)
```

Builds target baseline CPU instructions by default, so an artifact is not tied
to the CPU of the build machine. `-Dcpu=native` explicitly opts into host-only
instructions for a local build. Release builds strip debug information by default;
`-Dstrip=false` retains it.

The executable itself (`zig/zig-out/bin/blotc-zig`) is the framed compiler
service, not a source-file CLI. Use the Deno command above, or explicitly select
it in any of the native stateless, incremental, or project factories:

```ts
import { createNativeCompiler } from "./compiler/native.ts";

const compiler = await createNativeCompiler({
  executable: "zig/zig-out/bin/blotc-zig",
  threads: 4,
});
try {
  const { bytes } = await compiler.compile("entry const answer = fn () => 42");
  const { instance } = await WebAssembly.instantiate(bytes);
  console.log((instance.exports.answer as () => number)()); // 42
} finally {
  await compiler.dispose();
}
```

## Implementation

This is a **mechanical semantic port with a native runtime**, rather than a
hand-rewritten implementation of every compiler stage. `tools/port.py` reads the
retained pure algorithms and `tools/generate.py` emits ordinary Zig functions.
Generation rejects unsupported syntax, unknown primitives, and excessive arity.
The generated manifest records source hashes, function counts, outlined match
arms, parallel tasks and the maximum call arity. Generated files are build
outputs, not manually edited source.

The native layer implements unsigned and binary32 values, Unicode strings,
persistent Patricia maps, lists and sorting, closures and curried application, a
tail-call trampoline, binary framing and retained session state. Large match
arms are outlined into separate native functions so a recursive call does not
reserve stack space for every alternative in its dispatcher.

`--threads 1..64` controls a persistent bounded worker pool. The existing
explicit parallel batches become tasks; results retain source order. A joining
thread helps execute queued work to avoid nested fork/join starvation. Tasks
have independent trampoline scratch and share a thread-safe request arena. All
tasks are joined before the arena can be destroyed. Worker stacks reserve 64 MiB
of virtual address space, committed on demand.

Only the live session graph is copied into the next arena, preserving sharing.
There is no mid-request garbage collection. Requests are bounded to 16,777,216
wire words. Allocation sizes and framing arithmetic are checked before use.
Linux scheduling restoration is best effort; `--inherit-priority` preserves the
launcher's policy on the main thread and its workers.

## Validation

The `Zig compiler` workflow builds Debug and ReleaseSafe, runs native tests and
protocol/generator regressions, checks deterministic generation, and runs pinned
**zig-analyzer 0.16.0-4** on handwritten Zig. The analyzer configuration
excludes only generated code and build outputs. Its ownership contract
identifies arena allocators; three local directives explain temporary
arena-owned buffers.

Both Debug and ReleaseSafe run the complete compatibility gates below, split
into four disjoint test-file shards per mode. The native APIs and test adapter
are also type-checked. The optimized binary also runs protocol regressions under
a baseline QEMU x86-64 CPU. This
covers valid analysis, deterministic Wasm emission, retained sessions, diagnostic
recovery, malformed frames and thread limits without relying on the build host's
CPU extensions.

Compatibility is checked separately from those runtime tests:

- Standalone tests run all three native APIs **before** JavaScript reference
  modules exist, including failed revisions, imports and process recycling.
- The complete existing compiler suite runs with the Zig executable at the
  native process boundary, including Wasm execution, host capabilities,
  incremental/project caches, framing, diagnostics and scheduling.
- A second run redirects source-compiler calls through `source_adapter.ts`. Each
  operation compares Zig with the unchanged JavaScript reference, checks exact
  outputs or diagnostics, and returns Zig's artifact to the original test. Guest
  tests therefore execute Zig-produced Wasm. Calls exercise 1, 2, 4 and 8
  compilation threads.

The JavaScript reference is generated by the matched Bend 2.0.32 loader without
patches. Its source proof check is a separate CI gate. The differential adapter
is test-only; it is never a fallback in the native compiler.

Local runtime checks:

```sh
cd zig
zig build test
python3 tests_protocol.py -v
python3 tests_generate.py -v
zig-analyzer check --no-cache .
```

To replay the complete suites locally, first build the unmodified JS reference,
then select the Zig executable at `generated/compiler/blotc`. This path is an
ignored development output, not a source change. CI shows the exact commands and
uploads test logs alongside the compiler artifacts. All logged test pipelines
propagate failures; a successful `tee` cannot turn a failing suite green.

The port retains generic tagged values and source-derived semantic algorithms.
Replacing them with specialized Zig data structures, replacing the source
frontend, and claiming speed improvements over Bend are separate optimization
work. This port does not claim a measured speedup over the original backend.
