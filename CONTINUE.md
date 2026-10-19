# Continue here

## Compile-time hills and runtime track (handoff, 19 October 2026)

This section covers the compile-time program in
[COMPILE_HILLS.md](COMPILE_HILLS.md) (CT1–CT94, owner-approved, with ../gdev as
the benchmark) and the runtime issues #12–#16. The older tasks program continues
below it, unchanged.

### State

- Everything merged is on main and pushed. 91 hills have a dated Result bullet
  in COMPILE_HILLS.md (landed, dropped with numbers, or deferred with a design
  note).
- Landed highlights:
  - **Game:** cold build about 2.5 s → 2.3 s.
  - **Edits:** body edit 1.9 → 1.2 s, literal edit 1.4 → 1.0 s.
  - **Errors:** error edits 0.6–1.0 s → 12–48 ms.
  - **Restart:** unchanged restart 2.4 s → 20 ms; cache 57 → 20 MB.
  - **Tests:** suite 116 → about 95 s CPU; robot_pickup 19.5 → 5.4 s.
  - **Server:** serve-project peak RSS 810 → 472 MiB.
- Runtime:
  - **#12:** borrowed arrays.
  - **#13 and #14:** v128 SIMD, std/simd ops, wrappers at calls, v128 across
    private direct calls.
  - **#15:** measured and not material.
  - **#16:** the cycle collector skips proven data; proportional cadence;
    acyclic proof across units and through Array/List. The repro went from 68
    passes per frame to 0, about 10× faster at N=2048.

### Started but unfinished

- **CT90 is on branch `worktree-agent-acc90bd2852d65caf` (head `188506f`, also
  pushed to origin), not merged.**
  - It reuses frozen modules when a shared session switches test entries: suite
    CPU 96 → 73 s, Wasm identical to fresh builds.
  - It passed the gate and lint before its rebase onto `ba5decb`. After the
    rebase (a `Session.deinit` conflict), the gate, lint and a
    `bench:compile --shared-session` identity check must rerun before it lands.
  - CT91 is dropped on the same branch.

P1 (closed-label certificates) was measured but not started. Next step:

- Give `types.Store` a positive-only closed-row certificate per effect row,
  holding `closed_generation`, the physical epoch and the maximum argument
  height.
- `resolveOperationRow` and `closedRowHeight` return from it, with the same
  `TypeLimit` depth check.
- Rollback, `replaceListItem` and physical effect edits already bump the
  generation.
- Expected gain: about 6.6% self time of a cold game build
  (`check/types.zig:239`, `:1236`, `:1278`).

P2 (robot_pickup obligations), P3 (constructor memo for the `played` region) and
P4 (`namespaceEqual` in `reuse/principal_reuse_gate.zig`) aren't started.

### Open work, in suggested order

1. **O: CT92–CT94 (guards and docs).**
   - Reuse budgets in `compile_budget.test.ts`.
   - A paired timing guard in bench:compile.
   - Refresh the COMPILE_HILLS.md baseline, `zig-native/STATUS.md` and PLAN.md.
   - Also fix `bench:compile --restart-cache`, which prints "Wasm verification
     FAILED" for salt_hauling's expected restart rejection. No hash differs.
2. **Follow-ups recorded under their hills:**
   - **CT10:** binding-renumbering cutoff (design only).
   - **CT11:** hash-consed interfaces plus the Core type-table sharing
     difference.
   - **CT22:** the first edit after population re-optimizes 2,737 functions.
   - **CT26:** the body check cache admits none of robots.blot's 107 bodies
     (tasks 024/053).
   - **CT29:** a rejected population is still about 10% over pre-CT9, because of
     the dependency freeze.
   - **CT51:** summaries parametric in argument functions.
   - **CT56:** solver stores outliving region arenas.
   - **CT44, CT87, CT88:** parallel checking and inference; blockers recorded.
3. **Runtime:**
   - **R4:** pipelines into partial applications build a closure per call.
   - **Diagnostic:** `fn - F32` reaches emit ("requires concrete representation
     evidence") instead of a checker type error at the operator.
   - **#12 deferred cases:** a closure bound to a local, generic callees,
     callees with `match`.
   - **Closure calls:** v128 values passed through closure calls still box once.
   - **#16 remainder:** about 125 K retains per frame at N=2048. See
     [zig-native/FRAME_MEMORY.md](zig-native/FRAME_MEMORY.md). Next step:
     measure the pointer-identity memo hit rate of the draw builders.
   - Copies from `x[i] := v` on an array the code doesn't own, and static
     constant Lists, still drop the acyclic flag.

### Waiting on the owner

- **pen:** `pen dev` must pass `codegenTier: "development"` for its own session
  (CT28, in ../pen). CT90, once merged, needs no pen change: its workers already
  keep one session each.
- **Checkpoint cost:** a restart after an edit still pays about 250 ms for the
  checkpoint and reuses nothing from it. Gating or reshaping it is a design
  call.
- **GitHub:** whether to post results on issues #15 and #16. Never comment
  upstream without approval.

### How the work ran

- **Implementers:** at most 2 implementer agents at once, each in its own git
  worktree. The machine ran out of memory once with more.
- **Heavy jobs** (builds, `zig build`, the gate, benchmark loops) go through a
  shared lock with a memory cap:
  `flock <lock> systemd-run --user --scope -q -p MemoryMax=14G -p MemorySwapMax=2G -- <cmd>`.
- **Scratch:** big scratch goes in /var/tmp/blot2-ct-scratch/<group>/, never
  /tmp (a 16 GB RAM tmpfs).
- **Before merging**, run on the rebased tip:
  - the gate:
    `deno task test:compiler --budget-seconds 7200 --phase-seconds 5400`;
  - lint:
    `ZIG_ANALYZER=../zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`
    (0 findings);
  - Wasm identity: `deno task bench:compile`, comparing against main's build on
    the game, devtools and the slow tests.

  Then fast-forward main and push.
- **Intended output changes:** re-record the hashes with
  `bench:compile --allow-wasm-diff --write-hashes` in their own commit.
- **Measuring:**
  - Use instruction counts as well as CPU (CPU swings ±3% with layout).
  - Pin `codegenWorkers` when comparing binaries (serve-project defaults to 4).
  - Delete `build/bench/iteration/recent-failures.json` if it lists
    compile_budget.
- **Rules:**
  - No optimization may recognize prelude declaration names.
  - No tracing fallback, no pointer guesses.
  - ../gdev is private: commit only names, hashes and numbers from it, never
    sources.
  - Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Tasks program ([tasks/README.md](tasks/README.md))

Finish every task in the program. As of 19 October 2026:

- 80 are complete (including four designs);
- 30 remain open: 23 in progress and 7 pending.

The index in tasks/README.md is authoritative. Each task file carries its own
status, evidence and closed-acceptance rows.

The previous long handoff, with per-task evidence through 17 October, is in git:
`git show 48eda0a:CONTINUE.md`.

### Open tasks

- **In progress:**
  - **Cutoffs and constants:**
    - 024 (general body-interface cutoff; CT26 removed the obligation-span
      cause);
    - 053 (module cutoffs and wrapper erasure);
    - 086 (retain constant evaluation);
    - 093 (close the gdev edit gap).
  - **Runtime:**
    - 035 (remove the tracing runtime);
    - 047 (generic iterator state).
  - **Language:**
    - 067 and 068 (typed staging);
    - 073 and 074 (structured concurrency);
    - 105–109 (Ink-reported checker and runtime fixes; 109 is Array loop
      throughput).
  - **Restructuring:** 075–081 (evaluator, Core, checker and backend splits;
    fixtures; source tree; durable docs).
  - **Analyzer:** 082 (local analyzer workflow; rerun the analyzers after 084).
- **Pending:**
  - 084 (qualify the complete program);
  - 100–104 (the cold, literal-edit, body-edit, largest-region and allocation
    targets). CT results moved these numbers; re-pin them in 084;
  - 999 (remove tasks and PLAN.md).

### Owner decisions still in force

- **Language closures:**
  - 058/059/061/062/064/065 close against the fixed rows of
    `zig-native/LANGUAGE_QUALIFICATION.md`.
  - 067/068 close against the typed-staging acceptance traces.
  - 073/074 close against the structured-concurrency traces.
  - Forms outside those lists reject or decline, and are limitations, not open
    work.
- **Performance targets:** the five final targets live in 100–104. 084 re-pins a
  workload and records measurements.
- **035:** gated on running without crashes or memory exhaustion. The CPU
  comparison with tracing is informational.
- **082:** uses a local analyzer built from `../zig-analyzer`.
- **075:** doesn't depend on 001–074.
- **Retry demands:** only a demand parameter declared affine before
  instantiation moves captured owners (`demand_once`). Retry demands reject
  them. Recorded in `USAGE_CONTRACTS.md`.
- **Known limitation:** four retained/reuse laws overflow the stack only in
  `-Dllvm=false` builds; the LLVM gate passes them.
