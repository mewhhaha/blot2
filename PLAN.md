# Compiler direction

Zig is Blot's only compiler. Deno provides its project client, CLI, formatter,
source generators, editor integration and WebAssembly host. See the
[repository map](docs/README.md) and [current frontier](CONTINUE.md).

The active program is the [owned-storage rewrite](tasks/STORAGE_REWRITE.md),
with acceptance requirements in tasks 110–121. It replaces counted guest storage
and language tasks with named owners, invocation-local borrows, explicit copies
and copied-packet host workers. The counted backend is still reachable; retiring
it is unfinished implementation work under task 120.

Keep these requirements while simplifying the implementation:

- Target subsecond fresh compilation, below 100ms retained edits, and 1–2MB Gdev
  Wasm. The next fresh-build gate is below five seconds. Throughput goals are
  50,000 source lines in 0.5s, then one million lines per second.
- Preserve the checked language, effects, staging, owner lifetimes, explicit
  snapshots, numerical behavior and host contracts. Unsupported owned-storage
  features must diagnose rather than silently select another memory model.
- Use ordinary functions for compile-time work through `#run`. Controlled
  compile-time build effects remain open; current support is described in the
  [language guide](compiler/guide.md).
- Bound compiler allocation, semantic work and retained cache growth. Reuse must
  remain correct across edits, failed builds, restarts and changed dependencies.
  Keep the remaining numerical targets in tasks 086, 093 and 100–104.
- Measure the responsible compiler/runtime engine with pinned sources,
  compilers, toolchains and workloads. Keep fresh builds, retained edits,
  runtime, output size and allocation measurements distinct. Avoid
  prelude-name-specific optimizations.
- Qualify the real application, libraries, original exports, saves/recovery,
  workers, native/browser hosts and release package. A first frame or a sampled
  development family does not complete this program.

The [task inventory](tasks/README.md) retains unresolved requirements and their
origin. Earlier plans and design alternatives are preserved at the
[pre-cleanup revision](https://github.com/mewhhaha/blot2/tree/541ff890f1df53b5fe8572bd7f2bc41230f2fddb);
[the documentation map](docs/README.md) links the individual records. Superseded
counted-memory and language-task directions are historical, not features to
restore. Task 999's final completion audit remains unfinished.
