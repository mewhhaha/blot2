# Continue: fast compilation and the language rewrite

The owner's order (14 November 2026):
1. Make the direct backend (compiler-goose/src/direct/, [plan](tasks/FAST_COMPILE.md))
   the only backend. Done ([deletion record](tasks/DELETE_SCOPED.md)).
2. Carry out the approved [language changes](tasks/LANGUAGE_COHERENCE.md),
   memory model first ([rules and phases](tasks/MEMORY_MODEL.md)), together
   with the frontend speed work.
3. Port the result to Goose. Done; see below.

The goal behind all of it is compiling Blot at 1M lines/s; "prioritize fast
compiles".

Added on 15 November 2026: "add some more patches to goose to make it
faster until goose to wasm is ready. And try to finish the goose compiler
so we can retire zig." Then, the same day: "make the switch and delete the
zig compiler". Both are done: the compiler is the Goose one in
compiler-goose/, and compiler/ (Zig) is gone. The record is in
[tasks/GOOSE_PORT.md](tasks/GOOSE_PORT.md). Next is compile times.

## State on main (16 November 2026)

- **One compiler, written in Goose** (compiler-goose/). The Zig compiler it
  was ported from was removed on 15 November 2026; its last tree is commit
  359b14f6, directory compiler/. Before the removal the two gave the same
  Wasm on every program compared, and the Goose compiler's tests now
  compare it with what Zig produced (compiler-goose/tests/fixtures,
  tests/uniqueness and tests/direct).
- **Direct backend only.** `compiler-goose/src/compile.goose` is its
  interface. The scoped backend, the evaluator, the scoped reuse and the
  checker's cross-revision reuse are deleted. `serve-project` builds each
  revision fresh; dependency bundles (`.blotdep`) still provide checked
  modules.
- **Gdev Main** builds (Wasm dd97fe15…, 2,724,223 bytes); its first Pen
  frame is byte-identical (frame.png 19a03f0a… on hardware, c1ff619f… on
  the software driver; frames.trace 86d50101…), at 0.075 ms of guest time per frame
  against the old backend's 2.45 ms.
- **Ink:** `pen test-blot` gives `same 64 wrong 0 newfail 0 other 9` against
  the old backend's reference log.
- **Guest suite:** 1,063 cases pass, 101 are ignored, each with its reason
  (tasks/DELETE_SCOPED.md lists them by kind), and none fail. The full gate
  (`deno task test:compiler`) passes. It no longer has Zig's native laws;
  see "What went with Zig" in tasks/GOOSE_PORT.md.
- **Memory model phase 1** is done (bf582a9c):
  - the uniqueness pass (compiler-goose/src/check/uniqueness.goose), which
    now also checks `own` parameters;
  - `aliased_update`;
  - `values.copy`;
  - the storage part of the value restriction.
- **Transitional `=` store.** Phase 1 also landed it, and it stays, by the
  owner's choice "Keep `=` until apps move". Phase 1's `migrate-stores`
  turned 1,880 `:=` in Ink (44ec97e) and 3,011 in Gdev (6aa6350) into `=`.
  These are the writes into arrays a function was handed. Phase 3 moves them
  to the `own` style and deletes `=`.
- **Checker speed.** These were measured on the Zig compiler; the Goose
  compiler has the same changes. Gdev's Wasm is unchanged by each of them
  (2,720,970 bytes, sha256 af9f24dd…).
  - Importing a catalog no longer scans every earlier associated member for
    each new one; it uses a hash set. This was quadratic per module and 12%
    of a Gdev build.
  - A module copies the scheme of an imported associated member (`Vec3.add`,
    `Array.at`) at its first lookup, not at import. Gdev's 264 modules
    imported 48,324 schemes and now import 17,560. A member a module only
    forwards gets a binding that names its producer, and the importing
    module reads the scheme from the producer
    (`ProducerCapabilities.interface`).
  - The lexer compares a keyword's first letter before its spelling and
    skips ASCII when it validates UTF-8.
  - Together: 7.19 to 6.41 billion instructions for a Gdev build, and 1.36
    to 1.30 s on the cloud container
    ([record](benchmarks/evidence/measurements/2026-11-15-lazy-associated-import.json)).
  - The new version a `:=` gives a name is no longer generalized (6.37
    billion). This is the rebinding part of the value restriction, memory
    model phase 4.

## In progress

- **Removing `=`** (memory model phases 2 and 3). The owner asked on 16
  November 2026 to finish the conversion "so we don't have the mutable =
  anymore", and then to continue until it is done. It is not done.
  tasks/MEMORY_MODEL.md, "Phase 2 is the default" and "One rule set for
  every module", has the details.
  - **Done:** one rule set for every module. Every function's result is
    its caller's alone and a call only borrows its arguments, through
    function values too; `own` parameters; moves at a local's last read; a
    closure written as an argument gives back what it captured; std has no
    store; 379 provably unique stores in Ink and Gdev became `:=`.
  - **What `=` is now:** a write through what a function was lent, which
    may keep only values it owns (`kept_value`). A function that still
    returns or keeps what it was lent is marked `lent` (66 in Ink and
    Gdev) and nobody relies on it.
  - **Left:** about 4,400 stores in Ink and Gdev (table in
    tasks/MEMORY_MODEL.md) and the 66 `lent` functions. The way is
    top-down from the frame loop: once every caller owns what it passes, a
    writer takes it with `own`, returns it, and its `=` become `:=`. A
    caller keeps ownership across calls to functions that still use `=`,
    so this can go one function at a time with Ink's suite and Gdev's
    frame checked at each step.
  - **Built for it:** `own` on lambdas and in function types (Gdev's
    systems are callbacks): `own World -> U32 -> World`.
    `GrowArray` and `ResizeArray` are owned values like arrays, so an
    `own` parameter of such a type needs storage nothing else holds.
  - **Needed on the way:** a way to take a record apart into owned fields
    (`bind_frame`); and the stores through one-element arrays and growable
    buffers need their owner threaded from the frame loop.
  - **Then:** delete `=`, `lent`, `migrate-stores` and
    `BLOT_REPORT_STORES`, and bring spec section 10.3 in line.
  - Gdev's own tests: 13 modules that compile now for the first time have
    27 failing checks. They were hidden behind a compile error and are not
    looked at yet.
  - Tools: `python3 scripts/integration/count_stores.py DIR...` counts
    what is left; `python3 scripts/integration/stores_to_updates.py
    PROJECT ENTRY...` converts what the compiler can already prove.
- **Memory model phase 4** (the value restriction for `let`) is measured
  and not built. std, Ink and Gdev need no change and Gdev's frame is
  identical, but 13 guest cases pin the old rule (and 11 of Zig's native
  laws did) and it saves about 1% of a build. tasks/MEMORY_MODEL.md has the list and the
  patch.
- **Compile times** are next. The Goose compiler builds Gdev Main in 1.9 s
  (the Zig compiler took 0.9 s with four checkers and 1.37 s with one);
  tasks/GOOSE_PORT.md has the table. The profile below is of the Zig
  compiler, one checker, where checking was 0.87 s of 1.30 s (lower 0.16,
  backend 0.14, lex 0.03, parse 0.03). The algorithms are the same, so the
  shares should carry over; the Goose compiler has not been profiled.

  | Next costs (share of a Gdev build's instructions, inclusive) | |
  | --- | ---: |
  | `validateModuleBodies` | 60% |
  | `inferGlobal` / declaration bodies | 49% |
  | `types.Store.resolve` | 26% |
  | Core lowering (`lowerWithOrigins`) | 11% |
  | `finishGlobal` (generalization, `schemeInto` 7%) | 11% |
  | `collectModuleHeaders` (`copyNominal` 5%) | 9% |
  | `finish` (resolves every expression's type once more) | 9% |
  | load (lex and parse) | 7% |

  - No function is hot on its own: `resolveNode` has the largest self cost
    at 6%, and hash maps total 15%.
  - `copyNominal` still copies every public type of every imported catalog
    into each module (29,593 copies, 5%). Making it lazy touches the 65
    places that read `self.nominals`.
  - The costs above the import are inference itself. Required signatures
    (tasks/FAST_COMPILE.md, decision 2) remove generalization and let bodies
    be checked alone; that is the step that changes the order of magnitude.

## Language

- docs/language/spec.md is the target syntax (third revision and later
  edits).
- tasks/LANGUAGE_COHERENCE.md records every approval: sections A–E, the
  amendments, "Round 2 approvals" (twelve items: named trait outputs, effects
  as records, no value blocks, numbers U8–U64/I8–I64/F32/F64, `let` without
  shadowing, field defaults, collection loops, no spreads, …) and the
  reversal of B2 (`use` stays).
- Memory model: every value is immutable, arrays included, and `:=` builds
  the successor in place when the local owns it. Otherwise it is an error
  that asks for `values.copy`. Parameters are borrowed unless `own`, call
  results are owned, and a state `modify` hands the state over as `own`.
  `State.get` on array state and the strictness of `use` are open (spec
  Annex B).
- Text as UTF-8 `Array U8` changes what crosses the host boundary (ABI 8);
  when it lands is the owner's call.

## Commands

- Compiler: `deno task build:compiler` writes the optimized compiler,
  compiler-goose/build/blotc-goose (about seven minutes; Pen, the siblings
  and the tests' default path run it). `deno task build:compiler:dev`
  writes a debug compiler, compiler-goose/build/blotc-goose-dev, in about a
  minute and a half. The first build also builds the patched Goose. The
  build needs clang, cmake, ninja and Python 3.
- Gate: `deno task test:compiler` (tooling tests, the optimized build, the
  recorded references, the package, every guest and host test).
  `deno task test:guest` runs the guest and host suite against the
  optimized compiler as it is; `deno task test:compiler:dev FILES` builds
  the debug compiler and runs those files.
- References: `python3 compiler-goose/tools/test_fixtures.py`,
  `test_uniqueness.py` and `test_direct.py` compare the compiler with what
  the Zig compiler produced. `--record EXE` rewrites a record after a
  deliberate change of behavior.
- Gdev: `deno run -A scripts/integration/build_gdev.ts --timeout-ms 600000 OUT`
  (`--profile` adds phase timings; `--compiler X` picks another compiler),
  then
  `python3 scripts/integration/run_pen.py --launch --hardware --compiled-main OUT/main-*/main.wasm --expected-wasm-sha256 SHA --output DIR`.
  Without `--hardware` it runs headless on a software Vulkan driver
  (`apt-get install mesa-vulkan-drivers`). There frame.png is c1ff619f…;
  frames.trace is 86d50101… on either.
- Ink: `../pen/target/release/pen test-blot` in ../ink. Today it gives
  268 passed, 1 failed, 3 did not compile, in 73 modules; the Zig compiler
  gave the same log.
- Profiling: the tools in benchmarks/tools (`profile_compile.ts`,
  `summarize_compile_profile.py`, `summarize_stacks.py`) name stack frames
  by Zig source file and need redoing for the Goose compiler. Instruction
  counts work as before, anywhere valgrind is installed: give
  `build_gdev.ts` a `--compiler` shell script that runs
  `valgrind --tool=callgrind --callgrind-out-file=DIR/callgrind.out.%p blotc-goose "$@"`
  without `exec`. The client kills the script, valgrind sees the end of its
  input and writes the file. Read it with
  `callgrind_annotate --inclusive=yes` and `--tree=caller`.
- A fresh cloud container has none of the toolchain. Install Deno 2, and
  `apt-get install clang cmake ninja-build` for the compiler. Pen needs
  `apt-get install pkg-config cmake libasound2-dev libdbus-1-dev libudev-dev`,
  then `cargo build --release -p pen` and, in ../pen/plugins,
  `cargo build --release --target wasm32-wasip2`.
- CI (.github/workflows/compiler.yml) builds the compiler and runs
  `deno task check`. It fails in the guest phase, as it did before the
  switch: tests/guest/owned_render_copy_execution.test.ts imports
  ../ink/lib, and the runner has only blot2. A copy of the repository
  without its siblings fails exactly those two cases. The owner has said a
  failing CI is fine for now; fetching Ink in CI, or having the test declare
  that it needs Ink, would fix it.
- Two host tests depend on process start-up time and can fail when the
  whole suite runs in parallel on a slow machine:
  tests/host/lsp.test.ts ("Completion was never sent", its wait is now
  10 s) and tests/guest/zig_project_transport.test.ts ("startup timed
  out" after 2 s, seen once). Neither runs the checker.
- In the same file, "completion reaps a malformed peer" failed once with
  "Text file busy" when it spawned the fake compiler it had just written
  (15 November, under `--parallel`). The compiler under test is not
  involved.

## The compiler in Goose

[compiler-goose/README.md](compiler-goose/README.md) has the layout, the
build, the generators and the tests. [tasks/GOOSE_PORT.md](tasks/GOOSE_PORT.md)
has the port's record: the comparison with Zig before it was removed, what
went with Zig, the known differences and the speed.

- `--frontend-workers` checks modules in forked copies of the process. That
  is correct and slower than one checker, so one is the default.
- The `memory` field of a compilation record counts the compiler's pooled
  owners, not every allocation as Zig's did; `live_bytes` must be 0.

## Contracts

- Preserve ABI 8 and session protocol 2 until the owner changes them.
- Preserve the sibling checkouts' sources and assets (../pen, ../ink,
  ../gdev); push their changes to their main.
- No hidden O(n) copies: when an update can't be done in place, it is an
  error that asks for an explicit copy.
- Every change keeps Ink's suite and Gdev's first frame identical, unless a
  semantic change explains the difference.
