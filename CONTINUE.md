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

## Where it stopped (17 November 2026, evening)

The owner said "Stop now and push everything to main with a CONTINUE.md".
Everything below was pushed to `main` in blot2, Ink, Gdev and Pen as it
stood, mid-round. Read this before anything else.

**The thread:** removing the `=` mutation store (the owner chose the
explicit form: a writer takes what it changes with `own`, returns it, and
the caller rebinds; `let x = …` stays). Notes and rules:
[tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md), sections from "The
generated encoders" on. About 1,580 stores were left before the round in
progress (count with `python3 scripts/integration/count_stores.py ../ink/lib
../ink/tests ../gdev/src ../gdev/tests ../gdev/test_support ../gdev/devtools
../gdev/performance`).

**Verified and on main before the stop:** the generated Pen encoders, the
second and third layers of Gdev functions that own the world, the Ink
modules the game does not use (except physics), and the compiler rules
those needed (blot2 gate: 1,175 cases, 0 failures). At each of those steps
Gdev's packets over 120 frames were byte-identical, Gdev's tests were
391 passed / 67 failed / 107 did not compile module by module as before,
and Ink's were 268 passed / 1 failed / 3 did not compile.

**The round in progress (the save/restore vertical), not fully verified:**
the save schema, the ~40 `decode_into`/`reset_storage` functions it hands to
`persist.restore_into`, Ink's `persist` helpers, the host's `initialize`/
`keep`/`decode_state`/`decode_scene` hooks and the scene history now take
the world with `own` (tasks/MEMORY_MODEL.md, "Saving and restoring").
Then seven workers brought Gdev's tests, fixtures, devtools and
performance programs in line. What was checked:

- `gdev/src/main.blot` and `devtools/main.blot` check clean, and Gdev's
  packets over 120 frames are byte-identical (checked mid-round, before the
  test conversions; the game's code did not change after that).
- Ink checks 62 of 65 clean (as before) and its suite was at baseline
  (268/1/3) with Ink's side of the round in.
- Gdev's check over all entries: 219 of 231 clean. Besides the six known
  failures (salt_hauling_split, gizmos, codec_domains, three rejected
  tests), these still call `world.decode_state`/`decode_scene` in the old
  shape (`world.decode_state access values destination`); they need
  `let (report, access) = world.decode_state access values` and the
  enclosing function owning the world:
  `test_support/rocket_mornings.blot` (99),
  `test_support/traps_codec_rejects_fixture.blot` (81, 120, 131),
  `tests/codec_saved_state.blot` (87, 102, 626),
  `tests/restore_game.blot` (30, 36); `tests/rocket_mornings.blot`,
  `traps/codec_rejects.blot` and `traps/codec_values.blot` fail only
  because of those fixtures.
- **Not run for this round:** Gdev's test suite (`cd ../gdev &&
  ../pen/target/release/pen test-blot`; compare module by module with
  `build/scratch/tcmp4.py build/scratch/gdev-test-l3.txt NEW` against the
  third layer's run), the benchmark, the long run, the blot2 gate. Do those
  first, after fixing the files above.
- The workers reported their choices (all claimed to keep values the
  same): a few tests copy what they used to pass as views of the world;
  `tests/progression.blot` rebuilds a research record with a copied order
  view; several helpers moved reads before or after a hand-over. A worker
  warned that commit 379e1f6 caught `tests/recruit_notices.blot` mid-edit;
  the pushed tree has the finished file.

**Held back on Ink's working branch:** the physics conversion (rigid,
joints, physics, prepared, springs), commit 58e6b02: with the step owned
round the tick loop the backend releases nothing per iteration and
`tests/prepared-physics.blot` runs out of stack (task: a backend release
that keeps what an iteration carries out; tasks/MEMORY_MODEL.md).

**Next, in order:** fix the five files above; run the verification above;
then the functions `own_closure.py` still leaves out (those that return a
value need `(result, access)`; those called on a world a closure captures
need restructuring; the hooks record and Ink's editor chain, which still
lend the world); Ink's library modules the game uses; then delete `=`,
`lent`, `migrate-stores` and the report switches and bring spec 10.3 in
line. Open limits of the ownership pass that the workers met are listed
in tasks/MEMORY_MODEL.md and in the task list (a name bound to a result
that passes a borrow through, names captured by lambdas, names read last
in nested loops, a comprehension over a view of an untyped world's field).

Tools (scripts/integration/): `own_closure.py` (pick and convert a closed
set of functions), `ownify.py`, `unalias.py`, `harvest_stores.py`,
`own_restores.py`, `paths_for_parts.py` (not for names that type a
growable field), `count_stores.py`. Worker briefs that worked well are in
the session scratchpad, not in the repository; the rules they state are in
tasks/MEMORY_MODEL.md.

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
- **Gdev Main** builds (Wasm 74998ccc…, 2,621,601 bytes); its first Pen
  frame is byte-identical (frame.png 19a03f0a… on hardware, c1ff619f… on
  the software driver; frames.trace 86d50101…), at 0.075 ms of guest time per frame
  against the old backend's 2.45 ms.
- **Ink:** `pen test-blot` gives `same 64 wrong 0 newfail 0 other 9` against
  the old backend's reference log.
- **Guest suite:** 1,069 cases pass, 101 are ignored, each with its reason
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
    returns or keeps what it was lent is marked `lent` (55 in Ink and
    Gdev) and nobody relies on it.
  - **Left:** 1,619 stores in Ink and Gdev (table in
    tasks/MEMORY_MODEL.md) and 55 `lent` functions. The way is
    top-down from the frame loop: once every caller owns what it passes, a
    writer takes it with `own`, returns it, and its `=` become `:=`. A
    caller keeps ownership across calls to functions that still use `=`,
    so this can go one function at a time with Ink's suite and Gdev's
    frame checked at each step.
  - **Built for it:** `own` on lambdas and in function types (Gdev's
    systems are callbacks): `own World -> U32 -> World`; `f (own x)` at a
    call of an untyped function. `GrowArray` and `ResizeArray` are owned
    values like arrays. Names that borrow give back at their last read,
    and so does a borrowed value without a name (an argument, what a
    plain value is read out of, what a loop walks).
  - **The world is one value now** (tasks/MEMORY_MODEL.md): the frame's
    buffers live in Gdev's `FrameAccess`, made once and emptied each
    frame; the hooks no longer capture it; `bind_frame` is out of the
    session's path.
  - **The session owns it:** `world_storage.owners` returns the world,
    `host.run` takes it with `own` and `program.run` rebinds it round the
    loop.
  - **The stages own it** (tasks/MEMORY_MODEL.md, "The stages own the
    world"): `host.frame`, Ink's `app` and `clock.advance`, and Gdev's
    stage lambdas take the world and hand it back. `app.stages` has a
    typed signature. The tests, devtools and performance programs that
    call them are converted (`app.lent` wraps stage functions that still
    write through a lent world).
  - **The backend keeps up with it:** a write through an array inside a
    wide record no longer copies the record, and a loop that carries one
    releases each iteration's memory when the record came out as it went
    in. Before that the pushed game filled its stack after some thousands
    of frames (the session loop carried the world and released nothing).
    Open: an iteration that puts a new array into the carried world
    releases nothing; that needs a release that keeps survivors
    (tasks/MEMORY_MODEL.md, "What the backend needed").
  - **The systems the stages call own it** (17 November 2026): 66
    functions of Gdev take the world and return it
    (`scripts/integration/ownify.py`), and where nothing else borrows,
    their stores through names for parts are updates of the world
    (`scripts/integration/unalias.py`). The pass lets a field of a local
    be given to an `own` parameter and put back, the checker indexes a
    field of a record that is not known yet, and a parameter without a
    type that was only lent can no longer be given away (it could, and
    Ink and several tests relied on it).
  - **The generated encoders own their buffer** (17 November 2026):
    `pen codegen` writes `encode_render_views`, `encode_mesh_frame` and
    the canonical walk in the explicit form (the buffer is `own`, written
    with `:=` and returned), and `program.run` owns the world and rebinds
    it round the loop. That was 2,208 stores. A view now borrows the
    field it is made of, and a field of a function's own local can leave
    in its result (tasks/MEMORY_MODEL.md, "The generated encoders").
    384 provable stores in Gdev's tests became updates
    (`scripts/integration/harvest_stores.py`).
  - **More of the pass, for the next level** (17 November 2026): an arm
    of a `case` or an `if` that names a local at its last read moves it;
    a value is given when the call happens, so another argument may read
    it first; a `lent` function may return what it was lent but not keep
    it (`kept_value` holds there too), so a call to one only borrows.
    `scripts/integration/own_closure.py` picks a set of functions closed
    under their callers and converts it (ownify.py underneath), and
    `unalias.py` works from a tree that already has diagnostics.
  - **The second layer** (17 November 2026, tasks/MEMORY_MODEL.md, "The
    second layer of Gdev"): 68 more Gdev functions own the world, and the
    Ink modules the game does not use are converted except physics, whose
    conversion (Ink commit `58e6b02`, working branch) waits for a backend
    release that keeps what an iteration carries out. The pass no longer
    keeps loans alive after an early return, gives nothing of an untyped
    value away while a name borrows a field of it, and lets a name read
    last by an argument give back before the given argument is judged.
  - **Next:** the functions those systems call, level by level (64 at
    the next one), the `present` stage's draw functions, then Ink's
    library writers, which take a part and return it
    (`access.robot := ecs.insert access.entities access.robot index
    robot`).
  - Open:
    - A call that returns the world shares its other arguments for good,
      because the world's type has parts that only borrow
      (tasks/MEMORY_MODEL.md, "Found after it").
    - The backend's "never parameter" failure for generic functions held
      in a record (worked around in Gdev's `application`).
    - The failing checks in Gdev's test modules that compile for the
      first time since the rules became one set; not looked at yet.
    - A name that borrowed from a local before a loop that updates the
      local does not give back to the version after the loop; and a
      borrowed value without a name holds the whole local, so a field
      cannot be given beside it (tasks/MEMORY_MODEL.md, "The generated
      encoders").
  - **Then:** delete `=`, `lent`, `migrate-stores` and
    `BLOT_REPORT_STORES`, and bring spec section 10.3 in line.
  - Tools: `python3 scripts/integration/count_stores.py DIR...` counts
    what is left; `python3 scripts/integration/harvest_stores.py
    PROJECT ENTRY...` converts what the compiler can already prove and
    puts back what a second check does not accept.
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
