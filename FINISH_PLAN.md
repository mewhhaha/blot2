# Finish the current Blot program

Prepared 23 October 2026 from current main `93bc8d4`, the preserved candidate in
`/workspace/blot2`, the task index, and GitHub issues #25–#27. This is an
execution plan; no implementation or qualification is claimed by its creation.

[Triage of issues 26 and 27](ISSUE_TRIAGE.md) prioritizes cold-start phase
attribution before choosing an implementation and keeps the nested-layout
comparison separate from allocation-free contract research.

## Execution checkpoint, 23 October 2026

The subsequent
[associated-work repair](zig-native/ASSOCIATED_WORK_QUALIFICATION.md) restores
compilation of the unchanged frozen gdev game, honors configured budgets and
corrects exhaustion diagnostics. Its full gate and fresh release measurements
are recorded separately. This repair and the preceding derive work do not close
any additional milestone below.

The owner reconfirmed the full remaining plan and asked to implement before
final verification. The task-surface continuation from `87ba3f6` in
`/home/mewhhaha/src/blot2` is now qualified. The former `/workspace` paths below
describe historical integration work; both existing stashes remain preserved.
The new slice covers checker-selected spark groups, universally quantified
ordinary scope callbacks, and runtime collect-all. Direct relays, currying,
identity forwarding and renamed imports execute in both tiers and sync/JSPI.
Tuple collection works through direct generic receive helpers, aliases and
imports, preserving partial-result ownership. Exact explicit spawn helpers work
through aliases, renamed imports and stored partial calls, with capture checks
at the completed call.

The [full qualification](zig-native/TASK_SURFACE_QUALIFICATION.md) passes 2,536
exhaustive native tests, 1,645 guest/client tests, 48 smoke checks, 54 harness
checks and 15 preflight regressions. Zig lint reports zero findings. The release
CLI and native compiler are installed locally, and the README, language guide
and implementation contracts describe this slice. Arbitrary higher-order spawn
forwarding and implicit caller-region propagation still require further
signature evidence. The entire completion plan remains open.

The [compact symbolic instruction journal](zig-native/SYMBOLIC_JOURNAL.md)
passes the full compiler gate and strict seven-pair application comparison. It
reduces temporary allocation in emission; it does not close the remaining
performance targets. The scope/spawn/tuple slice is qualified above; the
remaining task-region and channel lifecycle work is still unfinished.

Milestone 1 is integrated and passes the complete compiler gate. Issue 26's
bounded numeric layout repair passes both-tier runtime, allocation, immutable
snapshot, host-copy and fresh/retained/restart checks. The
[qualification record](zig-native/NUMERIC_QUALIFICATION.md) includes the
measured compiler tradeoffs and rejected broad-inlining variants. Milestones 2
and 3 still have the explicit remaining iterator and performance requirements
below; issue 25's later language/runtime milestones are not complete.

Task 086 is complete as not needed on the measured workload: its conservative
constant-work estimate is 14.9% of later-edit CPU, below the 20% gate. Larger
backend/inference work remains, and the eleven other task records stay open.

Published commits: Blot `4091cb2` closes issue 26 after complete qualification.
Pen `b2f06cf` reuses its validated module cache during scene discovery: warm
export falls from 3.440 to 0.169 seconds and 2,471 to 105 MiB maximum RSS, with
complete bundle and cache-recovery equality. Issue 27's later-edit,
bounded-session and remaining compiler targets are still open.

## Scope and starting state

The outcome is one integrated, qualified main branch covering the remaining
`CONTINUE.md` work and issue #25. Issues #26 and #27 overlap the existing
representation and performance program and share its measurements.

- The task index has twelve open tasks: 047, 081, 082, 084, 086, 093, 100–104,
  and 999.
- `/workspace/blot2` is at `607618a`, 23 commits behind main. It contains 25
  modified tracked files and three untracked source/test files. Preserve this
  candidate and its evidence before integration; do not reset it.
- The clean `/workspace/.issue25-next` checkout is at main `93bc8d4`. Commit
  `e3e7463` qualified task receive helpers and the F32 return repair: 2,510
  exhaustive native tests, 1,633 guest/client checks, and zero lint findings.
  These results qualify that commit, not the separate dirty candidate.
- The recreated gdev snapshot and older candidate evidence are present under
  `/workspace/blot2/build/bench`. Verify the recorded manifest before using
  them. The lost original snapshot is not a prerequisite; its recreation was
  already authorized.
- At plan creation, issue #25 supported single task receives and sparks in a
  literal task scope, plus ordinary receive helpers through aliases/imports. The
  execution checkpoint above records the subsequent scope/spawn wrapper and
  tuple collection work. Generic caller-region propagation, selection, streams,
  scoped exits, purity certification, and CPU worker transport remain open.

Existing decisions stand: `return` exits the function, `break value` finishes
the nearest `do`, and unsupported returns across generated continuations give
explicit diagnostics. The new surface remains `*(call)`, `|source|`, `|(a, b)|`,
and `|a, b|`. Scope, task, channel, and control helpers use ordinary calls and
checked contracts. Do not introduce new block keywords or recognize prelude
function names as magic.

## Ordered milestones

### 1. Recover and integrate the existing candidate

1. Save a recoverable local checkpoint of the tracked diff, all three untracked
   files, and an evidence manifest. Record the source and executable hashes.
2. Compare its changes with the intervening main commits. Classify each as still
   needed, already superseded, or a rejected experiment. Carry forward the
   needed changes into a fresh worktree based on current main.
3. Group the live changes by behavior: iterator/evaluated-call optimization,
   constant/static-sharing correctness, and client process shutdown. Resolve
   overlapping backend and type-store edits using the current contracts.
4. Run the affected native and executed-Wasm laws, including the positive
   static-closure reuse law, second-edit/rollback controls, alias changes,
   immutable snapshots, and fresh/edit/revert equality.
5. Qualify the integrated candidate and its compiler/runtime costs against
   current main, then commit and push the accepted changes.

**Exit:** a clean integrated branch with reproducible evidence; no useful work
or benchmark provenance exists only in the old dirty checkout.

### 2. Finish iterator and representation work

Complete task 047's remaining Window/reducer/ownership cases and the final
all-width cursor comparison. Preserve independent forks, pull order, early
termination, saved snapshots, and the fallback for escaping or unknown state.

Use the recorded rejected Window counterfactual as a constraint: it reduced
allocation but slowed the measured cases by roughly 10–27%. Investigate the
remaining ownership/lifetime cost with a narrowly falsifiable experiment; do not
repeat the same cost-guard bypass. A rejected optimization stays rejected. An
unfulfilled task requirement stays open unless the owner changes the
requirement.

Qualify issue #26's nested numeric records versus sixteen-scalar records on
current main, across calls, callbacks, imports, arrays, and retained snapshots.
If there is no remaining gap, close it with that evidence. If there is a gap,
implement and measure the smallest internal layout/calling-convention repair;
preserve nominal types, public ABI, wire order, and floating-point operations.
Treat its allocation-free-boundary investigation as a separate explicit result,
not an implication of pre-optimization allocation remarks.

**Exit:** 047's accepted requirements are satisfied, and #26 has a measured
resolution or a clearly identified remaining acceptance row.

### 3. Establish one performance baseline and finish the measured gaps

Use task 084's workload preparation as the common baseline for 086, 093,
100–104, and issue #27. This avoids separate competing benchmark campaigns.

1. Verify the recreated source manifest, pin assets for host startup tests, and
   pin compiler, library, options, cache state, and machine conditions.
2. Measure fresh compilation, population, no-op, first and later literal edits,
   private helper edits, exported type/import changes, generic specialization
   changes, restart, and failed-edit/recovery separately.
3. Attribute compilation, constant evaluation/serialization, Wasm loading/JIT,
   assets, and overlapping processes. Separate cumulative requested bytes,
   peak/live requested bytes, process RSS, and guest capacity/live memory.
   Account for telemetry overhead and unattributed memory.
4. Resolve task 086's gate with at least seven paired retained measurements:
   quantify unaffected constant work, C. Continue broader receipt work only if C
   is at least 20% of edit CPU or the largest attributed phase. Otherwise close
   086 as not needed under its existing acceptance rule.
5. Use the attribution to finish 093 and attack 100–104. Extend the existing
   reuse/cache owners; retain their exact identity and publication checks.
   Measure bounded cache growth, eviction, corrupted checkpoint rejection, and
   long edit-session recovery for #27.

| Task | Required performance result                           |
| ---- | ----------------------------------------------------- |
| 100  | Fresh compilation approximately 500 ms CPU            |
| 101  | Retained literal edit below 30 ms CPU                 |
| 102  | General retained body edit below 100 ms CPU           |
| 103  | Every inference region below 50 ms CPU                |
| 104  | Cumulative requested compiler allocation below 100 MB |

A measured miss with good attribution is useful progress, but it does not close
these performance gaps. Preserve negative and inconclusive results. The
historical application RSS near 5 GiB in #27 is not evidence that the compiler
alone owns that memory and is not the same metric as task 104.

**Exit:** the measurement gate for 086 is resolved, 093 is accounted for, the
five target rows pass, and #27's attribution, memory bounds, and recovery
requirements are qualified.

The older named follow-ups must be reconciled explicitly, not lost in the task
index. Use this routing when auditing them:

| Existing follow-up                                                                                             | Work destination                                                                                    |
| -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| CT28: development tier for `pen dev`'s own Blot session                                                        | Verify during milestone 1; implement the scoped option forwarding if still missing                  |
| P1 closed-row certificates; P2 robot-pickup obligations; P3 `played` constructor memo; P4 namespace comparison | Measure and rank in milestone 3; accept or reject each proposed optimization with evidence          |
| CT10/11/22/26/29: IDs, interfaces, repeat optimization, body reuse, rejected populations                       | Milestone 3's edit/dependency/serialization work                                                    |
| CT51 and CT56: parametric summaries and solver storage lifetime                                                | Milestone 3's inference-region and memory targets                                                   |
| CT44/87/88: compiler checking/inference parallelism                                                            | Milestone 3 only if attribution supports it; this is separate from guest CPU workers in milestone 9 |
| R4, deferred borrowed-array cases, v128 closure boxing                                                         | Milestone 2's representation/callback matrix                                                        |
| Remaining frame retains, collection-copy and acyclic-flag cases                                                | Milestones 2–3's runtime ownership and memory measurements                                          |
| Restart checkpoint cost and retained-cache growth                                                              | Milestone 3 and issue #27                                                                           |

First check whether newer main commits already resolved each old note. An
optimization hypothesis can be rejected on evidence; an outstanding accepted
requirement must be completed or remain visibly open.

### 4. Move issue #25's region inference into checking

Treat the previous architectural blocker as implementation work with a bounded
first milestone:

1. Preserve spark/receive intent in syntax until checking. Move group selection
   out of the parser's literal-`@task.scope` rule.
2. Define generative region and once/capture-transfer contracts for scope and
   spawn. Infer the required region for a helper that sparks work; preserve it
   through calls, currying, aliases, imports, and higher-order wrappers.
3. Validate the contracts against source/Core bodies and at frozen/imported
   boundaries. Keep exact region identities and existing no-escape rules.
4. Preserve callable/argument evaluation at the parent spark site and execution
   of only the invocation in the child.

**Exit:** ordinary `scope`/`spawn` wrappers and a helper that sparks into its
caller's group execute correctly through imports. Missing groups, expired
groups, forged contracts, duplicate consumption, and cross-region captures
reject. Nested scopes select their own group. Scope exit still drains children.
No new user decision is needed for this milestone.

### 5. Finish task receives and tuple collection

Implement type-directed receiver operations and preserve collect-all versus
select-one syntax through formatting and Core. A tuple held in a binding or
passed through `await` must behave like a literal tuple of receivers. A task
whose payload is a tuple returns that payload without recursive receiving.

Establish all collection dependencies together and retain partial results until
completion or cleanup. Do not lower this contract to unrelated destructive
blocking receives. Qualify exact return values, application errors as data,
single execution, capture snapshots, cancellation/failure order, nested
dependencies, and cleanup. Keep existing demand behavior.

**Exit:** task-only collect-all works through direct and imported helpers in
both tiers and sync/JSPI, with partial-result ownership and failure laws. Stream
collection and selection complete in milestone 7.

### 6. Implement typed scoped exits

Implement the checked `control.scope` primitive and ordinary wrapper. Its exit
capability carries a fresh target and result type, can pass through helpers, and
may survive suspension in the same logical task. Calling it unwinds to that
target and cleans up scopes, children, and resources crossed by the exit.

**Exit:** nested and recursive targets remain distinct; expired targets,
escaping capabilities, and use from another task reject. Deep parser exits,
host-call settlement, and cancellation/drain behavior execute correctly.

### 7. Implement bounded streams and selection

Add checked channel creation, send, receive, and close operations with ordinary
source wrappers and constructors. Implement FIFO, capacity zero rendezvous,
bounded buffering, backpressure, endpoint versioning, and exactly-once message
transfer/drop. Sender close drains queued items; receiver close returns blocked
senders' unsent values. Cleanup and cancellation wake affected tasks.

Add select-one without consuming losing endpoints. Specify readiness ties,
closure, cancellation, and fairness in the durable contract; use written-order
tie resolution for simultaneous readiness and test starvation behavior. Retain
the scheduling-choice effect. Extend collect-all to one event per stream.

**Exit:** the issue's complete producer/consumer and collector examples run,
including capacity one, renamed/imported constructors, early close, blocked
send, partial collection, consumer failure, and cancellation races.

### 8. Certify the restricted pure subset

Keep effect freedom, deterministic results, total/non-trapping execution, and
permission to move/drop/speculate as separate facts. Start with finite acyclic
task graphs and checked finite batches/restricted pipelines. Unknown progress or
unsupported effects keep the conservative behavior.

Validate and preserve proof facts across helpers and imports. Enumerate small
adversarial schedules and compare values, required bit patterns, ownership,
cleanup, and failure/termination behavior. First-ready selection, external
mutation/clocks, unqualified host callbacks, schedule-sensitive failure, and
unproved channel progress must not silently become pure.

**Exit:** accepted programs have explicit checked evidence, and all required
counterexamples reject or retain their effects.

### 9. Add checked workers and measured scheduling optimizations

Define a separate transport boundary for worker-safe data and effects. Reject
raw guest pointers, invalid loans, and unsupported host capabilities. Bound
worker and queue resources and preserve cancellation and result ownership.

Prioritize task/queue elimination, stage fusion, and small-job chunking, then
worker execution. Compare direct sequential, cooperative, fused/static, and
worker implementations on the same inputs and permitted traces. Measure the game
snapshot/calculation/fixed-order-commit workload, a bounded pipeline, and deep
parser exits. Include tiny jobs and memory pressure.

Record replay hashes, p50/p95/p99 runtime, compile cost, code size, task/queue
counts, transferred bytes, allocations, and peak live memory. Publish missing
proof reasons and reject regressions. The issue's more speculative monotonic
data, algorithm portfolio, GPU, and distributed ideas are hypotheses for later
work; they do not expand this completion plan into promises of implementation.

**Exit:** checked CPU parallelism is real, the required optimizations are
qualified, and issue #25's acceptance matrix is complete before closing it.

### 10. Final integrated qualification and cleanup

Maintain docs and analyzer checks at each milestone, then close 081 and 082
against the final integrated source. Use 084 first to establish the common
workload/baseline, and finally to audit the completed program; this avoids
treating its documentation/measurement dependencies as a circular stop.

Reconcile old `CONTINUE.md` “remaining” notes with current code and tests so
already completed issues are not reopened by stale prose. Run the full
semantic/ownership, sync/JSPI, source/import/archive, retained/restart/recovery,
editor, packaging, analyzer, and performance gates on the combined candidate.
Move essential contracts and evidence into durable documents.

Only then execute task 999: audit every completion row, remove `tasks/` and the
old `PLAN.md`, repair references, and inspect the deletion. Its recorded
local-only cleanup note is superseded by the user's standing instruction to push
the finished work to main; push only after the final deletion audit. Keep this
plan and durable status independent of the temporary task directory.

**Exit:** no accepted work is silently deferred, all issue/task closure claims
have evidence, and the final checkout and main branch are accounted for.

## Execution and turnaround rules

- Use Zig 0.17.0 with `-Dllvm=false` for development and native test
  compilation. Use LLVM for the release compiler and release measurements.
- Use the 300-second `check:dev` cycle while editing; add the affected laws to
  its explicit family. Select tests from the already-built native inventory
  instead of compiling separate executables for each filter.
- Run one heavy job at a time under the shared memory/lock wrapper. Avoid
  queuing another build behind it; do read-only review and documentation while
  waiting. Keep unrelated code edits out of a qualification run.
- Run the full required gate before each coherent compiler milestone commit,
  then push under the standing authorization. The last recorded full gate took
  about eleven minutes; five minutes is the development feedback budget, not a
  promise for exhaustive release qualification.
- Reuse a successful gate only while its relevant inputs remain unchanged. Do
  not rerun compiler tests for documentation-only edits.
- At each milestone publish the commit, acceptance rows, test/evidence paths,
  measured result, and next bounded step. Stop for a real unresolved design
  choice or repeated failure with no new hypothesis; an anticipated refactor
  alone is not a reason to stop.

The first implementation action is milestone 1: preserve and reconcile the
existing candidate against main before introducing more language/runtime work.
