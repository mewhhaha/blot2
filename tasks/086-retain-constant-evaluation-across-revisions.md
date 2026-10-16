# 086 — Retain constant evaluation across revisions

## Status, dependencies, and originating requirements

- **Status:** In progress — owner approved the constant-receipt design on12
  October2026; no completion is claimed.
- **Dependencies:** [023](023-narrow-literal-edit-invalidation.md)
- **Originating requirements:** discovered while qualifying task
  [023](023-narrow-literal-edit-invalidation.md); PLAN: Hill 6 / literal edits
  under 30 ms. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Re-evaluate only constants whose inputs changed; reuse every other evaluated
constant, including its serialized data, across retained revisions.

## Starting point

Task 023 keeps code and metadata of unaffected bodies, but every revision still
evaluates all constants in a new Session. A separate session profiled a
top-level scalar literal edit on the current gdev checkout with the `fbe28c8`
compiler at about 1.1 s CPU; about 60% was `core_eval.Session.prepare` →
`Session.constant` re-evaluating entry constants. The largest was the `sandbox`
constant in gdev's main module (213,919 region nodes, 3,638 scopes, 276 ms
alone). The same session later measured a flat `generate_us` of about 740 ms
whether 0% or 90% of named functions were reused, consistent with evaluation
rather than code generation dominating. Task 022 already replays graph-equal
constant children of retained fragments but re-serializes them.

An instrumented copy of the task-085 compiler on the frozen gdev copy (11
October 2026) evaluated 594 constants per retained literal edit in about 700 ms.
One entry constant, `sandbox` in the main module, took 99.4% of that, and 98% of
its time was inference nested in its evaluation rather than value evaluation
(about 15 ms). Its value never read the edited constant; it reaches it only
through function constants that compile-time evaluation does not apply. The
other 593 constants took under 5 ms together. Reusing `sandbox` therefore means
publishing a constant slot and its fuel from a validated receipt, which the
value-template boundary in
[source_value_template.zig](../zig-native/src/reuse/source_value_template.zig)
explicitly excludes today ("does not publish constant slots, callable
certificates, or skip source fuel"). The owner approved the dedicated
[constant-receipt design](../zig-native/CONSTANT_REUSE.md) on12 October2026. The
existing value-template transport boundary stays unchanged.

Task 088 (`86db5b1`) later let `sandbox`'s principal region replay from its
recorded inputs: a gdev literal edit now costs about 570 ms CPU with 240 ms of
inference in total. The constant-evaluation profile above predates that change
and must be measured again before this design.

## Implementation checklist

- [ ] Record each constant's exact value dependencies (source bodies, reads,
      providers, generative identities and fuel/failure outcomes).
- [ ] Reuse an evaluated value and its data only when all dependencies are
      unchanged; keep demand cells, generative values and failures exact.
- [ ] Preserve evaluation order, diagnostics, failed-revision rollback and
      fresh/retained byte equality.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Edit unrelated literals, a constant's own input, a provider and a trapping
  constant; compare executed results and bytes with fresh builds.
- Measure retained literal edits on workloads with large entry constants and on
  gdev when available.

## Acceptance criteria

- [ ] Unaffected constants are not re-evaluated across admitted edits, with
      counters and laws.
- [ ] The literal-edit target is measured or remains explicitly open for task
      [101](101-reach-the-literal-edit-target.md).
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

Compiler6a57437 qualifies exact primitive constant and ready partial-member
receipts. Full native/OOM,973 guests,8 budgets and355-file zero analyzer pass.
Seven paired primitive/member controls preserve bytes/fuel and show modest
retained gains; the captured93-unit project has zero dedicated bookkeeping and
no constant payoff. Its roughly5% retained CPU regression is late ownership
fallback assembly, not a fulfilled edit target.

[The durable merged record](../zig-native/ITERATOR_CONSTANTS_QUALIFICATION.md)
pins actual release/source, measurements, failures and ordinary fallbacks.
Growth/enclosing judgments, typed-view publication, broader relocation/data
retention and portable member authority remain open. Task086 is incomplete.

The current uncommitted continuation owns ordered ordinary dependency reads,
reachable typed-view publication and compound collection buffer frontiers. Any
post-demand mismatch destroys the attempt before one ordinary retry; OOM is
never retried. Exact local callable templates use the tape's separate executed
source/read owner. Ordinary graph inspection keeps transitive admission.

The eight-file delta is frozen in
`/var/tmp/blot2-task086-demand-frontier-freeze-v2-20261015`, patch SHA-256
`2a1cb59e6cc374e861da4250b3c63231b61b41a02d25badc396b5d241d6fb202`. Ten focused
native laws and seven guest groups pass in isolation; root integration passes
three frontier/view ownership laws and the same seven guest groups. Complete
deterministic allocation-failure controls cover retry teardown, frontiers,
suspended dependency spans, views and relocated closure descriptors.

One captured development pair preserves exact fresh/edit/revert bytes and 70,330
source steps. Retained edits replay 61,383 local steps in eleven hits, with zero
declines/retries. CPU is near parity, not a speedup. Snapshot copying falls from
1,073,244 to 615,084 bytes; copied metadata falls from 2,059,944 to 1,660,593
bytes. Unchanged inference and backend preparation dominate the remaining cost.
General authority admission and final combined release qualification remain
open.
