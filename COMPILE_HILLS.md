# Compile-time hills

A program of 94 hills to cut the time Blot takes to compile, measured on the
gdev game. It follows the [twenty-hill program](PLAN.md#twenty-hill-program),
whose targets it keeps:

| Measure               | Target           |
| --------------------- | ---------------- |
| Cold build            | about 500 ms CPU |
| Retained literal edit | under 30 ms      |
| Retained body edit    | under 100 ms     |
| Allocation            | under 100 MB     |

Hills are numbered CT1–CT94 to keep them apart from PLAN.md's Hill 1–20. Each
lands as its own commit after `deno task test:compiler` and `deno task lint:zig`
pass, with emitted Wasm byte-identical to its baseline unless the hill says
otherwise.

## Baseline (17 October 2026, `3cf6de1`)

Release `blotc` (ReleaseFast) on a frozen copy of the current gdev:
`build/bench/gdev-snapshot`, re-frozen in `scripts/bench/gdev-manifest.json`. It
holds 130 source files and 1.09 MB of Blot, including the Ink library. That is
about 2.8 times the 394 KB workload behind the older 647 ms cold figure. Builds
go through `serve-project` with native assets, as pen runs them. CPU is from
per-thread schedstat on a Ryzen 3800X (8 cores, 16 threads). Cold figures are
medians of 5–7 runs with a spread of 1% or less; retained and restart figures
carry 8–25% load inflation.

| Entry                  | Cold CPU | Peak RSS |    Wasm |
| ---------------------- | -------: | -------: | ------: |
| `src/main.blot` (game) | 3,011 ms |  312 MiB | 1.84 MB |
| `devtools/main.blot`   | 1,051 ms |  137 MiB | 0.84 MB |
| Largest test entry     |   19.5 s |  619 MiB |  2.9 MB |
| All 55 test entries    |  167.5 s |          |         |

**Where cold game time goes:**

- **Backend generate:** 1,498 ms. Inference is 1,257 ms of it, constants 136 ms,
  layouts 36 ms.
- **Assemble and capture:** assemble is 198 ms and capture 81 ms.
- **Frontend (sampled):** check 26.5%, core lowering 7.5%,
  `freezeFromCheckedCore` 7.8%, load and parse 3.4%.
- **Wasm passes:** about 4%.

**Self time by kind:**

| Kind          | Share |
| ------------- | ----: |
| Checker       |   35% |
| Hashing       | 15.6% |
| memcpy/memset | 11.6% |
| Evaluator     |  7.4% |
| ArrayList     |  6.3% |
| Backend       |  6.2% |
| Allocator     |    4% |

**Counters:**

- **Instances:** 1,794 named and 563 closure instances.
- **Inference regions:** 5,888 regions with 52.8k scopes. The largest region
  (`game.blot:9829`) has 5,137 scopes and takes 262 ms.
- **Allocation:** 384 MB requested by the solver and scratch pools alone.

**Retained session (game):**

| Edit                                   |       CPU | Reuse                  |
| -------------------------------------- | --------: | ---------------------- |
| Trivia (comment, whitespace)           |     11 ms | output reused          |
| Literal in a function body             |     1.6 s | 1,492 of 1,794 reused  |
| Literal constant (`floor_half_extent`) |     2.4 s | none on the first edit |
| Body change                            | 1.8–2.9 s | none                   |
| Field added to a type                  |     2.5 s | none                   |
| Unused export added to `ink/math`      |     3.1 s | none, Wasm unchanged   |

Every non-trivia edit reports `rebuilt_seed=true`. A steady-state literal edit
is 87% backend, with constant serialization 31% and `prepareReuse` 12%. Retained
RSS grows from 312 to 630 MiB over an edit series.

**Restart and parallelism:**

- **Restart cache:** the restart cache loads but reuses no instance
  (`reused_named=0`). Restart therefore takes 4.0 s against 3.0 s cold, and its
  57 MB file is near the 64 MiB limit.
- **`--semantic-workers`:** one worker adds 27% CPU, and no worker count beats
  serial wall time.

## Order

| Phase                        | Hills     | Main target                     |
| ---------------------------- | --------- | ------------------------------- |
| 0. Measure                   | CT1–CT8   | Trustworthy, repeatable numbers |
| 1. Retained edits            | CT9–CT29  | Literal and body edit targets   |
| 2. Checker                   | CT30–CT44 | Cold build and test entries     |
| 3. Frontend validation       | CT45–CT49 | Cold build                      |
| 4. Inference                 | CT50–CT61 | Cold build and allocation       |
| 5. Backend                   | CT62–CT73 | Cold build and edits            |
| 6. Hashing, copying, memory  | CT74–CT81 | Everything                      |
| 7. Restart cache             | CT82–CT85 | Process restarts                |
| 8. Parallelism and test runs | CT86–CT91 | Wall time, test suite           |
| 9. Guards and docs           | CT92–CT94 | Keep the gains                  |

**First wave.** These are the cheapest hills with the largest measured evidence:

- **Measurement:** CT1 and CT2.
- **Reuse seeding:** CT9, the first edit's reuse seed.
- **Output cutoff:** CT10, the unchanged-output cutoff.
- **Checker:** CT30 (the instantiation pathology) and CT33 (`projectType`).
- **Restart:** CT82, the restart cache's reuse seed.
- **Backend scan:** CT63, the per-unit quantified-variable set.

Phases 2–6 can run in parallel with phase 1 once phase 0 lands. Phase 8's
inference parallelism waits on CT74, CT57 and CT88.

## Phase 0: measure

### CT1: make `bench:compile` run on the current gdev

`scripts/bench_compile.ts` hard-codes the old `{"gdev/": "packages"}` mapping.
Its fresh builds use the CLI, which cannot read native assets, and its retained
phases omit them.

- **Fix:** map `game/`, `pen/`, `test/` and `ink/`, as `pen.json` does. Build
  fresh and retained phases through `serve-project` with native assets. Include
  `ink/` and `test_support/` in the snapshot. Point the edit scenarios at
  current files.
- **Target:** paired runs on the re-frozen manifest with no Wasm difference
  between a binary and itself.
- **Result (18 October 2026):** CT1, "Run bench:compile on the current gdev
  through serve-project". Fresh, restart and retained phases use `serve-project`
  with pen.json's mappings and native asset roots (`scripts/bench/gdev.ts`); CPU
  is per-thread schedstat over the build with median and range; `--snapshot`
  selects the tree. Main's binary paired against itself, 5 runs at load 8.5–9.3:
  game 3,925 / 3,882 ms (ratio 0.989, ranges 3,799–4,230 and 3,827–4,450),
  devtools 1,325 / 1,359 ms (1.025), Wasm identical.

### CT2: frontend clocks

`serve-project` publishes backend clocks only, so the frontend split above comes
from sampling.

- **Fix:** add load, lex, parse, check, lower, freeze and validation clocks to
  `--profile` and to `serve-project` stats.
- **Target:** clocks that sum to within 5% of process CPU.
- **Result (18 October 2026):** CT2, "Clock every build phase under --profile
  and in serve-project stats". Exclusive thread-local phase scopes (assets,
  inputs, load, lex, parse, check, lower, freeze, validation, backend, other)
  publish as `phase_profile` / `phaseProfile`; unprofiled builds read no clock.
  Profiled game: check 975, lower 270, freeze 92, validation 215, backend 1,980
  ms, assets/load/lex/parse 58 ms; the named clocks cover 100.2–101.6% of child
  CPU (devtools 100.2–100.9%). Unprofiled, 5 pairs at load 7: game 3,818 / 3,832
  ms, devtools 1,350 / 1,265 ms, within noise; Wasm identical.

### CT3: allocation counters per phase

Only the solver and scratch pools count allocations.

- **Fix:** add requested bytes, allocation count and peak RSS per phase to the
  stats record. Reuse the counters that CT74 moves off the hot path.
- **Result (18 October 2026):** CT3, "Count requested bytes, allocations and
  peak RSS per phase". Profiled builds route the session allocator through a
  CountingAllocator that charges the active phase with relaxed atomics; nothing
  is inserted otherwise and `runtime/memory.zig` is untouched, so the counts
  survive CT74. Peak RSS is VmHWM sampled at phase changes (getrusage keeps the
  spawning process's RSS after exec). Game: 1,388 MiB in 3.91 M requests (check
  420 MiB / 2.42 M, backend 611 MiB, freeze 142 MiB, lower 99 MiB); peak 306
  MiB, raised by check 121, freeze 62, backend 60 and lower 38 MiB. Profiled CPU
  +0.7% against CT2.

### CT4: a committed sampler

The baseline used a gdb sampler: random 3–10 ms SIGUSR1 stops, inlined frames,
with PR_SET_PTRACER set for yama.

- **Fix:** commit it with its aggregator under `scripts/bench/`, so any hill can
  attach self, inclusive and subsystem tables.
- **Result (18 October 2026):** CT4, "Commit the gdb stack sampler as deno task
  profile:compile". `scripts/bench/gdb_sampler.py` runs inside gdb;
  `scripts/bench/profile_compile.ts` opens the workload behind a generated
  PR_SET_PTRACER wrapper and samples cold builds, `--edit` scenarios or `--test`
  entries, then prints self, inclusive, subsystem, owning directory, file, line
  and memcpy/hash/allocator caller tables (`--aggregate` re-reads samples). One
  cold game run: 476 samples, `projectType` 5.3% self, check 35% of leaf time,
  hash maps 12%, memcpy/memset 11%, as in the baseline.

### CT5: an edit-scenario suite

- **Fix:** fix the retained scenarios: trivia, literal constant, literal in a
  body, body change, type change, a body in a widely imported module, and an
  unused export. Report CPU together with `reused_named`/`fresh_named` and the
  recheck counters.
- **Target:** reuse counts asserted in `compile_budget.test.ts`, never times.
- **Result (18 October 2026):** CT5, "Run the retained edit suite and budget its
  reuse counts". The game session runs all seven scenarios with edit and revert
  and prints reuse, seed, output, revalidation and recheck counters. A miniature
  public suite (`editSuite` in `scripts/bench/corpus.ts`) is pinned as
  `retainedToday` upper bounds in `compile_budget.test.ts`. Game, one session:
  the first literal-constant edit reuses 0 of 1,794 and revalidates 14 modules
  (its revert reuses 1,501 and revalidates 1); body, type, ink/math body and
  unused-export edits reuse nothing (2.6–3.3 s); recheck counters stay 0. The
  miniature suite reuses 8 of 10 on its first literal edit, so it does not
  reproduce that first-edit loss.

### CT6: a test-suite metric

The 55 test entries take 167.5 s CPU, and their frontend is 94–99% of that.

- **Fix:** track total and per-entry CPU, and the slowest ten entries, as a
  bench workload.
- **Separate:** `tests/salt_hauling.blot` fails with `type_mismatch` in the
  snapshot; triage it separately.
- **Result (18 October 2026):** CT6, "Measure the gdev test suite as a bench
  workload". `--workload tests` builds all 56 entries as pen does (the
  `src/test_fixture.blot` overlay), records rejections instead of aborting, and
  prints the suite total and the ten slowest entries. Base/candidate, one run at
  load 5.5–8.8: 211.3 / 208.9 s; slowest `robot_pickup` 27.3 / 24.8 s, `edit`
  15.2 / 13.9 s, `game` 13.3 / 13.2 s. Wasm identical on all 55 built entries.
  `salt_hauling` is a stale test, not a compiler bug: it calls `station.layout`
  with 3 of its 5 curried parameters (`index` and `seconds` were added), so the
  `case` scrutinee is a function and the `#Some shape` arm is a type mismatch.

### CT7: a byte-identity guard

- **Fix:** every hill's paired run fails on a Wasm difference unless the hill
  declares one. Record the baseline hashes per entry beside the manifest.
- **Result (18 October 2026):** CT7, "Guard gdev Wasm with recorded per-entry
  hashes". `scripts/bench/gdev-wasm.json` holds the snapshot manifest's hash and
  65 entries (game, devtools, the game's seven edited sources and the 56 test
  entries, `salt_hauling` as `failure:type_mismatch`), recorded from main's
  release binary. A run fails when either binary differs from a recorded entry;
  `--allow-wasm-diff` permits a declared change and `--write-hashes` re-records
  it. Rejections and parity failures are never excused. A self-paired run passes
  ("gdev = recorded hashes"); an altered devtools hash exits 1, and 0 with
  `--allow-wasm-diff`.

### CT8: record the baseline

- **Fix:** move this baseline into `zig-native/STATUS.md` and PLAN.md's
  measuring section. Retire the 647 ms and 150 ms figures, which describe the
  older workload.
- **Result (18 October 2026):** CT8, "Record the gdev compile-time baseline in
  STATUS.md and PLAN.md". `zig-native/STATUS.md` gains a compile-time baseline
  section (cold, test-suite and retained figures, the phase clock and allocation
  split, the bench workflow); PLAN.md's measuring section describes the new
  harness and baseline. Both, and `tasks/README.md`, mark the 647 ms cold and
  150 ms first-edit figures as the retired 394 KB workload.

## Phase 1: retained edits

### CT9: seed reuse on population

The first edit after population reuses nothing (`rebuilt_seed=true`,
`reused_named=0`). A revert reuses 1,501 instances.

- **Fix:** record the populated revision as a reuse seed.
- **Target:** the first literal edit matches the steady-state reuse.
- **Result (18 October 2026):** CT9, "Seed the first edit from population and
  check the entry once". Population checked `robots.blot` against live
  dependencies and every edit against frozen interfaces; published capability
  collections copied shared recipe nodes in the producer's order, so the two
  differed and the first edit re-checked 14 modules and lost the reuse gate.
  Collections are now built children-first. Population also checked the entry
  twice (within the project, then as the seed's consumer); it now defers it from
  the first check. Game, 5 pairs at load 1.1–1.5: first literal_constant edit
  1,877 → 1,359 ms (0.724), reused 0 → 1,498 of 1,794, revalidated 14 → 1; fresh
  2,567 → 2,519 ms (0.981); other phases unchanged. Test entries, 5 pairs:
  robot_pickup 7,600 → 5,439 ms (0.716), edit 6,857 → 5,291 ms (0.772);
  robot_pickup 71.71 → 51.37 G instructions. All 56 entries, one run with CT12:
  116.3 → 101.4 s (0.872). A rejected population now checks the entry against
  both the frozen and the live dependencies (stale `salt_hauling` 2.0 → 3.6 s).
  Wasm identical.

### CT10: cut off unchanged output

Adding an unused export to `ink/math` leaves the Wasm unchanged but costs 3.1 s.

- **Fix:** compare each edited module's checked interface and lowered Core with
  the previous revision's. When neither changes for any consumer, stop before
  the backend.
- **Target:** an interface-neutral edit under 30 ms.
- **Result (18 October 2026):** deferred; larger than described. The unused
  export is inserted mid-module, so every later declaration of `ink/math`
  changes its binding ID (its interface's capability roots move from binding 41
  to 42), the new spelling grows the namespace, and all 76 importers re-check
  and lower new Core. No module's interface or Core is unchanged, so stopping
  before the backend needs comparison of the reachable program modulo binding
  IDs and unreferenced spellings, which the reuse gate deliberately declines
  today ("ID movement conservatively rebuilds code").

### CT11: interface early cutoff for importers

A body or literal edit in `ink/math` (71 importers) reuses nothing.

- **Fix:** invalidate importers by interface hash, not by module identity.
  Re-emit only the instances that inline or evaluate the edited body.
- **Result (18 October 2026):** no separate change. Importers are already cut
  off by interface comparison (`module_frontend_cutoff`): a steady-state
  `Quat.dot` body edit re-checks only `ink/math`. Its instances were then lost
  to the gate's associated-candidate rule, which CT12 replaces: the revert
  reuses 1,429 of 1,794 (1,695 → 1,524 ms). The first `ink/math` edit after
  population still re-checks 76 modules: the checker publishes input-function
  capability recipes for every eligible declaration when the module's type store
  holds a scoped type, and a live-checked `ink/math` copies such nodes from its
  imports while a check against frozen interfaces does not, so `Color.lerp` and
  `Quat.conjugate` carry recipes only at population. That difference in
  `check.zig` also makes retained interfaces differ from cold ones; it belongs
  to the checker hills.
- **Result, capability facts (18 October 2026):** CT11, "Take a catalog
  member's capability facts from its producer". The recipes did not come from
  scoped types: `ink/math` imports the prelude's F32 members through
  `std/vector`'s catalog, as aliases. A live alias carries its producer's flow
  and recipe, but a frozen interface strips both from aliases, so a check
  against frozen dependencies could not derive recipes for `Color.lerp` and
  `Quat.conjugate`, and retained and cold builds published different
  interfaces. A catalog member now takes its capability facts from its
  producer, live or frozen; a law checks that the re-exporting consumer
  publishes identical flows and recipes at population, after an edit and in a
  cold build. The first `ink/math` edit still re-checks the 76 importers
  (2,459 → 2,470 ms): its interface also differs in type-graph sharing, since
  replayed body facts give `Mat4.view`'s inferred result its own `Mat4` node
  where fresh elaboration shares the constructor's. Hash-consing projected
  interface graphs, or comparing them modulo sharing, would remove that.
  Wasm identical.

### CT12: instance-level dependencies

Body edits reuse nothing, even in a module with one changed body.

- **Fix:** record, per emitted instance, the bodies, constants and layouts it
  read. Rebuild only the instances whose inputs changed.
- **Target:** a body edit under 100 ms with output identical to a fresh build.
- **Result (18 October 2026):** CT12, "Invalidate only the declarations that may
  select an edited member". Per-instance body and value admission already
  existed; what discarded everything was the gate's rule that any dirty
  associated candidate disables reuse for the program, since receiver syntax,
  operators and `from` select by type through no named reference. The gate now
  dirties the declarations whose bodies may resolve the candidate's member name
  or operator (recipe members plus projected and updated fields, which recipes
  omit, and every obligation) and their readers. Game, 5 pairs at load 1.0–1.5:
  body_change edit 2,114 → 1,901 ms (0.899), revert 2,060 → 1,911 ms, reused 0 →
  1,434 of 1,794; steady-state ink/math body edit 1,695 → 1,524 ms, reused 0 →
  1,429; session instructions 101.9 → 97.1 G. Backend generate stays about 1.16
  s with 80% of instances reused, so the 100 ms target needs CT13 onward. Wasm
  identical.

### CT13: incremental constant serialization

Constant serialization is 31% of a literal edit.

- **Fix:** keep serialized static data per constant, keyed by the constant's
  value and layout. Re-serialize only the constants whose value changed.
- **Overlaps:** task 086.
- **Result (18 October 2026):** dropped; serialization is no longer the cost.
  Sampled over 16 literal edits after CT9–CT12, `Generator.constant` is 34.7%
  inclusive but 0.43% outside the closures and callables it reaches: closure
  specialization 12.6%, fresh callable generation 16.8% and closure functions
  4.9%. Retained aggregates are already replayed by value graph (684 per
  edit); their cost is admission, the old graph inspection and value match in
  `aggregateConstantRequest` (8.5%), whose correspondence the caller's
  relocated operands need.

### CT14: cheaper `prepareReuse`

`prepareReuse` is 12% of a literal edit.

- **Fix:** index the previous revision's instances by key instead of scanning
  them, and skip modules whose stamps match.
- **Result (18 October 2026):** CT14, "Certify retained pins by an identical
  certificate context". Sampled after CT15, `prepareReuse` is 11.3% of a
  literal edit: 6.6% frozen-Core validation of every module twice (the old
  pins and the current modules), 3.7% module stamps (CT18), no instance scan
  and 0.1% `dirtySelections` even on a body edit. gdev's capability recipes,
  scoped types and staging make the validation context non-reusable, so the
  previous edit's certificate never matched. A certificate whose every module
  image equals its retained pin, under the same namespace and bounds, was
  captured for exactly this context and now certifies the pins; current
  modules are still validated. Game, 5 pairs at load 1.1–2.2: revert of
  literal_constant 1,161 → 1,098 ms (10.86 → 10.40 G instructions),
  literal_in_body edit 1,155 → 1,089 ms, body_change 1,782 → 1,713 ms; the
  first edit after population has no certificate yet. Wasm identical.

### CT15: cache `source_value_template.moduleGenerative`

It is 2.7% self in a literal edit and recomputed per revision.

- **Fix:** cache it per module stamp.
- **Result (18 October 2026):** CT15, "Share unit facts with private
  evaluator sessions". The scans came from `Session.init` in the 64
  independent call-proof rechecks of each edit, each rescanning every module
  (3.5% of a literal edit, plus offsets and field-location hashing). Private
  sessions (`initShared`: those rechecks and semantic component jobs) now copy
  the parent session's unit facts over the same units. Game, 5 pairs at load
  1.7: literal_constant edit 1,389 → 1,316 ms (12.83 → 12.49 G instructions),
  literal_in_body 1,319 → 1,253 ms, body_change 1,947 → 1,899 ms; population
  unchanged. Wasm identical.

### CT16: index `artifact_import` lookups

`knownRow` and `knownLayout` are 1.7% and 1.3% self in a literal edit.

- **Fix:** replace their scans with hash indexes built once per artifact.
- **Result (18 October 2026):** CT16, "Memoize known layout ceilings per
  layout store". The two were an unmemoized recursive walk over shared layout
  DAGs (7.5% of a literal edit with callers). `artifact_import.Knowledge` keeps
  each node's and row's ceiling, the deepest level at which it is still known,
  computed once per append-only store without recursion; known(id, 0) is then a
  lookup. Game, 5 pairs at load 1.1–2.2: literal_constant edit 1,306 → 1,218
  ms (12.49 → 11.26 G instructions), literal_in_body 1,247 → 1,159 ms,
  body_change 1,871 → 1,790 ms (17.62 → 16.40 G); population unchanged. Wasm
  identical.

### CT17: interval index for fragment admission

`artifact_fragment.State.admit` (1.1% self) scans emission records per address
(`reuse/artifact_fragment.zig:288-300`).

- **Fix:** use an interval index.
- **Result (18 October 2026):** CT17, "Follow skipped aggregate ranges with
  one cursor during admission". The per-address scan (`localAddress`) is
  negligible now; the self time was `admit` testing every emission record
  against every skipped aggregate child. Those ranges are disjoint and
  ascending, so one cursor follows them and a binary search passes over each
  child's records. Game, 5 pairs: literal_constant edit 11.26 → 11.18 G
  instructions (1,218 → 1,214 ms, within CPU noise), body_change 16.40 →
  16.33 G. Wasm identical.

### CT18: generation tokens instead of module stamps

`ModuleStamps` re-hashes and compares every retained module's Core per edit,
about 39 ms (`zig-native/RETAINED_EDIT_COST.md`). Its `owns()` and entry scans
are linear (`reuse/code_artifacts.zig:665-730`).

- **Fix:** issue tokens at freeze time and keep the integrity check as an opt-in
  validation. The current design is a documented decision, so this needs the
  owner.
- **Overlaps:** tasks 093 and 101.
- **Result (18 October 2026):** CT18, "Pin retained Core by generation token".
  Approved by the owner. Sampled before, stamps were 5.3% of a literal edit
  (the importer re-hashed every retained module). A pin now carries a token,
  issued once when its Core image is first pinned, and the header it pinned; it
  holds while its module names those buffers. A view inherits a token only from
  the same buffers or from complete content equality (the existing `proveSame`
  comparison), so a changed module never keeps one. Certificates compare tokens.
  `validate_pins` keeps the digest check opt-in; checkpoints store digests,
  never tokens, and restored pins validate them once. `owns()` is a range check.
  Laws: token memo (copies, every change kind, storage, unowned views, threads,
  allocation failure), admission (in-place change caught only by validation,
  header change and forged token always), identical decisions with and without
  validation over an edit series, checkpoint restore, and a retained revision
  under allocation failure. Game, 5 pairs at load 1.1–2.0: −0.70 G instructions
  per build; literal_constant revert 1,027 → 969 ms (9.90 → 9.21 G),
  literal_in_body revert 1,043 → 983 ms, body_change revert 1,647 → 1,584 ms,
  population 2,491 → 2,425 ms. Every deterministic stat equal to the previous
  build, and to a validating build over a 42-build mixed series. Wasm identical.

### CT19: cheaper revision input snapshots

`Snapshot.get` and `resolve` scan strings per import edge
(`reuse/revision_inputs.zig:192-194, 244-250`). Each revision realpaths, reads
and double-hashes every input.

- **Fix:** add hash maps and a stat cache, and accept the client's changed set
  through the existing overlays.
- **Result (18 October 2026):** CT19, "Index revision input observations and
  digest each source once". Sampled after CT18, revision inputs were 0.6% of a
  literal edit: the import-resolution scan 0.2%, realpath 0.16%, the trivia
  re-lex 0.12% and the double source digest 0.09%. A snapshot now indexes its
  path, file and import observations (positions in the same lists, so frozen
  records and their scans are unchanged) and memoizes each source's digest for
  admission and module reuse. Law: every observation's index equals its list
  position, repeats read and resolve nothing, under an allocation-failure sweep.
  Game, 5 pairs at load 1.2: −20 M instructions per edit (literal_constant
  revert 9.205 → 9.185 G, 971 → 962 ms), trivia revert 62 → 43 M instructions
  (10 → 9 ms). Input counters and Wasm identical. No stat cache: skipping reads
  by mtime is unsound for same-size edits within a timestamp tick, reads cost
  0.05%, and the protocol does not promise that overlays list every change.

### CT20: worklists for dirty propagation

The principal gate re-scans all bindings until nothing changes
(`reuse/principal_reuse_gate.zig:236-262`), and importer invalidation uses the
same fixpoint (`reuse/revision_inputs.zig:459-475`).

- **Fix:** use reverse-dependency worklists seeded by the changed modules.

### CT21: append-only pools

Pool leases memcmp every pool and recopy grown ones
(`eval/pool_leases.zig:108-114`, `reuse/code_artifacts.zig:844-915`).

- **Fix:** use chunked pools that share an unchanged prefix.
- **Overlaps:** task 021.

### CT22: reuse encoded functions

Final encoding re-encodes every function per edit
(`backend/wasm.zig:1262-1288`). `Capture` deep-clones every input and output,
even reused ones (`backend/optimized_bodies.zig:99-117`, `wasm.zig:1067`).

- **Fix:** keep encoded bytes and refcounted captures for matcher-reused
  functions.
- **Result (18 October 2026):** CT22, "Count positional optimizer matching
  apart from the relocation budget". Encoding is about 1% of a literal edit
  and capture cloning 0.07%; the cost was functions the optimizer redid. The
  matcher's 1 M walk budget was spent by the positional checks alone (622 k to
  prepare positions on gdev's 3,541 functions), so even an unchanged position
  stopped matching part way. Positional checks are linear and now keep their
  own count. Game, 5 pairs at load 1.2–1.7: positional reuse on a
  literal_constant revert 2,602 → 3,538 of 3,541; revert 1,097 → 1,037 ms
  (10.43 → 9.93 G instructions), literal_in_body revert 1,102 → 1,047 ms,
  body_change revert 1,717 → 1,663 ms. Edits that move positions are
  unchanged: relocation walks fail on genuinely different bodies (9,164 of
  9,168 on the first edit, where population's bodies differ from retained
  ones), so a memo of proved callee pairs was tried and dropped. Wasm
  identical.

### CT23: persist lifetime summaries

`Summaries.prepare` scans every function at session start
(`backend/runtime_pipeline.zig:96`), including reused ones.

- **Fix:** carry summaries across revisions in a deterministic order.
- **Result (18 October 2026):** dropped. `Summaries.prepare` is 0.74% of a
  literal edit and 0.54% of a body edit (about 10 ms), under what one build
  can attribute. Summaries are inputs to the optimizer matcher, so reusing
  them would need a proof of their own, and a recursive or depth-limited
  summary depends on the order functions are visited, which an insertion
  changes.

### CT24: reply before persisting

The project server persists its checkpoint before replying on revision 1
(`reuse/zig_project_server.zig:367`).

- **Fix:** reply first, then persist.

### CT25: bound retained memory

Retained RSS doubles over an edit series (312 to 630 MiB).

- **Fix:** release superseded revisions' pools, captures and checkpoints once no
  lease holds them.
- **Target:** flat RSS over 50 alternating edits.
- **Result (18 October 2026):** CT25, "Give serve-project one heap of size-class
  free lists". Nothing retained accumulates: a site-tracking allocator showed
  live bytes repeating exactly (171.5 or 202.5 MiB) over a 72-build mixed series
  of the seven scenarios, while RSS grew 312 → 640 MiB. std's SmpAllocator moves
  a thread to the next per-thread slot whenever its slot has no free block of a
  class, stranding the blocks freed there; the one compile thread cycled through
  all 16 slots. `runtime/session_heap.zig` keeps one set of size-class free
  lists for the process (large blocks still map and unmap directly). Same
  series: RSS 273 → 270–303 MiB, flat after the first cycle; peak 810 → 472 MiB;
  population 259 → 232 MiB. Game, 5 pairs at load 1.3: instructions −0.07% to
  −0.26%, CPU population 2,508 → 2,489 ms, literal_constant revert 1,014 → 1,029
  ms, body_change revert 1,622 → 1,641 ms (within layout noise). Wasm identical.

### CT26: per-body recheck cutoff

Every body of an edited module is rechecked.

- **Overlaps:** tasks 024 and 102, and `zig-native/BODY_CUTOFF.md` (remaining
  scope).
- **Target:** only edited bodies and their dependents recheck.

### CT27: wider inference receipts

Receipt admission is per declaration and requires exact projections.

- **Fix:** admit consumers whose interface did not change.
- **Overlaps:** tasks 023, 088 and 093.

### CT28: a development codegen tier for `pen dev`

A `development` tier exists (`backend/compilation_tier.zig`) and skips five of
the seven optimization passes, but it is not the default.

- **Decision:** whether the edit loop uses it. The output differs, so this is a
  product decision for the owner.

### CT29: cheaper edits with errors

A diagnostic after a speculative local recompiles the whole program, and a
constant-receipt retry compiles again
(`backend/core_backend.zig:2294-2320, 2742-2764`).

- **Fix:** roll back only the speculated local.
- **Target:** an edit with an error costs no more than one compile.

## Phase 2: checker

### CT30: instantiate schemes once per use site

One test entry takes 19.5 s, 99% of it in check. 70% of its samples are self
time in `check/types.zig` (`substituteWithRows`, `substituteDepth`, `dataKind`),
reached from `Engine.appendInstance` (`check/check.zig:9822`) through
`expandUse`, `resolveUse` and `attemptPending`.

- **Fix:** memoize the instantiation of each scheme obligation per use.
- **Target:** that entry under 3.5 s, in line with entries of the same backend
  size.
- **Result (18 October 2026):** commit "CT30: prepare one substitution per
  scheme instance". Expanding a shared use substituted each obligation with a
  kind check per binder per call and a binder scan per node. One prepared
  substitution per instance now checks the kinds once and indexes long binder
  lists; every root is copied exactly as before. Five round-robin runs at load
  4–6, Wasm identical: robot_pickup 24.0 → 13.0 s, edit 13.2 → 10.9 s,
  tests/game 11.7 → 10.9 s, interface_station 10.2 → 9.7 s, salt_clicks 9.9 →
  7.9 s; the game entry is unchanged within noise. Substitution falls from 60%
  to 8% of robot_pickup samples. The 3.5 s target is not reached, for two
  structural reasons. Each of seven tests expands `carried` (48,500 obligations,
  1,058 binders) in full: 46,447 of those obligations are residual
  `effect_operation`s that stay unsolved, so the callee memo never records, and
  they are copies of only 107 distinct closed operations that snowball through
  `step` and `sized`. Deduplicating them would change scheme obligations and
  needs a design decision. Population also checks the entry module twice (full
  project, then the frozen-seed consumer).

### CT31: memoize substitution

- **Fix:** cache `substituteWithRows` results by (type, substitution id) inside
  one check, and skip closed subtrees using a closed-height bit.
- **Result (18 October 2026):** dropped. Sharing a memo across the roots of one
  substitution, or returning closed subtrees uncopied, changes which type nodes
  the checker creates and therefore the published Core (comparable through
  `.blotdep` files), which phase 2 keeps identical. After CT30 the remaining
  copying is 8% of robot_pickup samples and absent from the game profile.

### CT32: cache `dataKind`

- **Fix:** store the data kind on interned type nodes instead of recomputing it
  per query.
- **Result (18 October 2026):** dropped. `dataKind` was hot only through the
  substitution checks that CT30 removed; it is 2 of 2,410 cold game samples and
  absent from robot_pickup's profile after CT30.

### CT33: index nominal projections

`core_builder.Builder.projectType` scans every emitted type node for each
nullary nominal (`check/core_builder.zig:385-391`). It is 5.2% self cold (about
160 ms) and 29% self in some test entries.

- **Fix:** keep a map from nominal to type node.
- **Result (18 October 2026):** commit "CT33: index argument-free nominal type
  nodes in lowering". Five round-robin runs after CT30, load 4–6: game entry
  3,910 → 3,667 ms (3,782 before CT30), robot_pickup 13.0 → 10.1 s, edit 10.9 →
  8.9 s, tests/game 10.9 → 8.9 s, interface_station 9.7 → 8.1 s, salt_clicks 7.9
  → 7.2 s.

### CT34: `epoch_resolution_cache.Cache.get`

It is 9–12% self in test entries (`reuse/epoch_resolution_cache.zig:36-45`).

- **Fix:** measure probe lengths, then fix the key distribution or the table
  layout.
- **Result (18 October 2026):** dropped. Probe lengths are short: 25M lookups on
  robot_pickup averaged 1.83 probes, but tables kept the length of their busiest
  epoch (277k entries on average) and missed 88% of lookups. Shrinking tables
  after quiet epochs (above 1,024 entries) measured no gain in eight game and
  four test rounds at load 1: game 2,879 → 2,859 ms, robot_pickup 8,161 → 8,257
  ms, edit 7,498 → 7,513 ms, interface_station 7,001 → 7,073 ms. It also added
  5.6 MB of requested solver memory.

### CT35: the resolve family

`resolveOperationRow`, `resolveNode`, `resolveDepth`, `resolve`, `closedHeight`
and `closedRowHeight` together take about 11% self.

- **Fix:** add path compression for resolved variables, cache heights on nodes,
  and resolve operation rows once per interned row.
- **Result (18 October 2026):** dropped. Recording rows whose labels resolve
  closed, keyed by the closed generation with the tallest argument for the depth
  bound, measured 2,875 → 2,860 ms on the game and 8,349 → 8,391 ms on
  robot_pickup at load 1. A per-store record added 15 MB of requested solver
  memory; an inline 128-slot variant measured the same. Path compression was not
  tried: resolution must keep its chronological views.

### CT36: cheaper structural type equality

`equalGraph` and its pair map take about 2% self.

- **Fix:** hash-cons closed types so their equality is an id compare, and use a
  small inline pair buffer before falling back to the map.
- **Result (18 October 2026):** commit "CT36: keep small equality visits in an
  inline list". Symbolic equality recorded every visited pair in a hash map; the
  first sixteen pairs now stay in an inline list. Eight game and four test
  rounds after CT33, load 1.1, Wasm identical: game 2,848 → 2,715 ms,
  robot_pickup 8,118 → 7,779 ms, edit 7,461 → 7,073 ms, tests/game 7,400 → 7,194
  ms, interface_station 6,965 → 6,654 ms, salt_clicks 5,913 → 5,593 ms;
  requested memory is unchanged. Hash-consing closed types was not done: it
  would change which type nodes exist and therefore the published Core.

### CT37: cheaper operation interning

`internResolvedOperation`, `internOperationInstance` and its hashed form take
about 2.5% self.

- **Fix:** precompute operation hashes and avoid the memcpy that
  `effect_evidence.internOperationInstance` performs.
- **Result (18 October 2026):** dropped. Grouping interned operations by
  identity and instance, in stores above 32 operations, removed the scan but
  measured 2,859 → 2,875 ms on the game and 8,257 → 8,349 ms on robot_pickup at
  load 1, and added 84k allocations and 28 MB of requested solver memory. The
  `effect_evidence` interning is reached from inference projection (CT60).

### CT38: checker linear scans

`progressConstructor` (`check/check.zig:12555`), `implementationIndexForMember`
(:2856) and the duplicate-implementation check (:2599) scan linearly.

- **Fix:** index them.
- **Result (18 October 2026):** dropped. The three listed sites draw no samples
  in 2,410 cold game samples or 1,500 test-entry samples.

### CT39: index named imports

Named imports cost bindings times exports (`reuse/project_check.zig:447-470`).

- **Fix:** index exports by name.
- **Result (18 October 2026):** dropped. The bindings-by-exports loop draws 5 of
  2,410 cold game samples (0.2%).

### CT40: lowering linear scans

The `dictionary_uses` (`check/core_builder.zig:1120, 1194`) and
`member_templates` (:2859, :2906) lookups scan linearly.

- **Fix:** use maps.
- **Result (18 October 2026):** dropped. The `dictionary_uses` and
  `member_templates` scans draw 1 of 2,410 cold game samples.

### CT41: a single-pass lexer

The lexer makes four passes and reserves no token capacity
(`parse/lexer.zig:517-529`).

- **Fix:** fuse the passes and reserve from the source length.
- **Result (18 October 2026):** dropped. Lexing is 0.8% of a cold game build. A
  microbenchmark over all 226 gdev and std files (2.07 MB) takes 40.0 ms per
  round: validate 3.3, scan 21.0, layout 13.4 and contextual 2.6 ms. Reserving
  token and line capacity plus an ASCII fast path measured 38.9 ms, within run
  noise, and fusing passes cannot remove the scan and layout work that
  dominates.

### CT42: parallel lowering per unit

Lowering is serial (`main.zig:403-413`), but `lowerWithOrigins` takes only const
inputs.

- **Fix:** lower units on workers and merge diagnostics in source order.
- **Result (18 October 2026):** "CT42: Lower fresh units on semantic workers".
  With `--semantic-workers` above 1, `check/parallel_lowering.zig` lowers the
  fresh units of dependency freezing, project preparation and the CLI on
  workers, largest first; the serial loops take them in unit order, so
  diagnostics, errors and ownership do not change. Wasm identical on the game,
  devtools and the 10 slowest tests. Game with 4 workers (5 pairs, load 1.3):
  the `lower` phase 84.7 → 44.5 ms, wall 2,486 → 2,444 ms (-1.7%) and an
  `imported_body` edit 2,347 → 2,308 ms; CPU +1.9% with identical
  instructions, peak RSS 300 → 298 MiB. Devtools wall 905 → 896 ms; the 10
  slowest tests 44.5 → 44.1 s. The largest unit bounds the speedup. Serial
  builds take the old path.

### CT43: prefetch loading

The loader reads, lexes and parses one file at a time (`reuse/project.zig`).

- **Fix:** read and lex discovered imports on workers.
- **Result (18 October 2026):** dropped. On a 2.5 s game build the phase clocks
  give lexing 19 ms, parsing 12 ms and loading 6 ms (1.5% of cold samples in
  all). Parsing interns into the shared symbol pool under inherited fixities,
  so only reads and lexing could move: at most about 15 ms of wall time with
  four workers. `serve-project` reads through the revision snapshot, which
  records every read and is not thread-safe, so prefetching would also need a
  concurrent snapshot and speculative import resolution.

### CT44: level-wise parallel checking

- **Fix:** check independent modules of one dependency level in parallel. It
  needs a symbol-pool overlay. Large and high risk; do it after CT30–CT41.

## Phase 3: frontend validation

### CT45: freeze without copying

`freezeFromCheckedCore` is 7.8% of cold.

- **Fix:** freeze checked Core in place or by moving buffers instead of copying.
- **Result (18 October 2026):** CT45, "Move prepared Core into the frozen
  closure instead of copying it". The 7.8% was mostly validation and principal
  projection (CT46, CT48); the Core copy was 0.4% of cold samples. Fresh freezes
  now take each new module's prepared Core (`Prepared.takeCore` leaves an empty
  owner; borrowed seed Core never moves). Since CT9 a cold build lowers straight
  into the seed, so cold is unchanged; retained freezes of fresh modules shrink.
  Game, 3 runs at load 1.1: freeze requests 59.2 → 46.4 MiB and 29.6 → 23.5 ms
  on a body edit, 131.8 → 101.0 MiB and 67.5 → 52.7 ms on an imported-body edit.
  Wasm identical.

### CT46: incremental frozen-Core validation

`frozen_core_validation` (`Graph.edge` at 1% self, plus `cycles`) runs over the
whole program on every build.

- **Fix:** validate only new or changed modules, and build the graph edges once.
- **Result (18 October 2026):** two commits. "CT46: renumber fresh Core with a
  checked relink and validate it once": a fresh freeze whose entry precedes its
  dependencies (every cold build) validated each module's Core in source
  numbering, to guard an unchecked relink, and again in the closure pass. The
  relink now rejects units naming the excluded entry or no module, and only the
  dense pass runs: game instructions -1.51% (23,423 → 23,068 M), devtools -1.62%,
  measured on `fa4d4d5`. "CT46: reuse shared Core validation by owner inputs,
  not global facts": validation reads foreign modules only through unit
  references, so a shared module whose transitive owners are all shared keeps
  its receipt when the module count is unchanged and the dictionary only grew,
  instead of requiring every module's bounds and the symbol count to match.
  Game, 3 runs at load 1.1: a type-change revert revalidates 13 instead of 129
  modules' Core (validation 61.9 → 24.6 ms, edit 1,937 → 1,896 ms), an
  unused-export revert 75 instead of 129 (81.8 → 53.7 ms); the miniature
  suite's type change revalidates 1 instead of 4 (budgeted). Building the edges
  once was not needed: each pass visits an edge once. A linear acyclicity proof
  for lowered type graphs saved 0.17% of instructions and was dropped. Wasm
  identical.

### CT47: copy-free capability views

`capability_contracts.View.validate` spends 1.5% in memcpy.

- **Fix:** validate through borrowed slices.
- **Result (18 October 2026):** dropped. CT78 already stopped zeroing the 136
  KiB of fixed scratch per call. On a cold game build (1,347 samples)
  `View.validate` is 0.4% inclusive (5 samples, from capability digests,
  interface validation and scheme import) and its memset one sample; no copy
  remains to borrow.

### CT48: cache dependency interface validation

`dependency_interface_validation.validateGraphWithBudget` is 0.6% self.

- **Fix:** skip it for interfaces whose hash is already validated.
- **Result (18 October 2026):** two commits. "CT48: validate each fresh
  principal interface once, after renumbering": `freezeOne` validated every new
  interface (bounds and graph) before the closure pass validated it again; the
  checked relink now covers interface units, so only the closure pass remains:
  game instructions -0.67% (23,068 → 22,913 M), devtools -0.67%. "CT48: keep
  shared interface receipts when only the dictionary grows": shared interfaces
  were already reused (no hash needed: a shared owner is immutable), but any new
  symbol revalidated all of them. Interface validation reads only its own
  module and bounds symbol IDs from above, so a grown dictionary keeps the
  receipts: a game type-change edit checks 13 instead of 129 interfaces, an
  unused export 75 instead of 129 (miniature suite 1 and 3 instead of 4,
  budgeted). With CT46, versus main `67f1068` (5 pairs, load 0.8): cold game
  validation clock 128 → 58 ms, instructions -2.2% (23,185 → 22,675 M),
  devtools -2.4%; type-change edit validation 72.7 → 24.8 ms (CPU 1,987 →
  1,941 ms). Wasm identical.

### CT49: attribute `validateModuleBodies`

It is 13.1% inclusive cold.

- **Fix:** break it down with CT2 and CT4, then cache per module stamp or fold
  it into checking.
- **Result (18 October 2026):** dropped after attribution. It is the checker's
  body inference, inside the `check` clock, not a separate validation: 14.6% of
  cold game samples, of which `inferGlobal` is 81% (`inferDeclarationBody`
  9.2%, `finishGlobal` 2.4% of the build), `finish` resolving final types 16%
  (2.2%) and source-operator validation 0.4%. Each module is checked once cold;
  retained edits already skip unchanged modules (module cutoff and body
  caches), and a cross-process cache per stamp is the restart cache (CT82).
  Its cost belongs to the checker and inference hills.

## Phase 4: inference

### CT50: memoize mapping refinement

`specialization.Service.refineMappingsCaptures` is 28% inclusive and
`bodyEvidenceMode` 33%.

- **Fix:** memoize refinements per canonical (callee, mapping) key.
- **Overlaps:** Hill 4.
- **Result (18 October 2026):** dropped. Refinement receipts already memoize
  per (root, expected, seeds, rows): on a cold game build 16,254 of 19,248
  requests hit the local memo, leaving 2,994 fresh regions, of which only 63
  repeat an earlier key (physical-shape queries that cannot publish). A
  canonical memo could save at most 2% of refinement regions; the 28%
  inclusive is those regions' own inference, which CT60 and CT61 cut.

### CT51: split the largest region

Region `game.blot:9829` has 5,137 scopes and takes 262 ms.

- **Fix:** extend Hill 2's general split to it.
- **Result (18 October 2026):** deferred; far larger than a hill. The region
  is the principal evidence of the `played` composition constant (253 ms
  profiled at main, 260 ms after CT60/CT61). Its 5,137 scopes are 2,944
  named-body instances of only 255 bindings, 2,192 constructor instantiations
  from field accesses and updates, and one closure; 922 roots stay open. The
  calls stay inline because summaries key only first-order parameters
  (`summaryShapeEligible`), and plugins and systems arrive as functions.
  Splitting it needs Hill 2's summaries parametric in their argument
  functions' obligations, a semantic design change.

### CT52: certify incrementally

`closeCertificates` rebuilds a map over every scope at each solve end
(`eval/core_eval.zig:6587`).

- **Fix:** record certified pairs as scopes are added, and return early when
  nothing changed.
- **Result (18 October 2026):** dropped after measurement. After CT60
  `closeCertificates` is 2.6% of cold game samples, but it runs about once
  per region, at solve end: 6,495 calls over 5,886 regions, 3,549 of which
  close rows; 1,154 find no certificate and only 363 see an unchanged solver.
  A settled-row set with lazy protection (rollback-safe, reference path under
  projections) passed a parity law but measured 20.633 → 20.611 G
  instructions (-0.1%) and 2,340 → 2,330 ms over 5 pairs.

### CT53: per-scope edge lists

`freeze` scans all edges twice per scope, and `exportMappings`/`exportSolved`
scan every variable per scope (`eval/core_eval.zig:6572-6640, 11743-11750`).
That is quadratic in region scopes.

- **Fix:** use compressed sparse rows and per-scope variable lists.
- **Result (18 October 2026):** dropped. On 2,475 cold game samples
  `freeze` is 0.2–0.3% inclusive and `exportSolved` 1.4%, almost all of it
  projection and row resolution rather than scanning; per-scope lists would
  save under 0.3%.

### CT54: memoize `lexicalScope` and index instance selection

`lexicalScope` rebuilds a reachable set (`eval/core_eval.zig:7985-8005`), and
the `instance_selection` import scans every binding (around :7396).

- **Fix:** memoize the first and index the second.
- **Result (18 October 2026):** dropped. Neither `lexicalScope` nor the
  `instance_selection` binding scan appears in 2,475 cold game samples.

### CT55: lazy region scratch

Each region sets up about 14 maps and 12 lists (`eval/core_eval.zig:6291-6338`)
for a mean of 17 constraint visits.

- **Fix:** initialize them lazily and pool the region shell.
- **Result (18 October 2026):** dropped after measurement. Region setup and
  teardown are 0.5% of cold samples (arena reset 0.4% self), and 4,233 of
  5,886 regions request under 16 KB of solver memory. Resetting only the bump
  blocks in use and keeping already-binned large blocks measured 20.451 →
  20.442 G instructions (-0.04%), 2,345 → 2,339 ms over 5 pairs.

### CT56: solver allocation under 100 MB

The solver requests 262 MB in 477k allocations, and scratch requests 122 MB in
220k.

- **Fix:** reset region arenas instead of freeing, and size pools from counters.
- **Overlaps:** Hill 7.
- **Result (18 October 2026):** deferred. The solver's final capacities sum
  to 109 MB over a cold game build (effect rows 37 MB, type nodes 26 MB,
  effect versions 14 MB, labels 11 MB, extra 7 MB, operations 6 MB); the
  rest of its 262 MB is ArrayList regrowth inside pooled arenas, under 1% of
  cold CPU. Rows dominate because chronological resolution publishes a fresh
  row header per resolved fragment. Under 100 MB needs solver stores pooled
  beyond one region's arena, or fewer row headers in `effects.zig`, a memory
  model change. CT60's label memo and CT61's chains raise the requests to 266
  MB solver and 132 MB scratch.

### CT57: share program tables between sessions

`Session.init` is O(program) (`eval/core_eval.zig:1441-1487`), and private
sessions repeat it (`reuse/independent_call_proof.zig:90`).

- **Fix:** share immutable tables between sessions.
- **Result (18 October 2026):** covered by CT15, whose `Session.initShared`
  gives private sessions (independent call proofs and semantic component
  jobs) the parent's unit facts. A cold build's one `Session.init` is 0.1% of
  samples.

### CT58: stop copying wide values

`attemptConstraint` copies a Constraint (around `eval/core_eval.zig:10990`), and
`Body.get` returns a whole Plan union (`backend/resolved_body.zig:64-68`).

- **Fix:** pass pointers.
- **Overlaps:** Hill 14.
- **Result (18 October 2026):** dropped. `attemptConstraint` copies a
  Constraint of about 160 bytes per visit (52,075 visits, about 8 MB on a
  cold game build). `Body.get` is 0.3% of cold samples, nearly all from
  `Body.deinit` copying each plan out, and plan put, deinit and init 1%
  together; pointer access would save under 0.5%.

### CT59: a solver worklist

- **Fix:** finish Hill 5's open worklist so solver passes revisit only the
  constraints that changed.
- **Result (18 October 2026):** dropped. Regions with more than eight
  constraints already use the watched worklist. Of 52,075 constraint visits
  on a cold game build, 42,500 solve, 8,542 wait on summaries and 830 stay
  open, so there is no rescanning left to remove.

### CT60: memoize type-evidence projection

`type_evidence.Store.projectDepth` and `projectRowBody` are 1.4% self cold and
2.1% in a literal edit.

- **Fix:** memoize them per (type, mapping).
- **Result (18 October 2026):** CT60, "Memoize owned projection of operation
  labels". Owned (mapping-free) projection memoized type nodes but re-projected
  every effect row label: per call-site `project` in `collectCallAt` and
  `collectSelected` was 12% of cold game samples, half of it interning the same
  operations. The region's projection cache now also memoizes each solver
  label, charging its arguments' exact visits and failing at the depth where
  re-projection would; it shares the type memo's clocks. Laws compare with
  unmemoized projection, invalidate on rollback and argument writes, sweep
  allocation failures, and pin hit budgets and depths. 5 pairs at load 1.2–1.8:
  game 2,502 → 2,343 ms CPU, 22.68 → 20.62 G instructions (-9.1%); devtools 835
  → 815 ms, 6.96 → 6.74 G (-3.3%); `robot_pickup` 5,499 → 5,328 ms (-3.6%
  instructions); literal-in-body edit 1,363 → 1,262 ms, body edit 1,910 → 1,806
  ms. Wasm identical.

### CT61: memoize `ClosureRegion.importType`

It is 0.7% self.

- **Fix:** cache imports per region by source type id.
- **Result (18 October 2026):** CT61, "Chain solver operations by identity,
  instance and arity". `importType` already memoizes per (scope, type) and
  shares closed source types per region (0.4% self after CT60). The import
  cost left was interning imported evidence labels: `internResolvedOperation`
  scanned every solver operation per new label (2.6% of cold game samples,
  all from `importEvidenceLabel`, quadratic in a seed row's labels). The
  solver now chains operations by identity, instance and arity in index order,
  linked lazily and unlinked by rollback, so interning compares only same-key
  candidates and still returns the oldest equal one. A law checks every intern
  against the old scan through rollback, argument writes, seeded tables and
  allocation failures. 5 pairs at load 1.4: game 2,340 → 2,321 ms, 20.63 →
  20.45 G instructions (-0.9%); devtools -0.4%; `robot_pickup` 5,311 → 5,257
  ms (-1.6% instructions). Wasm identical.

### Issue #15: reference overlap validation

`wasm_lifetimes.Analysis.validateReferences` scans a parent's access list per
reference field, capped at 256 × 1024 comparisons per call; exhausting the cap
marks the parent escaped.

- **Result (18 October 2026):** measured; neither CPU nor rejections are
  material, so no implementation. The pass has no samples in 2,475 cold game
  samples (the whole lifetime pass is 1.7–2.1%). Counted with a temporary
  probe that also ran the uncapped scan: cold game 7,111 calls (2,070 with
  references; 5,602 references, 37,401 accesses, at most 271 and 2,981 in one
  function) make 8,516 comparisons; devtools 5,183; `robot_pickup` 8,972; a
  retained session with five edit/revert pairs 60,309 over 65,052 calls. No
  call exhausts the budget, so no proof is rejected by it. Stress shapes on
  one self-referencing record: W disjoint fields cost W² comparisons (the cap
  first binds at W = 513), K reads per field multiply that by K + 1 (W = 256,
  K = 4 exhausts it), and an overlapping write ends the scan early (W = 256:
  32,897) but still exhausts it at W = 1,024. Only budget exhaustion on such
  records rejects a proof the uncapped scan would accept.

## Phase 5: backend

### CT62: faster static-data serialization

`backend_static_data.serialize*` is 17% of cold. It scans all nominals per
nominal value (`backend/backend_static_data.zig:232-237`), allocates per
aggregate (:444) and finds record fields linearly (:470). Each `dataWords`
journals three events plus a copy (`backend/wasm.zig:447-477`).

- **Fix:** use a nominal bitset, scratch buffers, a field index and bulk copies.
- **Result (18 October 2026):** dropped. The 17% is inclusive: below
  `serialize*` sit `Generator.function` for static closures and
  `specializeClosure` inference. Excluding nested function compiles,
  serialization is 2.7% of cold game samples and 11% of a literal edit's, almost
  all of it `specializeClosure` (inference, CT50–CT61) and
  `source_value_template.moduleGenerative` (CT15). The code this hill names, the
  nominal scan, aggregate lists, field search and `dataWords` journaling, is
  under 0.3% everywhere (0.2% cold game, 0.2% edit, 0.8% devtools), too little
  to justify touching the artifact journal.

### CT63: a per-unit quantified-variable set

`quantifiedVariable` (`backend/backend_emission.zig:648-675`, from `332b496`)
scans every table of the unit for each ambiguous variable at each use. Its
budget is charged by unit size, so on large units it runs out and quietly
declines.

- **Fix:** build the quantified set once per unit.
- **Target:** no budget-driven declines, and the scan disappears from profiles.
- **Result (18 October 2026):** "CT63: Build each unit's quantified-variable set
  once". `backend/unit_index.zig` builds the set lazily per compile attempt;
  `closeAmbiguousUse` no longer charges the body budget. The scan never showed
  on gdev, whose large units skip `localStorageMappings` at the 4,096-node cliff
  (CT64), so game and devtools are unchanged: 28.364 G and 9.233 G instructions,
  3,635 → 3,780 ms and 1,247 → 1,273 ms CPU (5 pairs, load 5.4, noise), Wasm
  identical on game, devtools and the 10 slowest tests. A padded unit (200
  declarations, 20 generalized locals) that used to exhaust the budget and
  report `ownership_unproved` now compiles and runs.

### CT64: a def-use index for Core

`localStorageMappings`, `useCount`, `hasMutableUse`, the loop-plan scans,
`collection_iteration`, `private_cursor.check` and `owned_arrays` all scan the
whole unit. Several are cut off above 4,096 nodes
(`backend/backend_emission.zig:337, 1159`,
`backend/collection_iteration.zig:103`), which quietly turns optimizations off
in big modules.

- **Fix:** add a lazy per-unit index of references, captures, parent blocks and
  break values, and remove the cliffs.
- **Result (18 October 2026):** "CT64: Index each unit's def-use facts and drop
  the 4,096-node cliffs". `backend/unit_index.zig` answers every scan exactly;
  the private-cursor family uses a worklist, then replays the rules in scan
  order. Intended output change: only `src/robots.blot` (4,918 nodes) gains an
  optimization, the physical iteration and step sinks of `pick_along`'s loop.
  Game Wasm 1,844,385 → 1,843,273 B; 34 of the 65 entries in
  `scripts/bench/gdev-wasm.json` change, each by a multiple of the 556-byte loop
  rewrite, and devtools and 30 others are identical; the 39 gdev tests reaching
  `pick_along` pass with both compilers. Instructions: game 28.364 → 28.314 G,
  devtools 9.233 → 9.215 G, literal edit 14.617 → 14.589 G. CPU (5 pairs, load
  1.3): game 2,970 → 2,976 ms, devtools 1,039 → 1,043 ms, literal edit 1,436 →
  1,427 ms. Building the index in groups on first use (references and flags,
  statement parents, flow facts) keeps `compile_budget`'s chain_generic at
  main's requested bytes (8,533,910 → 8,492,366 B) for +0.004% game
  instructions.

### CT65: memoize layouts across emitters

`fromTypeDepth` re-walks types and scans mappings
(`backend/layout.zig:732-736`), and each emitter has only a 32-entry cache.

- **Fix:** memoize closed types globally and keep a (type, mapping id) memo.
- **Evidence:** compare the `layout_requests` and `layout_reused` counters.
- **Result (18 October 2026):** "CT65: Memoize closed type layouts per unit".
  Closed types (65% of the game's 159k top-level derivations, 8,266 distinct)
  are memoized in the layout store by unit position; the (type, mapping) memo
  was not needed. Wasm identical. Instructions: game 28.314 → 28.123 G (−0.7%),
  devtools 9.215 → 8.940 G (−3.0%), literal-constant edit 21.486 → 21.295 G.
  CPU: game 2,981 → 3,033 ms, devtools 1,035 → 1,044 ms (load 1.1), inside the
  ±3% build-to-build layout jitter of this series: CT71, an instruction no-op,
  measured −2.0%.

### CT66: incremental runtime planning

`planRuntime` rebuilds the startup graph and reruns `collect` on every iteration
(`backend/backend_plan.zig:232-262`).

- **Fix:** extend reach incrementally.
- **Result (18 October 2026):** dropped. The loop runs only for runtime cells
  (top-level `let`), and none of gdev's sources, its tests or `std` declare
  one, so `planRuntime` returns after its body scan on every gdev entry: 0 of
  959 cold game samples and 2 of 7,689 on a literal edit. Incremental reach
  would also have to reproduce the first `const_only` origin and follow
  suspensions cached between iterations, for nothing gdev can measure.

### CT67: an arena per emitter

Each function allocates a fresh emitter with about 90 lists and maps
(`backend/core_backend.zig:1062-1078`).

- **Fix:** reuse one emitter shell with a per-function arena.
- **Result (18 October 2026):** dropped. Emitter teardown (`Owner.deinit`) is
  0.04% of cold game samples, and the allocations under emitter frames are the
  checker and evaluator stores (`equalGraph`, effect rows) and module emission,
  not the emitter's own lists and maps. Those are filled through the shared
  `g.allocator` at hundreds of sites in `backend_emission.zig`, so an arena
  would mean splitting allocators throughout the emitter for a gain under the
  noise.

### CT68: memoize inlining analyses

`wasm_inline` recomputes `returnedParameter`, `admitted` and `framed` per call
instruction (`backend/wasm_inline.zig:95, 105, 334-360`).

- **Fix:** memoize them per callee.
- **Result (18 October 2026):** "CT68: Compute each inlining callee fact once
  per pipeline session". Atomic per-function slots shared by workers. Wasm
  identical. Instructions: game 28.056 → 28.045 G (−0.04%), devtools 8.910 →
  8.906 G. CPU: game 2,961 → 3,017 ms, devtools 1,006 → 1,026 ms (layout
  jitter).

### CT69: one lifetime analysis per function

`analyzeWithSummaries` and `rcPlan` rescan the same body
(`backend/wasm_lifetimes.zig:756, 1417`), and `assemblePrepared` reruns `rcPlan`
(`backend/wasm.zig:1077`).

- **Fix:** share one `Analysis` per function.
- **Result (18 October 2026):** "CT69: Share one lifetime scan between the
  lifetime and rc passes". The validation in `assemblePrepared` scans the
  root-lowered body, a different one, so it keeps its scan. Wasm identical.
  Instructions: game 28.123 → 28.056 G (−0.24%), devtools 8.940 → 8.910 G,
  literal edit 14.556 → 14.527 G. CPU: game 3,036 → 2,946 ms, devtools 1,030 →
  1,010 ms.

### CT70: in-place pass pipeline

About ten passes each build a new body and copy every instruction
(`backend/runtime_pipeline.zig:148-229`).

- **Fix:** edit in place or ping-pong between two buffers.
- **Result (18 October 2026):** "CT70: Size each rewriting pass's output body
  once". Each rewriting pass reserves its output; editing in place or passing
  buffers through every pass would rewrite ten passes for the same copies. Wasm
  identical. Instructions: game 28.045 → 28.036 G (−0.03%), devtools 8.906 →
  8.904 G. CPU: game 3,025 → 3,017 ms, devtools 1,025 → 1,029 ms.

### CT71: a cycle-preparation worklist

`prepareCycles` runs a reachability fixpoint over all instructions
(`backend/wasm.zig:653-684`).

- **Fix:** use a worklist.
- **Result (18 October 2026):** dropped. A worklist that stops at the first
  reached allocator measured 28.0358 → 28.0358 G instructions on the game (+0.02
  M) and the same on devtools: the fixpoint already stopped early.

### CT72: skip capture when no retained consumer exists

Capture costs 81 ms cold, and CLI builds also populate the cache on the critical
path (`main.zig:438-475`).

- **Fix:** capture only for retained sessions. Write the cache after output is
  flushed.
- **Result (18 October 2026):** dropped. Every `serve-project` build has a
  retained consumer: the next revision is admitted against this capture, and
  checkpoints and the restart cache encode it. The CLI already captures only
  when the restart cache is enabled (`retain_artifacts = cache_file != null`)
  and writes the cache after the Wasm file. Capture is now 3.5% of cold game
  samples (`recordArtifact` and journal recording), all of it read by the next
  build. Replying before persisting is CT24 and background population CT85.

### CT73: parallel final encoding

- **Fix:** encode functions on workers into per-function buffers. Concatenate
  them in index order.
- **Result (18 October 2026):** dropped. Encoding is 0.3% of cold game samples
  and about 1% of an edit. Per-worker buffers joined in index order kept the
  Wasm identical for every worker count, but with `codegenWorkers` 4 (5 pairs,
  load 1.6) `assemble_us` fell only from 89.6 to 89.1 ms on the game, 95.1 to
  92.3 ms on a literal edit and 64.2 to 60.0 ms on its revert. Wall time did
  not move (2,256 → 2,258, 1,038 → 1,036 and 936 → 931 ms), and CPU rose 2%.

## Phase 6: hashing, copying, memory

### CT74: release allocator overhead

`TrackedAllocator` wraps every release allocation with non-atomic counters
(`runtime/memory.zig:5-43`, `main.zig:156, 299`). That forces a mutex-wrapped
allocator on workers (`eval/parallel_allocator.zig`).

- **Fix:** use per-thread or atomic counters, or compile them out, and give
  workers `smp_allocator`.
- **Unblocks:** CT86–CT89.
- **Result (18 October 2026):**
  `CT74: share allocation meters with workers without a lock`.
  `TrackedAllocator` gains a `.shared` mode with atomic counters (`.single`
  keeps plain ones), and `LockedAllocator` hands any shareable allocator (smp,
  page, or a shared meter over one) to jobs unwrapped. Serial builds are
  instruction-identical. The game with `--semantic-workers 4` drops from 5,050
  to 4,844 ms CPU and from 4,225 to 4,065 ms wall (5 pairs, load 6.5).

### CT75: a fast hash for in-memory keys

Blake3 keys in-process caches with 4-byte updates
(`reuse/body_check_cache.zig:776` and about 25 other sites).

- **Fix:** use a 128-bit non-cryptographic hash where keys are not persisted.
- **Result (18 October 2026):** dropped after an audit. Every Blake3 key is
  either persisted (restart-cache stamps, `.blotdep` digests, compiler identity)
  or admits a body-cache hit by digest equality without the full key (body read
  sets, capability contract and unit origin digests). A non-cryptographic hash
  could turn a collision into a miscompile there. In-process tables that verify
  their keys already use Wyhash. Blake3 is about 1.5% of cold self time.

### CT76: fast structural hash and equality

`structural.hash` and `structural.equal` walk slices element by element
(`structural.zig:9-70`).

- **Fix:** hash and compare unique-representation slices as bytes.
- **Result (18 October 2026):**
  `CT76: hash and compare fixed structural values as
  bytes`. Fixed-size parts
  reach the sink in one update: memory-identical slices directly, padded records
  packed in 1 KiB chunks. The byte stream is unchanged, so stamps stay
  identical. Plain records compare with `memcmp`. Instructions fall 0.2% on the
  game, 0.4% on a literal edit and 4.8% on its revert; CPU moves within noise.

### CT77: reserve map capacity

- **Fix:** reserve capacity in bulk-built maps (`Session.init`
  `field_locations`, region maps) from known counts.
- **Result (18 October 2026):**
  `CT77: size Session field tables once from counted
  families`. Cold builds
  are unchanged and a retained revert runs 0.4% fewer instructions. Region maps
  have no known counts. The larger growth cost is the per-call pair set in
  `types.Store.equalGraph` (1.1% of cold samples), left to CT36.

### CT78: find the memcpy and memset callers

memcpy and memset take 11.6% self cold and more in edits.

- **Fix:** attribute their callers with CT4. Remove by-value copies of large
  structs and zeroing of fixed arrays that are written before they are read.
- **Result (18 October 2026):**
  `CT78: stop zeroing unused validation scratch and
  copying hot inputs`. The
  sampler attributed the copies on CT76 (1,350 samples).
  `capability_contracts.View.validate` zeroed 136 KiB of fixed arrays per call
  (2.0%), `frozen_core_validation.Graph.edge` copied its 160-byte receiver
  (0.7%), and evidence interning sent one Wyhash update per word (1.2%).
  Instructions fall 5.1% on the game, 5.0% on devtools, 2.8% on a literal edit
  and 7.4% on its revert. Game CPU drops from 3,656 to 3,539 ms (-2.8% paired),
  devtools by 3.4% and the edit by 2.2%.

### CT79: the hottest u64→u32 map

`hash_map(u64, u32).getIndex` is 2% self cold.

- **Fix:** identify the map. Replace it with a dense array or a better key where
  ids are compact.
- **Result (18 October 2026):** dropped. The hottest map is
  `effect_evidence.operation_buckets` (1.1% of the 2.0%). It is keyed by a
  Wyhash fingerprint, so no dense array applies. Using the fingerprint as its
  own hash saved 0.1% of instructions but no CPU over 15 pairs (+0.2% median).

### CT80: a modern CPU build

The release target is `.cpu_model = .baseline` (`zig-native/build.zig:8`).

- **Fix:** measure an x86-64-v3 build. If it pays, ship a variant or dispatch
  hashing at runtime.
- **Result (18 October 2026):** dropped. An `x86_64_v3` build runs 1.1% fewer
  instructions but 3.8–4.2% more CPU on the game over 16 pairs on this Zen 2
  machine. Neither a variant binary nor runtime dispatch pays.

### CT81: exit without teardown

The CLI frees the whole heap before exit (`main.zig:318-478`).

- **Fix:** skip teardown in release CLI builds. Keep it for leak-checked tests.
- **Result (18 October 2026):** dropped. On a 0.7 s CLI build, skipping the
  final release saves 2.6 ms of `teardown_us` (0.4%) and 0.05% of instructions,
  with no measurable CPU change. The release `live_bytes == 0` checks in the
  Deno tests are worth more.

## Phase 7: restart cache

### CT82: make the restart cache reuse

The cache loads but reuses no instance, so restart is slower than cold (4.0 s
against 3.0 s).

- **Fix:** find why the seed is rebuilt (`rebuilt_seed=true`, principal hits 0
  of 14), and fix the key or the seed.
- **Target:** restart under 25% of cold.

### CT83: cache the frontend

The cache holds only the backend checkpoint.

- **Fix:** persist the frozen dependency, so restart skips loading, checking and
  lowering of unchanged modules.
- **Overlaps:** Hill 8 and task 020.

### CT84: a compact cache

The game's cache file is 57 MB against a 64 MiB limit.

- **Fix:** shrink the encoding and split it per module, so growth does not
  silently disable the cache.

### CT85: populate the cache off the critical path

- **Fix:** write the cache after the reply, or on a worker.
- **Overlaps:** CT24 and CT72.

## Phase 8: parallelism and test runs

### CT86: make `--semantic-workers` pay

One worker adds 27% CPU, and no worker count beats serial wall time.

- **Fix:** after CT74, remove per-job setup and lock contention, and measure
  again.
- **Target:** four workers beat serial wall time with at most 10% more CPU.

### CT87: parallel region inference

Hill 9. It needs CT57, CT74 and CT88.

### CT88: split resolution from emission

`Generator.function` interleaves specialization and emission depth-first
(`backend/core_backend.zig:955-1089`).

- **Fix:** resolve instances first, then emit them. That lets both phases run in
  parallel. Large and high risk.

### CT89: parallel lifetime planning and codegen

The `rcPlan` loop is serial (`backend/wasm.zig:1063-1083`), and
`codegen_workers` defaults to 1 (`execution_policy.zig:8`).

- **Fix:** parallelize after CT74 and CT69.

### CT90: share the checked game across test entries

Every test entry that imports the whole game costs at least 3.3 s, and the suite
totals 167.5 s. pen builds each test as `src/test_fixture.blot` with the test
overlaid.

- **Fix:** keep one retained session per fixture and switch overlays, so each
  test pays only for its own module.
- **Target:** the suite under 30 s CPU.

### CT91: parallel test entries

- **Fix:** run test entries on separate workers that share CT90's frozen
  dependency.

## Phase 9: guards and docs

### CT92: reuse budgets

- **Fix:** assert the CT5 reuse counts and the new phase counters in
  `compile_budget.test.ts`, and tighten them as hills land.

### CT93: a timing guard

- **Fix:** add a paired CPU comparison of the game entry against the last
  recorded binary to the bench task. Fail it on a regression above 5%.

### CT94: keep the docs current

- **Fix:** update this file's baseline, `zig-native/STATUS.md` and PLAN.md as
  hills land.
