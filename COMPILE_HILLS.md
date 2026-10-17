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

### CT4: a committed sampler

The baseline used a gdb sampler: random 3–10 ms SIGUSR1 stops, inlined frames,
with PR_SET_PTRACER set for yama.

- **Fix:** commit it with its aggregator under `scripts/bench/`, so any hill can
  attach self, inclusive and subsystem tables.

### CT5: an edit-scenario suite

- **Fix:** fix the retained scenarios: trivia, literal constant, literal in a
  body, body change, type change, a body in a widely imported module, and an
  unused export. Report CPU together with `reused_named`/`fresh_named` and the
  recheck counters.
- **Target:** reuse counts asserted in `compile_budget.test.ts`, never times.

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

### CT8: record the baseline

- **Fix:** move this baseline into `zig-native/STATUS.md` and PLAN.md's
  measuring section. Retire the 647 ms and 150 ms figures, which describe the
  older workload.

## Phase 1: retained edits

### CT9: seed reuse on population

The first edit after population reuses nothing (`rebuilt_seed=true`,
`reused_named=0`). A revert reuses 1,501 instances.

- **Fix:** record the populated revision as a reuse seed.
- **Target:** the first literal edit matches the steady-state reuse.

### CT10: cut off unchanged output

Adding an unused export to `ink/math` leaves the Wasm unchanged but costs 3.1 s.

- **Fix:** compare each edited module's checked interface and lowered Core with
  the previous revision's. When neither changes for any consumer, stop before
  the backend.
- **Target:** an interface-neutral edit under 30 ms.

### CT11: interface early cutoff for importers

A body or literal edit in `ink/math` (71 importers) reuses nothing.

- **Fix:** invalidate importers by interface hash, not by module identity.
  Re-emit only the instances that inline or evaluate the edited body.

### CT12: instance-level dependencies

Body edits reuse nothing, even in a module with one changed body.

- **Fix:** record, per emitted instance, the bodies, constants and layouts it
  read. Rebuild only the instances whose inputs changed.
- **Target:** a body edit under 100 ms with output identical to a fresh build.

### CT13: incremental constant serialization

Constant serialization is 31% of a literal edit.

- **Fix:** keep serialized static data per constant, keyed by the constant's
  value and layout. Re-serialize only the constants whose value changed.
- **Overlaps:** task 086.

### CT14: cheaper `prepareReuse`

`prepareReuse` is 12% of a literal edit.

- **Fix:** index the previous revision's instances by key instead of scanning
  them, and skip modules whose stamps match.

### CT15: cache `source_value_template.moduleGenerative`

It is 2.7% self in a literal edit and recomputed per revision.

- **Fix:** cache it per module stamp.

### CT16: index `artifact_import` lookups

`knownRow` and `knownLayout` are 1.7% and 1.3% self in a literal edit.

- **Fix:** replace their scans with hash indexes built once per artifact.

### CT17: interval index for fragment admission

`artifact_fragment.State.admit` (1.1% self) scans emission records per address
(`reuse/artifact_fragment.zig:288-300`).

- **Fix:** use an interval index.

### CT18: generation tokens instead of module stamps

`ModuleStamps` re-hashes and compares every retained module's Core per edit,
about 39 ms (`zig-native/RETAINED_EDIT_COST.md`). Its `owns()` and entry scans
are linear (`reuse/code_artifacts.zig:665-730`).

- **Fix:** issue tokens at freeze time and keep the integrity check as an opt-in
  validation. The current design is a documented decision, so this needs the
  owner.
- **Overlaps:** tasks 093 and 101.

### CT19: cheaper revision input snapshots

`Snapshot.get` and `resolve` scan strings per import edge
(`reuse/revision_inputs.zig:192-194, 244-250`). Each revision realpaths, reads
and double-hashes every input.

- **Fix:** add hash maps and a stat cache, and accept the client's changed set
  through the existing overlays.

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

### CT23: persist lifetime summaries

`Summaries.prepare` scans every function at session start
(`backend/runtime_pipeline.zig:96`), including reused ones.

- **Fix:** carry summaries across revisions in a deterministic order.

### CT24: reply before persisting

The project server persists its checkpoint before replying on revision 1
(`reuse/zig_project_server.zig:367`).

- **Fix:** reply first, then persist.

### CT25: bound retained memory

Retained RSS doubles over an edit series (312 to 630 MiB).

- **Fix:** release superseded revisions' pools, captures and checkpoints once no
  lease holds them.
- **Target:** flat RSS over 50 alternating edits.

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

### CT31: memoize substitution

- **Fix:** cache `substituteWithRows` results by (type, substitution id) inside
  one check, and skip closed subtrees using a closed-height bit.

### CT32: cache `dataKind`

- **Fix:** store the data kind on interned type nodes instead of recomputing it
  per query.

### CT33: index nominal projections

`core_builder.Builder.projectType` scans every emitted type node for each
nullary nominal (`check/core_builder.zig:385-391`). It is 5.2% self cold (about
160 ms) and 29% self in some test entries.

- **Fix:** keep a map from nominal to type node.

### CT34: `epoch_resolution_cache.Cache.get`

It is 9–12% self in test entries (`reuse/epoch_resolution_cache.zig:36-45`).

- **Fix:** measure probe lengths, then fix the key distribution or the table
  layout.

### CT35: the resolve family

`resolveOperationRow`, `resolveNode`, `resolveDepth`, `resolve`, `closedHeight`
and `closedRowHeight` together take about 11% self.

- **Fix:** add path compression for resolved variables, cache heights on nodes,
  and resolve operation rows once per interned row.

### CT36: cheaper structural type equality

`equalGraph` and its pair map take about 2% self.

- **Fix:** hash-cons closed types so their equality is an id compare, and use a
  small inline pair buffer before falling back to the map.

### CT37: cheaper operation interning

`internResolvedOperation`, `internOperationInstance` and its hashed form take
about 2.5% self.

- **Fix:** precompute operation hashes and avoid the memcpy that
  `effect_evidence.internOperationInstance` performs.

### CT38: checker linear scans

`progressConstructor` (`check/check.zig:12555`), `implementationIndexForMember`
(:2856) and the duplicate-implementation check (:2599) scan linearly.

- **Fix:** index them.

### CT39: index named imports

Named imports cost bindings times exports (`reuse/project_check.zig:447-470`).

- **Fix:** index exports by name.

### CT40: lowering linear scans

The `dictionary_uses` (`check/core_builder.zig:1120, 1194`) and
`member_templates` (:2859, :2906) lookups scan linearly.

- **Fix:** use maps.

### CT41: a single-pass lexer

The lexer makes four passes and reserves no token capacity
(`parse/lexer.zig:517-529`).

- **Fix:** fuse the passes and reserve from the source length.

### CT42: parallel lowering per unit

Lowering is serial (`main.zig:403-413`), but `lowerWithOrigins` takes only const
inputs.

- **Fix:** lower units on workers and merge diagnostics in source order.

### CT43: prefetch loading

The loader reads, lexes and parses one file at a time (`reuse/project.zig`).

- **Fix:** read and lex discovered imports on workers.

### CT44: level-wise parallel checking

- **Fix:** check independent modules of one dependency level in parallel. It
  needs a symbol-pool overlay. Large and high risk; do it after CT30–CT41.

## Phase 3: frontend validation

### CT45: freeze without copying

`freezeFromCheckedCore` is 7.8% of cold.

- **Fix:** freeze checked Core in place or by moving buffers instead of copying.

### CT46: incremental frozen-Core validation

`frozen_core_validation` (`Graph.edge` at 1% self, plus `cycles`) runs over the
whole program on every build.

- **Fix:** validate only new or changed modules, and build the graph edges once.

### CT47: copy-free capability views

`capability_contracts.View.validate` spends 1.5% in memcpy.

- **Fix:** validate through borrowed slices.

### CT48: cache dependency interface validation

`dependency_interface_validation.validateGraphWithBudget` is 0.6% self.

- **Fix:** skip it for interfaces whose hash is already validated.

### CT49: attribute `validateModuleBodies`

It is 13.1% inclusive cold.

- **Fix:** break it down with CT2 and CT4, then cache per module stamp or fold
  it into checking.

## Phase 4: inference

### CT50: memoize mapping refinement

`specialization.Service.refineMappingsCaptures` is 28% inclusive and
`bodyEvidenceMode` 33%.

- **Fix:** memoize refinements per canonical (callee, mapping) key.
- **Overlaps:** Hill 4.

### CT51: split the largest region

Region `game.blot:9829` has 5,137 scopes and takes 262 ms.

- **Fix:** extend Hill 2's general split to it.

### CT52: certify incrementally

`closeCertificates` rebuilds a map over every scope at each solve end
(`eval/core_eval.zig:6587`).

- **Fix:** record certified pairs as scopes are added, and return early when
  nothing changed.

### CT53: per-scope edge lists

`freeze` scans all edges twice per scope, and `exportMappings`/`exportSolved`
scan every variable per scope (`eval/core_eval.zig:6572-6640, 11743-11750`).
That is quadratic in region scopes.

- **Fix:** use compressed sparse rows and per-scope variable lists.

### CT54: memoize `lexicalScope` and index instance selection

`lexicalScope` rebuilds a reachable set (`eval/core_eval.zig:7985-8005`), and
the `instance_selection` import scans every binding (around :7396).

- **Fix:** memoize the first and index the second.

### CT55: lazy region scratch

Each region sets up about 14 maps and 12 lists (`eval/core_eval.zig:6291-6338`)
for a mean of 17 constraint visits.

- **Fix:** initialize them lazily and pool the region shell.

### CT56: solver allocation under 100 MB

The solver requests 262 MB in 477k allocations, and scratch requests 122 MB in
220k.

- **Fix:** reset region arenas instead of freeing, and size pools from counters.
- **Overlaps:** Hill 7.

### CT57: share program tables between sessions

`Session.init` is O(program) (`eval/core_eval.zig:1441-1487`), and private
sessions repeat it (`reuse/independent_call_proof.zig:90`).

- **Fix:** share immutable tables between sessions.

### CT58: stop copying wide values

`attemptConstraint` copies a Constraint (around `eval/core_eval.zig:10990`), and
`Body.get` returns a whole Plan union (`backend/resolved_body.zig:64-68`).

- **Fix:** pass pointers.
- **Overlaps:** Hill 14.

### CT59: a solver worklist

- **Fix:** finish Hill 5's open worklist so solver passes revisit only the
  constraints that changed.

### CT60: memoize type-evidence projection

`type_evidence.Store.projectDepth` and `projectRowBody` are 1.4% self cold and
2.1% in a literal edit.

- **Fix:** memoize them per (type, mapping).

### CT61: memoize `ClosureRegion.importType`

It is 0.7% self.

- **Fix:** cache imports per region by source type id.

## Phase 5: backend

### CT62: faster static-data serialization

`backend_static_data.serialize*` is 17% of cold. It scans all nominals per
nominal value (`backend/backend_static_data.zig:232-237`), allocates per
aggregate (:444) and finds record fields linearly (:470). Each `dataWords`
journals three events plus a copy (`backend/wasm.zig:447-477`).

- **Fix:** use a nominal bitset, scratch buffers, a field index and bulk copies.

### CT63: a per-unit quantified-variable set

`quantifiedVariable` (`backend/backend_emission.zig:648-675`, from `332b496`)
scans every table of the unit for each ambiguous variable at each use. Its
budget is charged by unit size, so on large units it runs out and quietly
declines.

- **Fix:** build the quantified set once per unit.
- **Target:** no budget-driven declines, and the scan disappears from profiles.

### CT64: a def-use index for Core

`localStorageMappings`, `useCount`, `hasMutableUse`, the loop-plan scans,
`collection_iteration`, `private_cursor.check` and `owned_arrays` all scan the
whole unit. Several are cut off above 4,096 nodes
(`backend/backend_emission.zig:337, 1159`,
`backend/collection_iteration.zig:103`), which quietly turns optimizations off
in big modules.

- **Fix:** add a lazy per-unit index of references, captures, parent blocks and
  break values, and remove the cliffs.

### CT65: memoize layouts across emitters

`fromTypeDepth` re-walks types and scans mappings
(`backend/layout.zig:732-736`), and each emitter has only a 32-entry cache.

- **Fix:** memoize closed types globally and keep a (type, mapping id) memo.
- **Evidence:** compare the `layout_requests` and `layout_reused` counters.

### CT66: incremental runtime planning

`planRuntime` rebuilds the startup graph and reruns `collect` on every iteration
(`backend/backend_plan.zig:232-262`).

- **Fix:** extend reach incrementally.

### CT67: an arena per emitter

Each function allocates a fresh emitter with about 90 lists and maps
(`backend/core_backend.zig:1062-1078`).

- **Fix:** reuse one emitter shell with a per-function arena.

### CT68: memoize inlining analyses

`wasm_inline` recomputes `returnedParameter`, `admitted` and `framed` per call
instruction (`backend/wasm_inline.zig:95, 105, 334-360`).

- **Fix:** memoize them per callee.

### CT69: one lifetime analysis per function

`analyzeWithSummaries` and `rcPlan` rescan the same body
(`backend/wasm_lifetimes.zig:756, 1417`), and `assemblePrepared` reruns `rcPlan`
(`backend/wasm.zig:1077`).

- **Fix:** share one `Analysis` per function.

### CT70: in-place pass pipeline

About ten passes each build a new body and copy every instruction
(`backend/runtime_pipeline.zig:148-229`).

- **Fix:** edit in place or ping-pong between two buffers.

### CT71: a cycle-preparation worklist

`prepareCycles` runs a reachability fixpoint over all instructions
(`backend/wasm.zig:653-684`).

- **Fix:** use a worklist.

### CT72: skip capture when no retained consumer exists

Capture costs 81 ms cold, and CLI builds also populate the cache on the critical
path (`main.zig:438-475`).

- **Fix:** capture only for retained sessions. Write the cache after output is
  flushed.

### CT73: parallel final encoding

- **Fix:** encode functions on workers into per-function buffers. Concatenate
  them in index order.

## Phase 6: hashing, copying, memory

### CT74: release allocator overhead

`TrackedAllocator` wraps every release allocation with non-atomic counters
(`runtime/memory.zig:5-43`, `main.zig:156, 299`). That forces a mutex-wrapped
allocator on workers (`eval/parallel_allocator.zig`).

- **Fix:** use per-thread or atomic counters, or compile them out, and give
  workers `smp_allocator`.
- **Unblocks:** CT86–CT89.

### CT75: a fast hash for in-memory keys

Blake3 keys in-process caches with 4-byte updates
(`reuse/body_check_cache.zig:776` and about 25 other sites).

- **Fix:** use a 128-bit non-cryptographic hash where keys are not persisted.

### CT76: fast structural hash and equality

`structural.hash` and `structural.equal` walk slices element by element
(`structural.zig:9-70`).

- **Fix:** hash and compare unique-representation slices as bytes.

### CT77: reserve map capacity

- **Fix:** reserve capacity in bulk-built maps (`Session.init`
  `field_locations`, region maps) from known counts.

### CT78: find the memcpy and memset callers

memcpy and memset take 11.6% self cold and more in edits.

- **Fix:** attribute their callers with CT4. Remove by-value copies of large
  structs and zeroing of fixed arrays that are written before they are read.

### CT79: the hottest u64→u32 map

`hash_map(u64, u32).getIndex` is 2% self cold.

- **Fix:** identify the map. Replace it with a dense array or a better key where
  ids are compact.

### CT80: a modern CPU build

The release target is `.cpu_model = .baseline` (`zig-native/build.zig:8`).

- **Fix:** measure an x86-64-v3 build. If it pays, ship a variant or dispatch
  hashing at runtime.

### CT81: exit without teardown

The CLI frees the whole heap before exit (`main.zig:318-478`).

- **Fix:** skip teardown in release CLI builds. Keep it for leak-checked tests.

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
