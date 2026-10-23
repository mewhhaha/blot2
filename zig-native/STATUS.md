# Zig compiler status

## Row traversal, retained reuse and scratch, 24 October 2026

Seven alternating release pairs reduce fresh game CPU by **32.5%** against
CT96; median build wall falls from **13.60 to 8.68 s**, with identical Wasm.
Matching phase measurements reduce inference 9.93 → 6.23 s. Literal/body edits
use 40.7% / 43.1% less CPU and take 7.63 / 6.56 s median wall. The 50%
edit-CPU and four-second wall targets remain open. Backend temporary scratch
cuts 33 exhaustive sweeps from 44,074 to 37,930 runs. The isolated full gate
passes 2,540 exhaustive native laws, 1,648 guest checks, 48 smoke checks and
57 tooling checks, with zero Zig lint findings. See
[qualification](CT97_QUALIFICATION.md). CT97 is complete; CT98 and BT4 retain
their remaining timing targets. The separate text repair and installed tools
are outside this candidate.
## CT96 spawn preparation, 23 October 2026

The [qualified optimization](CT96_QUALIFICATION.md) scans for spawn contracts once
per generator and reuses one immutable module-pointer view. Every positive call
keeps its existing authority checks. Seven alternating release pairs reduce game
CPU by 28.6% and devtools CPU by 29.0%; game median build wall falls from 17.24 to
12.16 s, with byte-identical Wasm. The isolated gate passes 2,539 exhaustive native
laws, 1,648 guest checks, 48 smoke checks and 57 tooling checks, with zero lint.
The separate text-capability repair is outside this candidate's qualification.
The [post-CT96 review](../PERFORMANCE_REVIEW.md) selects row traversal next and
explains why zero executable candidates does not imply zero semantic reuse.
Its three-law diagnostic run passes 33 exhaustive sweeps and 44,074 scenario
runs; it implements no further compiler optimization.

## Compile and build costs, 23 October 2026

The [preceding baseline measurements](../COMPILE_MEASUREMENTS.md) use qualified
release `63c931f`: fresh gdev takes 16.292 s, backend inference accounts for
9.64 s of the profiled build, and repeated spawn-capability scanning owns 27.6%
of sampled CPU. Retained code edits offer zero backend reuse candidates. The
[compile hills](../COMPILE_HILLS.md) now incorporate CT96 above and its fresh
profile. The older scan cost is historical; CT97 is the next experiment.

Compiler development edits take about 3.4 s with ordinary Safe/noLLVM caching;
the warm affected check takes 4.64 s. [Build hills](../BUILD_HILLS.md) retain
ordinary caching and target exhaustive test cost separately. The benchmark
tools preserve configured budgets/assets/std, pin inputs and outputs, distinguish
wall and CPU clocks, and measure isolated build/edit/revert cycles.

## Associated work budgets, 23 October 2026

The associated-work repair compiles the unchanged frozen gdev game without a
source migration. Five fresh release builds have a median of 16.192 seconds
for the game and 0.918 seconds for devtools. It honors configured budgets
through checking and evaluation, skips unnecessary normalization for ordinary
effect rows, and reports the allowance actually exhausted. The combined gate
passes 2,539 exhaustive native tests and 1,647 guest/client checks, with
zero analyzer findings. The release CLI and compiler are installed locally.
See [qualification and measurements](ASSOCIATED_WORK_QUALIFICATION.md).
The preceding derive/budget changes are in `58e00c3`; the broader completion
plan remains open.

## Qualified task-surface continuation, 23 October 2026

The current continuation adds checker-selected spark regions, ordinary scope
wrappers with universally quantified callbacks, exact spawn helpers through
aliases/imports/partial calls, and collect-all through direct generic receivers.
Tuple collection preserves partial-result ownership and written result order.
The full gate passes 2,536 native tests with exhaustive allocation-failure
sweeps in four shards, 1,645 guest/client tests, 48 smoke checks, 54 harness
checks and 15 preflight regressions. Zig analyzer reports zero findings across
517 source files plus the fixture module. The
[qualification record](TASK_SURFACE_QUALIFICATION.md) pins raw evidence,
source/binary hashes, the frozen application corpus and local installation
checks. The final release CLI and native compiler are installed locally.

Inferred caller regions, general higher-order spawn forwarding, channels,
select-one, scoped nonlocal exits, purity certification and CPU workers remain
unfinished. The iterator and performance targets also remain open. See
[the completion plan](../FINISH_PLAN.md) and
[structured concurrency](STRUCTURED_CONCURRENCY.md).

## Earlier qualified milestones

Blot's production compiler is handwritten Zig 0.17. Deno hosts the public
compiler API, formatter and Wasm guest API. The earlier full-qualified source
freeze passes 2,223 native laws, 1,404 guest/client tests and all 455 Zig
analyzer files with zero findings. It includes 1,366 complete allocation-failure
sweeps. Exact source/executable pins and logs are in
`build/bench/complete-program-20261015/final-proof-repaired-gate/qualified-pins.json`.
The local cloud milestone passes its combined final gate below;
[language qualification](LANGUAGE_QUALIFICATION.md) maps the qualified language
contracts and their separate costs. Language behavior remains defined by
[the guide](../compiler/guide.md), with ownership rules in
[CONTRACT.md](CONTRACT.md).

The cloud milestone on 19 October 2026 passes **2,470 native laws executed,
1,556 guest/client checks and 37 harness checks**. All native counts are free of
skips, failures, leaks and logged errors. CI lint checks 507 source files plus
the fixture module at zero findings. Package dry run, editor and local-link
checks pass. The [complete current record](CLOUD_QUALIFICATION.md) includes
exact source, compiler/test-binary and toolchain pins, paired comparison, heap
and runtime measurements, and the correction preventing unverified Zig run-cache
hits from becoming native qualification evidence.

Task 024's declared/qualified field recipes and the missing staging/scoped-task
trace laws are qualified. Tasks 035, 067/068, 073/074, 075–080 and 105–107 also
close against the current gate and measurements. Task 108 also closes with
[recreated Ink callback probes](STATIC_CAPTURE_ROWS.md); 97 tasks are complete
and 13 remained open at that checkpoint. General iterator/module cutoff work and
all final performance targets remain open. The published `codeberg.org` network
rule is active and the local analyzer backend built and its doctor passed; that
checkpoint still required its final source scan. Later evidence is recorded
above and in [CONTINUE.md](../CONTINUE.md).

CT92–CT94's retained work budgets and explicit five-percent CPU gate pass. The
final seven-pair pinned candidate/baseline median is 0.941, with substantial
sample variation; no speedup is claimed. [Compile guards](COMPILE_GUARDS.md)
retains the failed noisy identity control and measurement conditions. LSP
cancellation/deadline fixtures use a native peer prepared before timed requests;
transport uses the compiled TypeScript peer. Production deadlines and assertions
are unchanged. [CONTINUE.md](../CONTINUE.md) tracks the remaining work.

The default path shares frontend callee schemes, infers closed first-order
callees through an iterative queue, and reuses complete semantic queries and
executable fragments under separate dependency checks. Inference collection no
longer consumes the executed-code depth budget: annotated chains at 300 and
1,000, a generic chain at 300 and diamond N=16 compile and execute.
Predicate-free source schemes and qualified parametric callback obligations
admit independent higher-order jobs without unfolding complete transitive
bodies. Recursive components use bounded joint inference. Incomplete callback or
capture evidence retains ordinary checking; the captured-project region and
latency targets remain open. [Call summaries](CALL_SUMMARIES.md) records the
qualified boundaries and measurements.

`std/path` provides pure getters/setters, identity and composition,
type-changing writes, and modification with an effectful transform. Staged
accessors retain unused polymorphic fields. Bounded inlining and private
functions preserve callback effect labels without treating a partial layout as a
closed semantic proof.

Known local demand-forwarding chains can use control flow and local memo state
within a shared 96-node proof budget. Indirect, recursive and escaping demands
retain runtime cells. Provider cancellation permits a later force to retry;
recursive force fails, and traps or host exceptions leave persistent demand
cells terminal. Sync and JSPI execution share this contract.

Region solvers and checker scratch use independent resettable arenas, retaining
at most 64 MiB per pool. Published results keep durable owners. Automatic CLI
and project-server restart caches contain validated checkpoint candidates;
missing, unavailable, incompatible and corrupt caches fall back to compilation.
Explicit checkpoints remain supported. No evaluated values are trusted merely
because a checkpoint file exists.

The qualified [List span change](LIST_TRAVERSAL.md) removes redundant leaf
validation from direct packed-row loops. Its three-field fold fixture uses about
24% less CPU against the preceding packed compiler, with unchanged guest memory.
Full traversal and cursor regression closure remain open.

## Recreated cloud baseline (19 October 2026)

The original local snapshot was lost and the owner approved freezing current
gdev/Ink again. The active manifest covers 583 files and 69 test entries; source
pins and the paired results are in
[COMPILE_HILLS.md](../COMPILE_HILLS.md#recreated-cloud-baseline-19-october-2026).
Three alternating game/devtools pairs and one test-suite pair compared pre-CT90
`ba5decb` with the current compiler, including isolated restart caches and
shared test sessions. Successful Wasm and the one existing test rejection match
between binaries and phases.

| Current measurement               |                           Value |
| --------------------------------- | ------------------------------: |
| Game cold CPU                     |                        2,939 ms |
| Devtools cold CPU                 |                          831 ms |
| All 69 test entries, fresh CPU    |                        165.87 s |
| Shared test session, CPU          | 120.84 s (153.72 s before CT90) |
| Largest fresh test (`goals_game`) |                          7.54 s |
| Game cold peak RSS                |                       312.4 MiB |
| Game Wasm                         |                 2,235,460 bytes |
| Game restart CPU                  |                         16.9 ms |
| Retained literal-in-body edit CPU |                        1,088 ms |
| Retained body edit CPU            |                        1,457 ms |

The test entries have 68 successful compilations and one pre-existing rejection:
`tests/protocol.blot` does not cover Ink's new `SessionStarted` event. They are
compile benchmarks, not executed game-test results. The old workload's absolute
times below are historical and do not compare directly with this new freeze.

## Historical compile-time baseline (17 October 2026)

The current measured workload is the gdev game as of 17 October 2026 (`3cf6de1`
compiler; the CT1–CT8 measurement hills in
[COMPILE_HILLS.md](../COMPILE_HILLS.md) add no compiler work). It is frozen in
ignored `build/bench/gdev-snapshot`, verified against
`scripts/bench/gdev-manifest.json`, and holds 130 source files and 1.09 MB of
Blot including the Ink library, about 2.8 times the older workload below. Every
build runs through `serve-project` with pen.json's imports and native assets.
CPU is per-thread schedstat time of the release child over the build; cold
figures are medians of 5–7 runs at low load.

| Measurement                          |                 Value |
| ------------------------------------ | --------------------: |
| Game (`src/main.blot`) cold CPU      |              3,011 ms |
| Devtools cold CPU                    |              1,051 ms |
| All 55 test entries, CPU             |               167.5 s |
| Largest test entry (`robot_pickup`)  |                19.5 s |
| Game peak RSS                        |               312 MiB |
| Game Wasm                            |               1.84 MB |
| Retained trivia edit                 |                 11 ms |
| Retained literal in a body           |                 1.6 s |
| Retained first literal-constant edit |   2.4 s (reuses none) |
| Retained body or type change         |             1.8–2.9 s |
| Unused ink/math export               | 3.1 s, Wasm unchanged |

Profiled phase clocks (`--profile`; exclusive, they cover 100–102% of child CPU)
split a cold game build into about 1.0 s of checking, 0.28 s of lowering, 0.09 s
of freezing, 0.21 s of validation, 2.0 s of backend and under 80 ms for assets,
load, lex and parse together. The session allocator receives 1,388 MiB in 3.9 M
requests: check 420 MiB, backend 611 MiB, freeze 142 MiB and lower 99 MiB. Check
raises peak RSS by 121 MiB, freeze by 62 MiB and the backend by 60 MiB.

`deno task bench:compile --baseline OLD --candidate NEW` measures fresh, restart
(`--restart-cache`) and retained phases in alternating pairs, the seven-scenario
edit suite with reuse counters, and the test suite with `--workload tests`. It
fails on Wasm that differs between binaries, between retained and fresh builds,
or from the per-entry hashes in `scripts/bench/gdev-wasm.json`, unless
`--allow-wasm-diff` declares the change. `deno task profile:compile` samples
stacks under gdb. Without the snapshot, the synthetic corpus and its miniature
edit suite still run; `zig-native/tests/compile_budget.test.ts` pins that
suite's reuse counts.

## Historical demand-forwarding measurements

These are the earlier qualified demand-forwarding measurements on the frozen,
private 394,294-byte gdev workload, from seven alternating pairs. That workload
is retired: its 647 ms cold and 150 ms first-edit figures were CLI builds
without native assets and do not compare with the baseline above. CPU is child
user plus system time; filesystem caches and machine load are uncontrolled.
Fresh compilation has persistence disabled. Retained population is measured
separately from edits. Earlier batches and different workloads are not
comparable timings. They do not describe the later 415-input captured project or
establish its current cold/edit targets.

| Measurement                          |                           Current value |
| ------------------------------------ | --------------------------------------: |
| Fresh CLI CPU                        |                                  647 ms |
| Retained population CPU              |                                  740 ms |
| First retained literal edit CPU      |                                  150 ms |
| Subsequent edit/revert CPU           |                                  140 ms |
| No-op CPU                            | Below the process-accounting resolution |
| Fresh requested allocation           |                                321.2 MB |
| Peak requested live memory           |                                 78.9 MB |
| Live requested memory after teardown |                                       0 |
| Inference regions                    |                                   2,036 |
| Largest region, scopes               |                                   8,041 |
| Solver constraint visits             |                                  35,215 |
| Occurs-check visits                  |                                  42,410 |
| Wasm bytes                           |                                 629,339 |

Wasm matched between compilers and between fresh and retained phases. Against
the preceding variable-cache compiler, fresh CPU was 644 / 647 ms, population
was unchanged at 740 ms, first edit was 160 / 150 ms and subsequent edit was
unchanged at 140 ms. Allocation and work counters are unchanged. No
compile-speed gain is claimed. Raw samples and binary hashes are in ignored
`build/bench/demand-forwarding-qualified`. Requested allocation is cumulative
allocator traffic, not process RSS or guest memory. The 500 ms cold, under-100
ms retained-edit and under-100 MB cumulative allocation targets remain open; the
stricter literal-edit target is 30 ms.

## Building and verification

Check `zig version` before a build batch. Use `deno task build:compiler` for
release builds and `deno task build:compiler:dev` during incremental
development. `deno task test:compiler` runs native semantic/ownership laws and
executed-Wasm, client, dependency, checkpoint and retained-revision tests.
`deno task lint:zig` requires zero findings. Native filtering uses
`zig build test -Dtest-filter=TEXT` from `zig-native/` and imports the complete
suite before applying the filter.

`deno task bench:compile --baseline OLD_BLOTC --candidate NEW_BLOTC --runs 5`
checks output equality against both binaries, retained phases and the recorded
hashes, and measures fresh, population, no-op and the edit suite's edit and
revert phases through `serve-project`. Add `--restart-cache` for isolated cache
population and process restart, `--workload tests` for the test suite and
`--profile` for phase clocks and allocation counts. The harness verifies the
private gdev snapshot against `scripts/bench/gdev-manifest.json`; never commit
that snapshot. Without it, the synthetic corpus still runs.
`blotc build ... --profile` reports phase, allocation and region detail;
deterministic work counters accompany compilation records.

## Remaining boundaries

The shared semantic query table and its portable archives are implemented.
Selected, principal, refinement, constant and executable records retain separate
proof obligations. Higher-order and recursive jobs retain bounded ordinary
fallbacks when their inputs are incomplete. The captured-project latency and
allocation targets remain open. Semantic workers stay opt-in until paired CPU
and wall measurements justify a default change. The local analyzer backend
builds with the active Codeberg network policy and doctor passes; its final
source scan remains required by the owner-specified gate.

The current continuation replaces ordinary tracing with counted strong edges,
journal/invocation leases and nonmoving trial deletion for real cycles. Its
latest result-slot transfer and iterator changes pass the current common
compiler gate. General iterator allocation and its performance comparison,
broader fusion/SIMD and complete retained-body/constant coverage also remain
open. See [standard-library guidance](../std/PERFORMANCE.md),
[language evolution](LANGUAGE_EVOLUTION.md), [demand evaluation](DEMANDS.md) and
[the architecture](ARCHITECTURE.md) for current contracts and limits.
