# Zig compiler rebuild

The existing Bend compiler and Deno APIs remain the reference and default until
compatibility tests establish parity. No language features are intentionally
removed, and the Zig executable never falls back to Bend or JavaScript.

## Build

The initial supported development target is x86-64 Linux. Install Zig **0.16.0**
and Python **3.10+**, then run from the repository root:

```sh
cd zig
zig build
zig build test
python3 tests_protocol.py -v
./zig-out/bin/blotc-zig --version
```

Use `zig build -Doptimize=ReleaseSafe` for an optimized build with safety checks.
The binary serves the existing framed native protocol, version 13, on stdin and
stdout. It is not a source-file CLI. The existing native Deno factories accept
`{ executable: "zig/zig-out/bin/blotc-zig" }` as an explicit backend selection.
Their existing frontend dependencies must be installed separately.

## What is implemented

The first pass is a **mechanical semantic port**, not yet an idiomatic rewrite
of each compiler stage. `tools/port.py` parses the retained pure algorithms and
`tools/generate.py` emits ordinary Zig functions. The build invokes Python, not
Bend. The executable contains native Zig code, not a Bend interpreter, embedded
Bend runtime, generated C, or generated JavaScript.

At this revision generation covers 70 source modules, 3,425 native functions
(including 165 closure bodies), and 96 explicit primitives. Generated code and
source hashes are available in CI artifacts under `src/generated/`. Keeping the
algorithms traceable makes differential failures easier to isolate before
changing the compiler's data structures or scheduling.

The handwritten native layer includes unsigned and binary32 values, Unicode
strings, persistent Patricia maps, lists and sorting, closures and curried
application, a tail-call trampoline, framed binary IO, and retained session
state. Each request owns an arena; only the live session graph is copied into
the next arena, preserving graph sharing. There is no mid-request collection.

## Checked so far

Five Zig tests cover values, persistent maps, retained sharing, strict decimal
parsing, byte-block output and malformed-request diagnostics. Five process-level
tests cover handshake, multiple invalid requests on one stream, truncated and
oversized frames, and command-line validation. CI builds and runs these in Debug
and ReleaseSafe and checks deterministic source generation.

These tests are **not full language parity**. Source-level differential tests,
valid and invalid programs, Wasm execution, guest ABI and incremental-session
regressions are the next gate. A translated function count is not test coverage.

## Remaining migration gates

- Preserve accepted and rejected source programs, imports and source prelude.
- Verify type/effect inference, const evaluation, nominal and associated types.
- Verify closures, tags, tuples, records, arrays, loops and effect providers.
- Verify emitted Wasm, entry roots, host capabilities and `blot:abi` metadata.
- Verify stateless, incremental and project APIs, cache reuse and rollback.
- Implement actual parallel scheduling. `--threads 1..64` is currently accepted
  for protocol-client compatibility, but this first port executes serially.
- Measure stack depth, request peak memory, build time and compilation speed.
- Replace transitional generated structures only behind compatibility tests.

Do not switch the default compiler or mark this migration complete until the
compatibility gates pass. The source parser remains the existing Deno/Baba
frontend; replacing it is a separate stage, not a hidden change in this port.
