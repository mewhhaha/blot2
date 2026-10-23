# Continue here

23 October 2026: the [compact symbolic journal](zig-native/SYMBOLIC_JOURNAL.md)
is qualified: 2,527 exhaustive native laws, 1,640 guest/client checks, exact
application output and a seven-pair CPU guard of 1.01083 (limit 1.05). A native
screen requested 43.8 MB less per fresh/edit/revert phase and reduced peak RSS.
The language task/channel batch is separate, still in progress and unqualified;
issues #25/#27 and the remaining task requirements stay open.

23 October 2026: [the completion plan](FINISH_PLAN.md) orders the preserved
local candidate, the remaining task records, and issue #25's remaining
language/runtime milestones. New issues #26 (numeric layouts) and #27
(application compilation/memory) share the representation and measurement work.
The plan records current state and exit criteria; it does not claim
implementation or qualification.

Current execution: the recovered compiler changes and bounded recursive numeric
Array/List storage pass the full gate: 2,525 exhaustive native tests, 1,640
guest/client checks and zero analyzer findings. Seven LLVM application pairs
pass fresh/edit/revert/restart equality and the 5% fresh-game CPU guard (1.013).
The [qualification record](zig-native/NUMERIC_QUALIFICATION.md) preserves raw
measurements, limitations and rejected experiments. The original dirty
`/workspace/blot2` checkout remains preserved; integration is in
`/workspace/.numeric-tuning`.

Pen cache bounds, artifact validation and profiling are pushed in `d8e0a2f`,
`67a4682` and `1b459b7`. All 24 whole-application startup checks pass. The large
headless peak belongs to Pen (about 2.5 GiB), with the compiler child below 320
MiB in this capture. Pen `b2f06cf` fixes scene discovery bypassing the validated
module cache: warm export falls from 3.440 to 0.169 seconds and from 2,471 to
105 MiB maximum RSS. All 341 files match across twelve exports; corrupted and
unavailable cache recovery preserve the same output. See
[Pen's measurements](https://github.com/mewhhaha/pen/blob/b2f06cf201cbc4dd1533b2cdb0477b2571b6386f/docs/compile-memory.md).

Issue #26 is closed after the verified `4091cb2` main push. Issues #25 and #27
and the remaining task requirements stay open. Task 086 closes as not needed:
the conservative constant-work estimate is 14.9% of later-edit CPU, below its
20% gate, and other inference and runtime-function reconstruction are larger.
The
[measured decision](zig-native/CONSTANT_REUSE.md#measurement-gate-resolved-23-october-2026)
preserves the paired runs, complete stacks and limitations. There are eleven
open task records. Continue with backend reconstruction/emission, non-constant
inference, bounded long edit sessions and issue #25's remaining contracts.

## Issue #25: minimal task/channel/control surface (22 October 2026)

This checkpoint's compiler revision is `e3e7463`. At that time the only open
GitHub issue was #25. The current one-result task slice implements `*(call)` and
`|handle|` inside a direct `@task.scope` callback. An ordinary
`const await = fn source => |source|` consumes a task handle and returns its
exact result through local aliases and renamed imports. The compiler freezes and
validates that helper's exact join body, specializes its erased handle layout,
and seals bottom-typed Wasm blocks after function exits (which repaired F32
returns). The full gate passed: 2,510 native laws in four exhaustive shards,
1,633 guest/client checks, release build and harness/smoke checks. Zig lint
found zero issues.

Issue #25 is **open**. Tuple collect/select, stream channels, scoped nonlocal
exits, purity proofs, worker transport and their benchmarks are not implemented.
The next boundary is helper propagation for task regions:

- `parse/parser.zig` binds `*call` to `task_group` and rewrites it immediately
  to `@task.spawn`; the parser only sets that group for a literal
  `@task.scope (fn group => ...)` callback. A helper that sparks work outside
  that literal syntax currently fails before type checking.
- `check/check.zig::taskApplication` requires a syntactic lambda for
  `@task.scope`, so `const scope = fn body => @task.scope body` reports
  `task_escape`.
  `const spawn = fn group => fn action => @task.spawn group
  action` also
  reports `task_escape` when its closure captures the group.
- The implementation must carry a validated, generative region contract through
  wrappers/imports and elaborate spark after checking that evidence. Do not
  recognize prelude names as keywords or weaken the existing escape diagnostics.
  Start with `scope`/`spawn` helper execution in both tiers and
  fresh/retained/imported checks, then tuple receive and the later stages in
  #25's stated order. Use the native Zig backend for development and the LLVM
  build only for release qualification.

The issue body revised at 19:59 UTC intentionally has only `*` and receiver bars
as new surface syntax; it excludes `tasks`, `async`, `finish`, `defer` and
`channel` block keywords. Keep `return` as function exit and `break value` as
the nearest `do` result. The untouched `/workspace/blot2` checkout is dirty;
work in the isolated `/workspace/.issue25-next` checkout or a fresh worktree
without overwriting it.

22 October 2026: the release build-cost follow-up is qualified on main. A single
non-inlined `CaptureScratch.deinit` owns `captureBody`'s partial lists; the
transfer and allocation-failure paths remain covered. The compiler-only LLVM
profile completes in 206.15 s on the separate pending candidate, with 199.00 s
in LLVM emission. On the isolated main source, the complete LLVM release build
including fixtures takes 255.10 s. The full gate passes in 754.63 s: 2,500
exhaustive native laws in four shards, 1,587 guest/client checks, 51 harness
checks and 48 smoke checks. Full Zig lint has zero findings. The recreated gdev
snapshot matches recorded Wasm for the game, devtools, largest test and all game
edit/revert phases. See
[development feedback](DEVELOPMENT_TURNAROUND.md#capturebody-release-build-follow-up-22-october-2026)
for exact scope and timing limits. The separate pending compiler candidate in
`/workspace/blot2` remains uncommitted and needs its own qualification.

## Compile-time hills and runtime track (handoff, 19 October 2026)

This section covers the compile-time program in
[COMPILE_HILLS.md](COMPILE_HILLS.md) (CT1–CT94, owner-approved, with ../gdev as
the benchmark) and the runtime issues #12–#16. The older tasks program continues
below it, unchanged.

### State

- All 94 hills have a dated Result bullet in COMPILE_HILLS.md. The current cloud
  milestone is local; its qualification is recorded below.
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

- **CT90 post-rebase qualification is complete.**
  - It reuses frozen modules when a shared session switches test entries (commit
    "CT90: Reuse frozen modules when the entry's closure changes"): suite CPU 96
    → 73 s, Wasm identical to fresh builds before the rebase.
  - It passed the gate and lint before being rebased onto `ba5decb`, where a
    `Session.deinit` conflict in `retained_revision.zig` was resolved by keeping
    both release lines. The owner had it merged as is.
  - Initial CT90 cloud validation passed the complete gate: release builds, all
    2,466 native laws, 1,552 guest/client checks and 33 harness tests. Zig lint
    and the paired benchmark on the owner-approved recreated snapshot also pass.
    No entry-switch implementation repair was needed.
  - CT92–CT94 guards and documentation are implemented and validated in the
    local milestone; see [compile guards](zig-native/COMPILE_GUARDS.md). Task
    024's fixed acceptance rows and task 053's fixed rows are complete; 047 is
    next.
  - CT91 is dropped (pen already runs 8 workers).

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

### Cloud continuation (19 October 2026, local milestone)

Qualified implementation commit: `e29dd0d2c6faa2ad16a39e4a06ef254cede3ff2c` on
local `main`. The later workload/Array qualification record is
`237a5065ecd8a5debc406ef77a79d4a489c37b9b`; native compiler inputs are
unchanged.

- Source `/workspace/.tools/activate.sh` before commands. Zig is 0.17.0, Deno
  2.9.6 and Rust 1.99.0. Heavy jobs use `/workspace/.tools/run-heavy.py`: a
  shared lock and a 14 GiB process-tree RSS watchdog. There is no systemd user
  bus. Scratch stays under ignored `build/`.
- The forced complete compiler gate passes **2,470 native laws executed, 1,556
  guest/client checks and 37 harness checks**. Native laws have zero skips,
  failures, leaks or logged errors. CI lint checks 507 source files plus the
  fixture module with zero findings; package dry run, editor grammar, example
  parses, Helix configuration, formatting and local documentation links pass.
  See [current qualification](zig-native/CLOUD_QUALIFICATION.md) and ignored
  `build/bench/iteration/run-cfd5c1f6733154b7/`.
- The gate now refuses Zig run-cache hits as native journal evidence. A miss in
  verified journal reuse forces execution. The timing report records source,
  toolchain-file, executable and log hashes inside the qualifying environment;
  the strict journal key still includes the whole environment. The earlier
  guest-passing cached run is retained as diagnostic history.
- Task **024** closes with declared field-principal admission and correct
  forwarding through qualified roots, complete allocation-failure laws,
  both-tier execution and fresh/retained/source/archive parity. Its eleven-row
  law map is in [body cutoff](zig-native/BODY_CUTOFF.md). The gdev
  body-admission and latency gaps remain with 093/102.
- Tasks **035, 067/068, 073/074, 075–080 and 105–107** also close against
  current evidence. Nested-array stress stays at 192 KiB; the 4,096-element
  small-object case commits 384 KiB with its class histogram explained. Staging
  costs have seven paired repetitions in both tiers and dependency modes. Ink's
  app-hooks pass 6,000 calls at flat 128 KiB guest memory. Deliberate language
  and ownership limits remain documented.
- Task **109** now closes with the recovered original issue repro and all four
  Ink probes measured against exact historical release sources. Required
  current/pinned ratios stay below 1.5, break writes scale linearly, and all
  60,480 calls preserve witnesses and warmed memory. See the
  [current Array qualification](zig-native/PERSISTENT_ROOTS.md#current-array-throughput-qualification-19-october-2026).
- Task **108** closes with the owner-approved recreated Ink callback probes: all
  1,854 result checks, both codegen tiers and retained/fresh/revert bytes pass.
  The exact pre-fix parent reports `effect_mismatch` for the pure stored
  callback cases. See [static captures](zig-native/STATIC_CAPTURE_ROWS.md).
- CT92–CT94 guards pass. The final strict comparison matches fresh, retained,
  restart and shared output for the game, devtools and selected slow tests.
  Seven pinned CPU pairs pass the 1.05 regression limit with median 0.941.
  Spreads are large; no speedup is claimed. The noisy failed identity control
  remains preserved in [compile guards](zig-native/COMPILE_GUARDS.md).
- The owner approved recreating the lost gdev freeze from current repositories:
  **583 files and 69 test entries**, at gdev `52fbc5af` and Ink `1a291a1b`. The
  active manifest/references are updated. The CT90 campaign compiled 68 tests
  successfully and retained one pre-existing protocol rejection: the match omits
  Ink's `SessionStarted` event. This is a compilation count, not executed
  passing game tests. gdev/Ink sources remain unchanged and private source stays
  ignored. Old absolute timings are not comparable to this freeze.
- GDB 16.3 and tree-sitter CLI 0.27.1 are installed locally. The profiler
  records compiler/harness hashes, one-worker phase/receipt data and per-thread
  CPU deltas; its ordinary stack report includes idle threads. Its smoke passes,
  but task 086's seven-pair constant-cost decision remains open.
- The published Codeberg network change is active: this running instance
  enforces revision 4, and Git can read the pinned Zig 0.17.0 tag. The local
  analyzer at `9a78ce1` and its compiler backend build with the supported
  `-Duse-llvm=true` host compiler option. Doctor confirms Zig 0.17.0 and a
  compatible backend. Local lint and the uncached final-source checks remain
  required for task 082. No source changes or benchmark evidence were pushed
  upstream.

### Task 053 qualified continuation, 20 October 2026

The qualified continuation is saved in local `709237c`, based on `8ff153a`; its
measured output hashes are separately saved in `ed3b0af`. The public-contract
follow-up below is qualified in `04e41ef`; the final catalog/package slice is
qualified in `4fda7c2`. Known opaque storage changes now retain ordinary
semantic callers while derived producers republish their physical recipes. The
wrapper matrix compares all private and exported machine bodies, executable
sections and allocation/ownership traffic; all 96 rows pass in development and
release screens.

The first full gate passes 2,476 native laws, 1,570 guest/client checks and 37
harness checks. Its release is `8a8cfb7c…`. A later negative control found that
circular foreign recipe assertions were admitted. The bounded positive-only
closure proof now rejects that forgery and passes original-producer, parameter
selector, shuffled-chain and allocation-failure controls. The repaired source
passes the new full gate and final analyzers below. The stopped pre-repair
compile campaign is diagnostic; no CPU guard is claimed from it.

The integrated continuation owns binding and nominal/constructor catalog maps,
rewrites unpublished caller copies and preserves original producer IDs. Private
binding/type insertion, movement and generic parameter alpha changes pass
focused native/OOM and both-tier source/archive/checkpoint/failed-edit controls,
including their combination with the closure-proof repair. Higher-rank,
usage/proof and complex public authority/catalog correspondence remain
conservative. Private-only effect/contract insertion and public effect parameter
alpha changes also pass the expanded focused controls; do not silently treat
unverified acceptance cases as complete.

Both analyzers and the activated local uncached checks pass 510 source files
plus the fixture module with zero findings. The first integrated gate stopped in
a harness startup race before release/native compilation. Its budget test now
waits for the SIGTERM-resistant descendant's readiness and checks the real timer
separately; that focused control passes. A later build was intentionally stopped
to finish the private-catalog and public-effect correspondence work. The
complete gate on the integrated source, `run-5ff7fbd61da7a31a` on 20 October,
passes **2,484 executed native laws, 1,574 guest/client checks and 37 harness
checks**. There are zero skipped native laws, failures, leaks or logged errors.
The release is `3f9c9275…`; its final 96-row wrapper matrix and five operation
pairs pass exact executable-section and allocation/ownership comparisons. The
pinned compile comparison passes fresh/retained/edit/revert/restart/shared
parity in three paired rounds. The seven-pair CPU guard passes (median ratio
0.979, limit 1.05; wide spreads, no speedup claim). A causal control that
restores only the old irrefutable-pattern path reproduces the original
baseline's bytes for every selected workload, explaining the intended output
changes.

A further row-3 screen confirms a remaining cutoff gap: an unchanged, unused
public contract before the opaque type makes a private insertion recheck both
callers (0/0 reuse, versus 1/1 without that contract). Fresh bytes and executed
results remain correct on that baseline. The follow-up now integrates owned
public-contract catalog and qualification-origin correspondence after passing
eight helper laws, full native allocation-failure sweeps and both-tier
source/archive/checkpoint/failed-edit controls for used and unused contracts.
Changed public predicates still revoke reuse. The complete gate now passes
**2,489 executed native laws, 1,578 guest/client checks and 37 harness checks**,
with zero native skips, failures, leaks or logged errors. Release `832ea709…`
also passes all 96 exact wrapper contexts and five operation comparisons. Its
first seven-pair CPU comparison failed (paired median 1.187, limit 1.05),
despite identical Wasm. The independent seven-pair identity control passes
(median 0.983), as does the preselected expanded 15-pair comparison on CPU 2
(median 1.021, limit 1.05). Individual ratios remain broad; the first failed run
is preserved and no speedup is claimed. All 162 strict compile-parity samples
and the separate fresh-edited controls pass, including restart and shared
sessions, without output waivers or hash changes. This public-contract slice is
qualified. At that checkpoint task 053 stayed open: the bounded used/unused
implementation-catalog probe still rechecks both callers (0/0 reuse); an
associated-method probe fails at its initial artifact publication and needs
diagnosis.

The final continuation qualifies those ordinary catalog cases. It matches
complete bounded public implementation/member recipes, original method
capability relationships and forwarded catalog zero, while getters keep symbolic
dispatch. The first full gate exposed a package getter compatibility failure.
Its targeted repair reconstructs the checked receiver and uses the existing
exact public member/scheme proof, including legacy and wrong-member,
wrong-receiver and physical payload-guess controls through complete OOM.

The repaired source passes **2,497 executed native laws, 1,585 guest/client
checks and 37 harness checks**, with zero native skips, failures, leaks or
logged errors. Both analyzers cover 511 source files and the fixture with zero
findings. Release `1b05518e…` passes all 96 exact wrapper contexts and five
operation comparisons. The preselected CPU-2 identity control and 15-pair
comparison pass (candidate paired median 0.998133, limit 1.05; broad
distributions, no speedup claim). All 162 strict compile samples and fourteen
fresh-edited controls pass, including restart/shared sessions, without output
waivers or hash writes.

The 176-observation/88-pair allocation campaign preserves exact Wasm and work;
all fourteen Session groups end at zero requested live bytes. Source and report
pins are in the
[final qualification](zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#final-task-053-qualification-20-october-2026).
Task **053** now closes against its fixed rows 1–13. The failed package gate and
previous noisy CPU screens remain preserved as history.

The standalone allocation campaign passes 68 observations: both tiers,
fresh/retained work, source-byte parity and zero live requested bytes after
teardown. Typical scalar work is 6 → 3 elaborations/lowerings; generic alpha is
7 → 4. Requested revision bytes fall, but retaining the previous accepted owner
raises the peak during publication. This is measured Session work with the
production SMP allocator, separate from release CPU qualification. Raw pins and
scope are in `build/bench/task053-cutoff-allocation/results.json`.

Continue with the
[053 law map](zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#task-053-continuation-19-october-2026-qualification-in-progress).
Local execution details and exact logs are in
`/workspace/.tools/task053-current-progress.md`. Preserve later work, use the
shared heavy-job runner, and keep this qualification as the next baseline. The
intended ordinary irrefutable-pattern output changes have a passing causal
control and separately recorded hashes; never waive unexpected differences or
the CPU guard.

### Open work, in suggested order

1. **Task program: 047, then the next ready tasks.**
   - The all-width cursor comparison is byte-exact but still exposes the
     performance gap; Window and broader generic state remain open. The new
     shared-path experiment is rejected. Its scoped directory successor passes
     focused laws and measures U32 cursor CPU ratios 0.223–0.267 at widths
     1/3/16. All 186 width/type/shape pairs pass against both rebuilt historical
     references and current std separately, with no cursor regression. Compiler
     cost, LLVM/full checks, Window and broader state remain open. Main remains
     unchanged pending qualification. See the
     [directory screen](zig-native/ITERATOR_STATE.md#scoped-directory-candidate-focused-checks-passed).
   - Keep 086's measured constant-work gate, 093's edit attribution and tasks
     100–104's targets open until their actual requirements pass.
2. **Follow-ups recorded under their hills:**
   - **CT28 (pen, owner approved):** use the development codegen tier for
     `pen dev`'s own Blot session. The Blot plugin already forwards that option;
     keep the generic plugin host's arbitrary settings scoped to its plugin.
   - **CT10:** binding-renumbering cutoff (design only).
   - **CT11:** hash-consed interfaces plus the Core type-table sharing
     difference.
   - **CT22:** the first edit after population re-optimizes 2,737 functions.
   - **CT26:** the body check cache admits none of robots.blot's 107 bodies
     (tasks 093/102).
   - **CT29:** a rejected population is still about 10% over pre-CT9, because of
     the dependency freeze.
   - **CT51:** summaries parametric in argument functions.
   - **CT56:** solver stores outliving region arenas.
   - **CT44, CT87, CT88:** parallel checking and inference; blockers recorded.
3. **Runtime:**
   - **R4:** the current pure pipeline/helper screen has zero allocation traffic
     in optimized code. Development code still uses 96 rounded bytes per loop
     iteration; direct curried calls use zero. Broader/effectful cases remain
     open. See the
     [current runtime screen](zig-native/CLOUD_QUALIFICATION.md#runtime-and-measurement-screens-20-october-2026).
   - **Diagnostic:** `fn - F32` reaches emit ("requires concrete representation
     evidence") instead of a checker type error at the operator; this remains
     reproduced in both tiers at `4fda7c2`.
   - **#12 deferred cases:** a closure bound to a local, generic callees,
     callees with `match`.
   - **Closure calls:** v128 values passed through closure calls still box once.
   - **#16 remainder:** about 125 K retains per frame at N=2048. See
     [zig-native/FRAME_MEMORY.md](zig-native/FRAME_MEMORY.md). Next step:
     measure the pointer-identity memo hit rate of the draw builders.
   - Copies from `x[i] := v` on an array the code doesn't own, and static
     constant Lists, still drop the acyclic flag.

### Waiting on the owner

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

Finish every task in the program. As of 23 October 2026:

- 99 are complete (including four designs);
- 11 remain open: 4 in progress and 7 pending.

The index in tasks/README.md is authoritative. Each task file carries its own
status, evidence and closed-acceptance rows.

The previous long handoff, with per-task evidence through 17 October, is in git:
`git show 48eda0a:CONTINUE.md`.

### Open tasks

- **In progress:** 047 (iterator state and cursor cost), 081 (final durable
  documentation), 082 (local analyzer backend and final-source checks), and 093
  (gdev edit gap).
- **Pending:** 084 (complete-program qualification), 100–104 (cold, literal,
  body, largest-region and requested-allocation targets), and 999 (conditional
  removal of tasks and PLAN.md).

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
