# Continue: fast compilation and the language rewrite

The owner's order (14 November 2026):
1. Make the direct backend (compiler/src/direct/, [plan](tasks/FAST_COMPILE.md))
   the only backend. Done ([deletion record](tasks/DELETE_SCOPED.md)).
2. Carry out the approved [language changes](tasks/LANGUAGE_COHERENCE.md),
   memory model first ([rules and phases](tasks/MEMORY_MODEL.md)), together
   with the frontend speed work.
3. Port the result to Goose.

The goal behind all of it is compiling Blot at 1M lines/s; "prioritize fast
compiles".

## State on main (15 November 2026)

- **Direct backend only.** `compiler/src/compile.zig` is its interface.
  `backend/`, `eval/`, `runtime/`, the scoped reuse and the checker's
  cross-revision reuse are deleted, about 170,000 lines in all.
  `serve-project` builds each revision fresh; dependency bundles (`.blotdep`)
  still provide checked modules.
- **Gdev Main** builds; its first Pen frame is byte-identical (frame.png
  19a03f0a…, frames.trace 86d50101…), at 0.075 ms of guest time per frame
  against the old backend's 2.45 ms.
- **Ink:** `pen test-blot` gives `same 64 wrong 0 newfail 0 other 9` against
  the old backend's reference log.
- **Guest suite:** 1,054 cases pass, 101 are ignored, each with its reason
  (tasks/DELETE_SCOPED.md lists them by kind), and none fail. The full gate
  (`deno task test:compiler`) passes.
- **Memory model phase 1** is done (bf582a9c):
  - the uniqueness pass (compiler/src/check/uniqueness.zig);
  - `aliased_update`;
  - `values.copy`;
  - the storage part of the value restriction.
- **Transitional `=` store.** Phase 1 also landed it, and it stays, by the
  owner's choice "Keep `=` until apps move". Phase 1's `migrate-stores`
  turned 1,880 `:=` in Ink (44ec97e) and 3,011 in Gdev (6aa6350) into `=`.
  These are the writes into arrays a function was handed. Phase 3 moves them
  to the `own` style and deletes `=`.
- **Checker speed.** Gdev's Wasm is unchanged by each of these
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

- **Memory model phase 2** (`own` and borrowed parameters) is measured and
  waits for the owner. Nothing is migrated, and main has none of it. The
  unfinished pass is on branch `wip/memory-phase2-own` (0afccb55).
  - Its 585 guest failures come from the breadth of its rules: it rejects
    the prelude (`identity`, `Maybe.map`, `Array.at`), which every case
    compiles. It also has one bug, in shallow copies.
  - As written (spec section 10.3) the rules reject 352 places in the Gdev
    build and 350 in Ink's tests. With two rules narrowed they reject 44
    and 27.
  - tasks/MEMORY_MODEL.md, "Phase 2: what the borrowed rules reject", has
    the counts, the two recommended rule changes, what the pass still
    needs, and the order of work. Spec Annex B item 13 points to it.
  - **The owner decides:** the two rule changes, and whether `own` in
    function types waits for the B3 and C8 removals.
- **Memory model phase 4** (the value restriction for `let`) is measured
  and not built. std, Ink and Gdev need no change and Gdev's frame is
  identical, but 13 guest cases and 11 native laws pin the old rule and it
  saves about 1% of a build. tasks/MEMORY_MODEL.md has the list and the
  patch.
- **Checker speed.** A release (LLVM) compiler builds Gdev Main in 1.30 s
  on the cloud container with one frontend worker, of which checking is
  0.87 s (lower 0.16, backend 0.14, lex 0.03, parse 0.03).

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

- Development compiler: `zig build install -Doptimize=safe -Dllvm=false --prefix zig-out-dev`;
  fast: `-Doptimize=fast --prefix zig-out-direct`. Run both in compiler/,
  under `flock /var/tmp/blot2-heavy.lock systemd-run --user --scope -q -p MemoryMax=14G -p MemorySwapMax=2G`.
- Guest suite: `deno test -A --parallel tests/guest tests/host -- compiler/zig-out-dev/bin/blotc`.
- Gdev: `deno run -A scripts/integration/build_gdev.ts --compiler X --timeout-ms 600000 OUT`
  (`--profile` adds phase timings), then
  `python3 scripts/integration/run_pen.py --launch --hardware --compiled-main OUT/main-*/main.wasm --expected-wasm-sha256 SHA --output DIR`.
  Without `--hardware` it runs headless on a software Vulkan driver
  (`apt-get install mesa-vulkan-drivers`). There frame.png is c1ff619f…;
  frames.trace is 86d50101… on either.
- Ink: build/goose-perf/ink-direct is a copy of ../ink whose pen.json runs
  build/goose-perf/blotc-direct (compiler/zig-out-direct). Refresh its .blot
  files from ../ink after changing Ink, then run
  `../../../pen/target/release/pen test-blot --project ink-direct` from
  build/goose-perf and compare with build/goose-perf/compare_ink.py against
  ink-zig.log.
- Profiling:
  - Build with `-Doptimize=fast -Dllvm=true -Dprofiling=true`.
  - Sampling, on a machine that has build/goose-perf (untracked): run the
    compiler (not Deno) with
    `LD_PRELOAD=build/goose-perf/prof/cpusample.so CPUSAMPLE_DIR=… CPUSAMPLE_US=500`
    and summarize with `ABSADDR=1 python3 build/goose-perf/prof/analyze.py DIR BINARY`
    (or `callers.py DIR BINARY FUNCTION`).
  - Instruction counts, anywhere valgrind is installed: give `build_gdev.ts`
    a `--compiler` shell script that runs
    `valgrind --tool=callgrind --callgrind-out-file=DIR/callgrind.out.%p blotc "$@"`
    without `exec`. The client kills the script, valgrind sees the end of its
    input and writes the file. Read it with
    `callgrind_annotate --inclusive=yes` and `--tree=caller`.
- A fresh cloud container has none of the toolchain. Install what
  .github/workflows/ci.yml pins: Zig 0.17.0, Deno 2, and zig-analyzer
  0.17.0-1 (set `ZIG_ANALYZER`, or put it at
  ../zig-analyzer/zig-out/bin/zig-analyzer). Pen needs
  `apt-get install pkg-config cmake libasound2-dev libdbus-1-dev libudev-dev`,
  then `cargo build --release -p pen` and, in ../pen/plugins,
  `cargo build --release --target wasm32-wasip2`. The `flock` and
  `systemd-run` wrappers above are for the owner's machine.
- `deno task lint:zig` is at zero findings with zig-analyzer 0.17.0-1. Main
  had 16 until 15 November, so CI failed there before it ran a test.
- Two host tests depend on process start-up time and can fail when the
  whole suite runs in parallel on a slow machine:
  tests/host/lsp.test.ts ("Completion was never sent", its wait is now
  10 s) and tests/guest/zig_project_transport.test.ts ("startup timed
  out" after 2 s, seen once). Neither runs the checker.

## The Goose port (phase 3 of the order)

- compiler-goose/ ports the deleted scoped compiler and is parked. Its
  history and evidence are pinned at b9875a88.
- It builds with plain upstream Goose: compiler-goose/tools/build_upstream_goose.py
  builds github.com/aardappel/goose at d92c4315, unpatched (owner, 14
  November 2026). Plain upstream did not finish checking the old port in 25
  minutes.
- The new port targets the rewritten, much smaller compiler, against plain
  upstream from the start.

## Contracts

- Preserve ABI 8 and session protocol 2 until the owner changes them.
- Preserve the sibling checkouts' sources and assets (../pen, ../ink,
  ../gdev); push their changes to their main.
- No hidden O(n) copies: when an update can't be done in place, it is an
  error that asks for an explicit copy.
- Every change keeps Ink's suite and Gdev's first frame identical, unless a
  semantic change explains the difference.
