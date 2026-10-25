# Five-minute development feedback

CT116's selected Safe/noLLVM development cycle passes in 29.80 s, including the
new dependency, membership, imported-summary and parallel-checker laws. This is
one observed cycle, not a paired compiler-build speedup. The frozen full gate
uses four native shards and completes in 687.33 s with exhaustive allocation
faults. A missing local analyzer was rebuilt with its compatible Zig 0.17
backend under `build/tooling`; `ZIG_ANALYZER` selects that workspace-owned
executable. See [CT116 qualification](zig-native/CT116_QUALIFICATION.md).

The [CT113 cycle](zig-native/CT113_QUALIFICATION.md) compiles all 2,587 native
laws and passes 130 selected sampled laws, 68 executed guests, formatting/types
and zero Zig lint findings in 28.16 s. Native compilation takes 7.21 s. This
cycle overlaps diagnostic work and is not a compiler-build speed comparison. The
final LLVM release builds in about three minutes. Full native execution passes
2,587 laws and 1,687 exhaustive allocation sweeps in 632.80 s. After a guest
temporary-directory race is fixed, the successful resumed gate takes 78.23 s,
including 30.56 s for all 1,660 release guests. The cached native phase is
verified and resumed; these are not fresh full-gate build timings. Default
development and all native-test compilation remain noLLVM.

Historical CT112 observations follow.

The [CT112 follow-up](zig-native/CT112_QUALIFICATION.md) expands static-sharing
to 120 sampled native laws and 68 guests. Its final isolated cycle compiles the
complete 2,586-law native inventory and passes formatting/types and zero Zig
lint findings in 29.09 s. The cycle overlaps LLVM release construction; it is
not a quiet or paired compiler-build timing. A separate four-shard sampled run
passes all 2,586 laws in 30.82 s. The separate full gate passes in 723.99 s,
including 635.97 s exhaustive native execution on four shards and 39.74 s
release guests. Its native compilation and already built release are cached;
these are not fresh compiler-construction timings.

Historical CT110 iteration measurements:

[CT110](zig-native/CT110_QUALIFICATION.md) passes the expanded 99-law / 56-guest
selected development cycle in 25.54 s, including complete Safe/noLLVM
compilation of 2,576 native laws. Full native compilation takes 9.70 s and
exhaustive execution 1,228.48 s across two shards. The LLVM release builds in
318.80 s while native execution overlaps. These are observations, not paired
build gains; the previous CT109 run below used four shards.

The first full gate passes native execution but finds a guest cache-directory
cleanup race. The fixture now waits for detached writer locks. A verified native
resume completes guests/local checks in 51.06 s; that excludes the already
completed exhaustive execution and is not a 51-second full gate. Final
qualification passes all 1,656 guests and zero Zig lint findings.

Historical CT109 iteration measurements:

[CT109](zig-native/CT109_QUALIFICATION.md) expands the static-sharing family to
95 native laws. Its last complete selected cycle passes in 25.73 s; this is one
shared-host observation, not a paired construction speedup. Final exhaustive
qualification compiles all 2,573 native laws with Safe/noLLVM in 8.63 s and
executes them in 651.07 s (four shards, 630–651 s). The full gate takes 711.82 s
and includes 1,656 guests; its already built LLVM release is reused. Development
selection and complete release qualification remain separate.

The CT106 distribution below retains its original 78-law selection and source
pins; it is historical evidence, not the current selection count.

[CT106](zig-native/CT106_QUALIFICATION.md) measures 20 complete Safe/noLLVM
static-sharing edit/check cycles: **25.35 s median**, **27.64 s observed p95**,
**27.78 s maximum**. Leaf/checker compiler construction medians are 4.29/4.88 s;
the test-only cached compiler build is 0.36 s. Complete native compilation takes
7.20–8.03 s by edit class, and guest smoke about 9.7–9.9 s. Every cycle compiles
all 2,564 native laws, runs the same 78-law sampled family and 55 guests, and
passes local checks. The first failed teardown sequence is excluded and
preserved; the completed sequence verifies every source restoration, compiler
identity and inventory. These are observed distributions on a shared host, not
paired build speedups or universal latency bounds. Full release qualification
remains separate.

The historical LLVM release trace spends 220.88 of 227.76 s in emission. Keep
Safe/noLLVM for development and the complete native inventory; focus next on
native compilation, the measured guest cost and LLVM emission. The deep guest
fixture is already just above its required 128-level boundary. Correct build
identity recomputation preserves compiled-artifact caches and fixes the observed
stale digest. [Experiment tools](scripts/bench/README.md) document reproduction.

Historical development measurements follow.

The [CT96 task-family edit cycle](zig-native/CT96_QUALIFICATION.md) passes in
14.54 s, including complete native compilation, 17 native laws, 27 guest checks
and local analysis. Full qualification still needs 665 s of native execution on
this run. Use the [build hills](BUILD_HILLS.md) for measured targets and a phase
allowance with enough headroom; a cancelled gate never counts as a pass.

The [23 October local measurements](COMPILE_MEASUREMENTS.md) supersede the
historical cloud timings below for this host: ordinary Safe/noLLVM compiler
edits take about 3.4 s, native compilation about 5.5 s, and two warm
`check:dev --area type-effects` cycles pass in 4.71 / 4.64 s. Empty-cache Zig
build-system initialization alone costs 56 s, so retain stable writable caches.
Explicit incremental mode shows no useful real-edit gain in the three-cycle
screen and regresses cache hits. The [build hills](BUILD_HILLS.md) separate
cache initialization, edit/check cycles and exhaustive qualification; full
native execution remains the largest gate cost at 596 s.

Run `deno task check:dev --area static-sharing` from the repository root. In the
cloud environment, activate the pinned tools and avoid waiting behind a heavy
job:

```sh
. /workspace/.tools/activate.sh
python3 /workspace/.tools/run-heavy.py --no-wait deno task check:dev --area static-sharing
```

The command enforces a 300-second total budget. A timeout, missing selected
test, failed check or changed input is incomplete or failed, never a pass. The
repository lease returns busy immediately when another compiler check owns its
artifacts.

## Scope

- Compile the complete native inventory with Zig's backend, then select existing
  laws at runtime. LLVM is reserved for the actual release compiler.
- The current static-sharing family selects 99 native laws, covering aggregate
  parity and rejection, persistent roots, principal observations, portable
  archives, closure replay, checked interfaces, bounded backend reuse,
  effect-row normalization and fault-policy behavior. `--list-areas` and the
  run's exact selection are authoritative.
- Run the selected protocol, budget-recovery and client edit/error/recovery
  guest tests. JUnit validation requires every selected file/name to actually
  execute and pass.
- Run formatting, type checks and local Zig analysis. Broad lint changes batch
  pending files into directory scans; cache reuse still checks
  tool/configuration and transitive contents.
- Record actual names, per-test durations, fault coverage, input/executable
  hashes, identity-check timings, other overhead, and pending qualification in
  `build/bench/check-dev/results.json` and a separate directory for each run.

Development fault checks execute the successful scenario and inject faults at
its first, middle and last discovered allocation positions. The default full
mode retains exhaustive sweeps, including the original standard-library
semantics. The native policy laws exercise both modes. Manual fault loops remain
exhaustive.

This published selection uses existing compiler behavior. Pending compiler
repairs can extend the manifest with their additional native and guest laws;
those extensions must be qualified alongside the repair. They are not
prerequisites for using the published command.

## Improvements and measurements

The first implementation measured 244.92 s with compiler/native rebuilds and
88.57 s cached on the pending compiler candidate's expanded 21-native/48-guest
selection. Its sampled timing census executed all 2,510 native tests in 176.55
s. These are historical development measurements, not release qualification or a
p95 guarantee for the published compiler.

The isolated published selection passes in **154.74 s**: compiler rebuild 29.35
s, all 2,499 native tests compiled in 43.25 s, 16 selected native laws in 1.38
s, 45 guests in 25.44 s, and Zig analysis in 44.77 s. Initial/final identity
checks take 7.56 s; other overhead is 0.11 s. Formatting and type checks also
pass. The raw report is `build/bench/turnaround-publish/results.json` (input
digest `3d491fd3d6067f605a9834d5dea40067a5bf02ce6ba24a0986b3a10b66887dcf`).

The final cached command, including the smoke-lease correction, passes in
**28.66 s**, executing the same 16 native/45 guest selection and static checks.
Its report is `build/bench/turnaround-publish-final/results.json` (input digest
`601bd377b08ca581a7547d9c5d222c781805629c14bd5bc2a51d9e48ca6f5a6b`). Identity
checks take 12.89 s and other overhead 0.11 s. These single-run numbers show
substantial I/O/runtime variation; they do not establish a p95 or a speedup
against the pending candidate's different test selection.

One pending ownership law spent 76.73 s in two direct exhaustive
standard-library fault sweeps. The new wrapper lets development explicitly
sample those sweeps while preserving the original full-mode behavior. Broad lint
edits previously launched hundreds of processes; directory batching checked 513
files with zero findings in 62.18 s. The 256-local requirement law now reuses
its already prepared baseline, preserving the budget boundary, rejection and
exact byte comparison.

Native tests reserve the same 1 GiB evaluation stack as the compiler, with pages
committed on demand. This fixes Zig-only failures caused by the host's 8 MiB
main stack. The runner harness includes a 16 MiB stack regression.

Executable hashing uses a reusable 1 MiB buffer instead of many small stream
reads. An initial same-machine comparison of the 291 MB compiler and 509 MB
native executable measured 3.56 s before and 1.30 s after, with identical
SHA-256 values. Source hashing shares a 64 KiB buffer. All bytes are still read
before and after a check; equal sizes/timestamps do not bypass verification.
Boundary and same-size edit tests guard these identities. Timed identity checks
now expose previously unattributed wall time without caching test execution.

## Remaining hills

Measure the next 20 real development cycles before claiming a five-minute p95.
Keep cold and cached observations separate. Extend the explicit regression
families when changes reach beyond their documented scope.

Profile the next necessary LLVM release build with Zig's time report; do not
rebuild LLVM native unit tests. Further scheduling work can use the recorded
per-test durations to measure shard imbalance before changing the partition.

Keep genuine boundary tests in extended validation. Examples include the
evidence limit, a 2^19-visit projection DAG and a million-instruction relocation
budget. Shrinking them would stop testing their intended limits.

A quick pass never replaces the full native exhaustive-OOM gate, full guests/CI,
or release exact-output, CPU, runtime and allocation qualification. Frozen
evidence remains tied to its original inputs.

The automatic recent-failure preflight currently runs guests with Safe/noLLVM.
Release-calibrated allocator budgets can therefore fail there even when the
release compiler passes. CT111 encountered this mismatch. Recheck the complete
budget file through `test:compiler --guest` using the same `--timings-dir`; a
successful release run clears the recent-failure entry normally before retrying
the full gate. Preserve the failed log and do not relax budgets or inject native
resume evidence. This limitation is separate from compiler correctness.

Validation before publication: all 44 tooling tests pass. The final full-gate
smoke-lease correction passes all 19 affected launcher/journal tests, including
a new busy-before-build regression. The 256-local boundary law also executes and
passes in default full mode with zero skips, failures, leaks or logged errors.

## Explicit shard scheduling and additional areas

The full gate now executes the installed native binary directly in one to four
bounded concurrent shards, default two. It inventories the binary first, checks
every shard against its exact partition, rejects missing/repeated/skipped tests,
and requires the requested allocation-failure mode and complete shard records.
Full qualification always requests `full`; standalone sampled runs remain
explicit development measurements. No test cases or exhaustive sweeps were
removed.

Each shard has its own logs and measured monotonic execution interval. The
coordinator reports peak active shards and retains partial evidence on failure.
A failed shard cancels its siblings, including descendant process groups. Native
journal reuse pins the inventory, raw shard logs, report, executable and
aggregate phase logs; altered or incomplete evidence cannot become a resumed
pass.

The earlier small Zig probes already overlapped forced runs with and without an
explicit working directory. They did not explain historical production
serialization. Direct scheduling removes dependence on that build scheduler for
full-gate execution; it does not claim a diagnosis of Zig itself or a release
speedup. Synthetic barrier tests prove one/two/four-worker execution and
failure, cancellation and resume behavior. Real inventory measurements are
recorded below.

Use `deno task check:dev --list-areas` for the supported selections:

| Area             | Native laws | Guest coverage                                                                 |
| ---------------- | ----------: | ------------------------------------------------------------------------------ |
| `syntax`         |           9 | CST structure and annotation success/rejection                                 |
| `type-effects`   |           9 | Nominal identity, symbolic rows, retained/archive specialization and rejection |
| `body-checking`  |           8 | Seven fresh/retained revisions including edits, rejection, recovery and revert |
| `static-sharing` |          16 | Protocol, budget and selected client recovery                                  |

These are focused families, not whole-subsystem substitutes. Their native laws
include positive behavior, rejection/recovery and ownership/OOM checks. Every
command still compiles the complete native inventory and enforces its
five-minute budget. Selected-only guest areas avoid an empty Deno file list
(which would otherwise discover unrelated tests), and requested guest fixtures
are derived from the manifest. Unknown areas fail before any build starts.

The three new commands pass on the isolated published compiler baseline, with
all 2,499 native tests compiled: `syntax` **25.25 s** (9 native/13 guests),
`type-effects` **25.98 s** (9 native/7 guests), and `body-checking` **17.65 s**
(8 native/1 guest). Reports are `build/bench/shards-areas-AREA/results.json`.
The existing `static-sharing` family also passes in **28.51 s**, executing all
16 native laws and 45 guests through the updated workflow. All 51
compiler-tooling tests pass, including the integrated full-gate
failure/repair/resume/native-edit sequence. These are measured development runs,
not a cold-build or p95 guarantee.

The real complete-inventory execution passes all **2,499 native tests in 172.81
s**, split into 1,250 and 1,249 tests with a measured peak of two active shards.
This census uses sampled allocation failures and does not qualify a release.
Source and executable digests stayed unchanged during the measurement. Raw
per-shard logs and intervals are retained under
`build/bench/shards-areas-census`; `results.json` records exact inventory
coverage and `pins.json` records the before/after identity checks. Full
exhaustive-OOM timing remains to be measured in the next necessary release
qualification.

## Compiler cleanup and generic expansion

The compiler build-cost repair removes two sources of generated-code growth.
`package_core` now adapts its public contexts to one concrete internal context,
so anonymous caller structs no longer instantiate nine recursive walkers.
`checkEngine` uses one non-inlined teardown for its initialized owner. Direct
owners move into `Checked` together; subsequent fallible publications fill empty
fields and drain the corresponding engine lists. A failed publication destroys
the transferred fields and the remaining engine state once each. Temporary
owners retain their cleanup order and scratch-pool lifetime.

Dependency decoding and Core cloning now share a non-inlined destructor for the
initialized field prefix. The body auxiliary owner destructor also stays outside
its unrolled capture loop. These changes retain field order, wire formats and
allocation-failure behavior while avoiding repeated cleanup expansion.

The final body-checking development run passes in **116.85 s**, including a
**33.66 s** compiler rebuild and **70.37 s** compilation of all **2,510** native
tests with Zig's backend. It executes the eight selected native laws, the guest
with seven revisions, formatting, type checks and local lint. The full directory
lint scan also passes with zero findings. All **24** selected checker/completion
tests pass separately in exhaustive allocation-failure mode in **18.21 s**.
These are local observations, not p95 claims or full release qualification.

Raw evidence is under `build/bench/compiler-build-cost-body-pass`,
`build/bench/compiler-build-cost-checker-oom`, and
`build/bench/compiler-build-cost`. Earlier intermediate development runs failed
lint and remain recorded as failures. An earlier extended OOM batch passed 53
tests before its overall five-minute timeout; it remains incomplete.

The complete sampled native run finished in **263.08 s**: 2,509 tests passed,
and the shared allocation-meter test failed. Repeating that test reproduced
three failures in 100 runs. Its comparison against an independent serial run
assumed that the allocator's in-place growth decisions did not depend on
allocation order. The corrected test sums plain per-job counters over the same
operations observed by the shared counter; production allocator code is
unchanged. All three memory tests pass 100 repetitions both standalone and in
the rebuilt complete native executable. The resulting coverage record combines
2,507 unchanged passing tests with those three rechecked tests, verifies the
exact 2,510-name inventory, and preserves the original failed census. This is
not a fresh whole-suite pass. See
`build/bench/compiler-build-cost-meter/coverage.json` and
`build/bench/compiler-build-cost-census/results.json`.

The emitted Zig-backend function sizes confirm that the duplicated work was
removed. Against the earlier inspected development binary:

| Code                       |                  Earlier bytes |                        Current bytes |
| -------------------------- | -----------------------------: | -----------------------------------: |
| `checkEngine`              |                        612,984 | 46,751, plus 9,053 in shared cleanup |
| All `Walker` methods       | 3,417,823 across nine families |                380,027 in one family |
| Largest decoder instance   |                        448,364 |                               43,751 |
| Largest Core-copy instance |                        294,180 |                               19,830 |

These are emitted-code measurements, not whole-build speedup ratios. The older
binary differs elsewhere in the pending compiler work. The partial-field
destructors add 81,532 bytes across all their concrete types; their cost is
shared across failure sites. See `compiler-build-cost/symbol-summary.json`.

The isolated LLVM/Fast release attempt **did not finish within its 600-second
budget** and was terminated at **600.17 s**. No completed release build or LLVM
pass timing report was produced, so no end-to-end LLVM speedup is established.
The earlier 27/37-minute observations also used different sources and concurrent
build work. The canonical earlier release executable was preserved. The command
and failed result are in `build/bench/compiler-build-cost-release/results.json`.

The largest remaining Zig-backend function is `body_check_cache.captureBody` at
**426,073 bytes**: 505 source lines, 18 error cleanups, 21 other cleanups and 77
fallible calls. `wasm.Module.assemblePrepared` (152,069 bytes),
`Engine.reuseBody` (125,793), and `code_artifacts.capture` (119,935) follow.
Shared ownership cleanup in `captureBody` is the next concrete candidate to
investigate. Static size does not establish which function dominates the
remaining LLVM time. Release qualification and the full exhaustive-OOM gate
remain pending.

After the LLVM timeout, all **109** selected guest tests in **37** files pass
with the Zig-backend compiler in **65.77 s**. They cover package/rank behavior,
ownership, portable execution, staging, dependency reuse, edits, recovery and
restart. JUnit coverage and unchanged source pins are recorded in
`build/bench/compiler-build-cost/qualification-development-guests.json`. They do
not qualify an LLVM release executable.

For publication, an isolated export of the staged tree excludes the separate
pending compiler repairs. Its Zig-backend compiler and complete 2,499-test
native executable build successfully in 28 s and 44 s respectively. All 27
selected checker, completion and memory tests pass with exhaustive allocation
failures; all 153 selected guest tests in 41 files pass. The source working tree
remains unchanged during these checks. Evidence is under
`build/bench/build-cost-publication/`. This establishes focused validation of
the published changes independently of the pending repairs; the full exhaustive
gate and LLVM release qualification remain pending.

## `captureBody` release build follow-up (22 October 2026)

`body_check_cache.captureBody` now keeps its partial lists in one
`CaptureScratch` owner with a non-inlined destructor. Early declines and
allocation failures release the same fields; slices transferred to a `Body`
still have their individual error cleanups. This removes the repeated list
cleanup expansion from the many exits of the capture routine. On the current
Zig-backend binary, `captureBody` emits 190,574 bytes plus a 2,054-byte cleanup
function. On the current LLVM release binary it emits 57,213 plus 1,090 bytes.
The earlier inspected binaries reported 426,073 and 201,681 bytes respectively;
those binaries used different surrounding source, so the sizes are evidence of
reduced generated code rather than a controlled whole-build speedup ratio.

The compiler-only LLVM time report on the separate pending candidate finishes in
**206.15 s**, including **205.50 s** for `blotc`. Zig attributes **199.00 s** to
LLVM emission, **5.73 s** to declaration work and about **0.16 s** to link
flush. LLVM pass timing totals 187.49 s; its largest entries are loop strength
reduction (19.45 s), instruction combining (17.84 s), instruction selection
(14.62 s) and inlining (14.49 s). The earlier 600-s timeout used another source
state; neither run is a matched before/after build comparison. Raw reports and
source/binary pins are under
`/workspace/blot2/build/bench/compiler-build-cost-release-scratch/` in the
separate pending checkout.

In the isolated main checkout, the complete LLVM release build, including its
runtime fixtures, takes **255.10 s**. The full compiler gate takes **754.63 s**:
all **2,500** native laws execute with exhaustive allocation-failure mode in
**651.22 s** on four concurrent shards, all **1,587** guest/client checks pass
in **76.50 s**, and 51 harness plus 48 smoke checks pass. Native execution has
zero skips, failures, leaks or logged errors. All 513 Zig files pass local lint
with zero findings. The raw gate is in `build/bench/capture-scratch-main-gate/`
in the isolated checkout.

The four native shard intervals are 478.44, 494.16, 651.16 and 525.57 s. Their
combined test duration gives a 537.33-s four-core lower bound, leaving at most
about 114 s for perfect repartitioning of this run. These test names and
durations are saved with the gate. Rebalancing is a final-gate opportunity; the
Zig development loop remains the right path for changes in progress.

The recreated 583-file gdev snapshot verifies the recorded Wasm for the game,
devtools and `tests/goals_game.blot`, and all seven game edit/revert scenarios
match fresh output. The three-pair game identity control passes its 1.05 CPU
guard at paired median 0.995. Identity pairs check benchmark noise; they do not
measure the patch against an unmodified main compiler. Results are under
`build/bench/capture-scratch-main-{game,other,retained}-identity/`. A separate
seven-pair comparison on the pending candidate reports median 0.994 against the
previous qualified compiler, with identical Wasm between those binaries, but
both differ from the repository's older recorded game hash; it is only a
diagnostic, saved in the pending checkout's
`build/bench/compiler-build-cost-release-scratch/game-cpu-diagnostic/`.

The next 20 **real** changed-source development cycles are still needed before
claiming a five-minute p95. The two focused checks on this main patch took 25.64
s with a rebuild and 4.57 s cached. Repeating an unchanged check would measure
cache replay, not another development cycle.

## Stop a failed native gate promptly

The full gate invokes each installed native shard with `--fail-fast`. A failing
law, allocator leak or logged error writes its timing record and exits; the
scheduler then cancels and reaps sibling process groups. Missing shard
completion is a failure and cannot enter the successful resume journal.

Successful shards still execute the complete inventory with exhaustive
allocation failures. The flag changes failure latency, not passing coverage. An
explicit manual invocation without `--fail-fast` retains the option to collect
multiple failures in one run. Runner fixtures cover the early exit, complete
inventory, ordinary failure reporting and sibling cancellation.

## Preserve native evidence and balance exhaustive work

Native resume identities exclude `CODEX_TOOL_CALL_ID`, `SHLVL` and `_`: these
identify a tool invocation or shell bookkeeping, rather than compiler
configuration. Compiler options, the remaining environment, source and fixture
bytes, toolchain files, executable and raw logs still have to match. The real
runner recovery test changes the tool-call ID between invocations and checks
that a guest repair resumes native evidence while a native edit invalidates it.

Exhaustive workers use successful per-test durations to balance their assigned
work. An installed baseline supplies hints on a fresh checkout; a local complete
run supplies newer hints. Unknown tests remain in the inventory, and missing or
corrupt hints fall back to the ordinary partition. Each selected test, fault
mode and worker completion is still checked against the complete inventory. The
executable's existing exact-name selection runs each group.

The first 2,525-test measurement took 1,399 seconds, with individual workers
taking approximately 1,040, 1,399, 1,099 and 1,014 seconds. Assigning those same
recorded durations predicts about 1,138 seconds per worker. That 19% reduction
is a scheduling estimate; a subsequent exhaustive run must measure the result.

## Integrated exhaustive run, 23 October 2026

The combined numeric/ownership candidate passes all 2,525 native tests with
exhaustive allocation failures in **1,028.47 s**, using four balanced groups.
The complete compiler gate takes **1,113.76 s**, including 1,640 guest checks in
**48.15 s**. Verified compiler and native build caches take 0.11 and 0.45 s. The
final numeric development family passes in **26.03 s**. These are individual
observations, not a p95 guarantee. Earlier unbalanced native execution took
1,399.38 s while LLVM also ran; the difference cannot all be attributed to
balancing. No native tests or exhaustive fault positions were removed.

Native identities ignore only per-invocation tool bookkeeping while preserving
source, toolchain, executable and log hashes. This avoids re-executing an
unchanged successful suite merely because the next tool call has a new ID. See
the [full qualification](zig-native/NUMERIC_QUALIFICATION.md).
