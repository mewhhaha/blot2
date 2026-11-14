# Zig compiler

This directory contains Blot's sole compiler. Zig owns parsing, type and effect
checking, lowering to Core, the project server and WebAssembly emission. The
direct backend (`src/direct/`, [plan](../tasks/FAST_COMPILE.md)) is the only
code generator; `src/compile.zig` is its interface. The Deno client and host
tools live in [host/](../host/README.md).

Read [CONTINUE.md](../CONTINUE.md) for the current frontier and
[tasks/LANGUAGE_COHERENCE.md](../tasks/LANGUAGE_COHERENCE.md) for what follows.

Use Zig **0.17.0**. From the repository root, `deno task build:compiler:dev`
builds with the native backend (`-Dllvm=false`) and installs
`compiler/zig-out-dev/bin/blotc`. Keep the compiler with the matching root
`std/` library.

Run `deno task check:dev` (the `direct` area) for the documented development
cycle. It is a focused regression family, not full qualification. Compiler
changes require the full gate and Zig lint described in [AGENTS.md](../AGENTS.md).
Inspect the real Gdev frame PNG after integration; source inventory alone does
not qualify the runtime.

## Contracts and evidence

- [Compiler architecture](../docs/compiler/ARCHITECTURE.md),
  [ownership contract](../docs/compiler/CONTRACT.md), and
  [scoped-storage design](../docs/compiler/SCOPED_STORAGE.md).
- [Project client contract](../docs/compiler/PROJECT_CLIENT.md) and
  [project protocol](../docs/compiler/PROJECT_PROTOCOL.md).
- [Qualification reports](../docs/qualification/) and pinned raw records under
  [benchmarks/evidence](../benchmarks/evidence).

Evidence identifies its own source and toolchain; it does not automatically
qualify a later candidate.
