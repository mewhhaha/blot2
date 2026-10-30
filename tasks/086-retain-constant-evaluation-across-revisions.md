# 086 — Retain constant evaluation across revisions

## Status, dependencies, and originating requirements

- **Status:** Complete — closed as not needed on the pinned workload by the 23
  October 2026 measurement gate. Existing receipt slices remain.
- **19 October 2026:** the compile-time hills cut the gdev literal edit to about
  1.0 s, from 1.88 s before CT9. Results for CT9, CT12, CT14–CT17, CT22, CT27
  and CT89 are in
  [COMPILE_HILLS.md](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILE_HILLS.md).
- **Dependencies:** [023](023-narrow-literal-edit-invalidation.md)
- **Originating requirements:** discovered while qualifying task
  [023](023-narrow-literal-edit-invalidation.md); PLAN: Hill 6 / literal edits
  under 30 ms. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Re-evaluate only constants whose inputs changed, and reuse every other evaluated
constant with its serialized data across retained revisions, if and only if a
release measurement on the pinned workload shows that re-evaluating unaffected
constants still costs enough to matter. Otherwise close the task as not needed,
keeping the receipt slices that have already landed.

## Starting point

**Original motivation.** With the `fbe28c8` compiler, a top-level scalar literal
edit on the then-current gdev checkout cost about 1.1 s CPU; about 60% was
`core_eval.Session.prepare` → `Session.constant` re-evaluating entry constants,
led by gdev's `sandbox` constant (213,919 region nodes, 3,638 scopes, 276 ms
alone). On 11 October 2026 an instrumented task-085 compiler on the frozen gdev
copy evaluated 594 constants per retained literal edit in about 700 ms;
`sandbox` took 99.4% of that, and 98% of its time was inference nested in its
evaluation rather than value evaluation (about 15 ms). The other 593 constants
took under 5 ms together. The owner approved the dedicated
[constant-receipt design](../zig-native/CONSTANT_REUSE.md) on 12 October 2026;
the value-template boundary in
[source_value_template.zig](../zig-native/src/reuse/source_value_template.zig)
stays unchanged.

**Findings on 17 October 2026: the targeted cost no longer dominates the latest
recorded measurements.**

- Task 088 (`86db5b1`) made `sandbox`'s principal region replay from recorded
  inputs; a gdev literal edit fell to about 570 ms CPU with 240 ms of inference
  ([summary-job cost](../zig-native/CALL_SUMMARIES.md#summary-job-cost-11-october-2026)
  notes that 086's profile needs re-measuring).
- After task 093 (`aef65e7`), constant evaluation (152 ms) plus constant
  serialization (120 ms) were still about 61% of a 440 ms gdev edit
  ([attribution](../zig-native/RETAINED_EDIT_COST.md#attribution)). That
  workload cannot be re-measured: the frozen gdev manifest was waived on 11
  October and `build/` was removed on 15 October (see
  [README](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#task-index)).
- On the current 93-unit captured project, an LLVM release profile of a retained
  scalar edit at `2798ff9` reports 51–53 ms of constant work and 19 ms of value
  evaluation against 545–549 ms of inference
  ([historical attribution](../zig-native/CONSTANT_REUSE.md#historical-attribution-before-the-current-continuation)).
  The 14 October release screen measures a median edit of 843 ms (revert 733 ms)
  with every constant-receipt counter at zero
  ([qualified continuation](../zig-native/CONTINUATION_QUALIFICATION.md#qualified-continuation-14-october-2026)).
  Against that median, 51–53 ms would be about 6%, though the two numbers come
  from different compilers.
- At `6a57437` the captured project had no receipt activity and a roughly 5%
  retained regression from late ownership fallback assembly
  ([measured costs](../zig-native/ITERATOR_CONSTANTS_QUALIFICATION.md#measured-costs)).
  The 15 October compound replay reaches eleven hits and 61,383 replayed steps
  on that project at near-parity CPU; unchanged inference and backend
  preparation dominate the rest. The largest constant (57,019 of 70,330 source
  steps) has a nominal result that is excluded before recording
  ([qualified combined run](../zig-native/ITERATION_COST.md#qualified-combined-run-14-october-2026)).

The 60% share that motivated this task was measured on the frozen gdev copy,
which can no longer be re-measured. On the current captured project, the
recorded constant-work clock is roughly a tenth of inference alone, but that
clock may not include static-data serialization (120 ms of the gdev edit at
`aef65e7`). The measurement gate below therefore counts both, and further
receipt authority (compound nominal values, growth/enclosing judgments,
typed-view publication, broader relocation and serialized-data retention,
portable member authority) is built only if the gate justifies it.

## Implementation checklist

- [x] Run the measurement gate below on current main and record it in
      [CONSTANT_REUSE.md](../zig-native/CONSTANT_REUSE.md) before any further
      receipt work.
- [x] Not required by the measured gate: record each constant's exact value
      dependencies (source bodies, reads, providers, generative identities and
      fuel/failure outcomes).
- [x] Not required by the measured gate: reuse an evaluated value and its data
      only when all dependencies are unchanged; keep demand cells, generative
      values and failures exact.
- [x] Existing implementations preserve evaluation order, diagnostics,
      failed-revision rollback and fresh/retained byte equality.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

**Measurement gate.**

- Workload: the workload task [084](084-qualify-the-complete-program.md) pins;
  until it exists, the 93-unit captured project with its 415 recorded input pins
  ([qualified continuation](../zig-native/CONTINUATION_QUALIFICATION.md#qualified-continuation-15-october-2026)).
  Synthetic large-constant workloads support laws, not this decision.
- Compiler: an LLVM release build of current main, with persistence settings
  stated. A measurement taken before the latest change to retained-edit code
  does not count.
- Runs: at least seven alternating paired retained top-level scalar literal
  edits, reporting medians of edits 2 onward, with child user plus system CPU, a
  phase profile (`blotc build ... --profile` or the project server's profile)
  and the constant-receipt counters.
- Quantity C: CPU per edit spent evaluating constants whose recorded inputs did
  not change, including inference nested in that evaluation, plus re-serializing
  their static data. Report nested inference and receipt hits/declines
  separately.
- Threshold: the remaining work is justified only if C is at least 20% of the
  median retained literal-edit CPU, or C is the largest single attributed phase.
  Below that, close this task as not needed. A cost under 20% can make an edit
  at most 1.25× faster, while task 101 needs roughly 28× (843 → 30 ms), so it
  does not decide what to work on first. If larger phases are removed later,
  task 101's attribution re-measures C and can add a new constant task.

If the work proceeds:

- Edit unrelated literals, a constant's own input, a provider and a trapping
  constant; compare executed results and bytes with fresh builds.
- Measure retained literal edits on the gate workload against the same control.

## Acceptance criteria

- [x] The measurement gate is recorded durably with workload pins, compiler
      identity, distributions and C.
- [x] Either C is at or above the threshold and unaffected constants are not
      re-evaluated across admitted edits, with counters and laws, or C is below
      the threshold and the task is closed as not needed with C handed to task
      [101](101-reach-the-literal-edit-target.md)'s attribution.
- [x] The literal-edit target is measured or remains explicitly open for task
      [101](101-reach-the-literal-edit-target.md).
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Landed receipt slices (kept either way): `6a57437` exact primitive constant
  and ready partial-member receipts (full native/OOM gate, 973 guests, eight
  budgets, 355 analyzer files at zero; modest primitive/member retained gains);
  `b145c5e` sparse inspection (large-snapshot retained CPU 18.005 → 15.158 ms);
  `38e822d` primitive growth receipts (retained 1.630 → 1.172 ms at 512
  elements, 3.710 → 1.746 ms at 2,048). See
  [constant receipts](../zig-native/CONSTANT_REUSE.md) and
  [the merged record](../zig-native/ITERATOR_CONSTANTS_QUALIFICATION.md).
- Compound replay (ordered dependency reads, reachable typed views, collection
  buffer frontiers, one ordinary retry after a post-demand mismatch, OOM never
  retried) landed in `23a934f`. Its delta was frozen as
  `/var/tmp/blot2-task086-demand-frontier-freeze-v2-20261015`, patch SHA-256
  `2a1cb59e6cc374e861da4250b3c63231b61b41a02d25badc396b5d241d6fb202`; ten
  focused native laws and seven guest groups passed, with complete
  allocation-failure controls. One captured development pair preserves exact
  fresh/edit/revert bytes and 70,330 source steps; retained edits replay 61,383
  steps in eleven hits with zero declines or retries. CPU is near parity.
  Snapshot copying falls from 1,073,244 to 615,084 bytes and copied metadata
  from 2,059,944 to 1,660,593 bytes.
- Remaining: the measurement gate, then either the open receipt authority listed
  in the starting point or closure as not needed.
- The 20 October historical CPU-weighted smoke reanalysis separates runtime
  function emission from constant evaluation and static serialization. Its
  samples do not align with qualifying edit windows, so Quantity C remains
  unmeasured. The
  [cloud preparation](../zig-native/CONSTANT_REUSE.md#cloud-measurement-preparation-20-october-2026)
  records the observed contexts, pins and both comparisons needed for closure.
- Durable record: [constant receipts](../zig-native/CONSTANT_REUSE.md).

### Final gate, 23 October 2026

Seven paired retained campaigns and seven complete-stack profiles qualify the
current LLVM compiler. The conservative sampled C estimate includes changed
inputs and all missing coverage: its median is 14.9% of later-edit CPU, or 16.9%
with a 20-ms tick-accounting sensitivity margin. Other inference and
runtime-function reconstruction are larger. No new receipt authority is needed.
All fresh/retained/revert witnesses pass; current source has the complete
2,525-native/1,640-guest gate. The published profiling tools pass type/lint
checks, executed smoke and known attribution controls.

See the
[durable decision and raw evidence](../zig-native/CONSTANT_REUSE.md#measurement-gate-resolved-23-october-2026).
The 30-ms literal-edit target remains open in task 101.
