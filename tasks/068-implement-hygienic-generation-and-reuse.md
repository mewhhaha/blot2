# 068 — Implement hygienic generation and reuse

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
- **Dependencies:** [067](067-implement-typed-code-and-descriptors.md),
  [024](024-apply-general-body-interface-cutoff.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 8 / hygiene and
  staged dependencies. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Preserve binding identity and exact tracked staged inputs through generation,
reuse and failed revisions.

## Starting point

Task 067 supplies typed code and task 024 body cutoffs.
[symbols.zig](../zig-native/src/parse/symbols.zig),
[declaration_dependencies.zig](../zig-native/src/reuse/declaration_dependencies.zig)
and [compiler/assets.ts](../compiler/assets.ts) provide identity and
tracked-input foundations.

## Implementation checklist

- [x] Generate declarations with hygienic lexical identities across shadowing,
      imports and multiple expansion sites.
- [x] Record every code/descriptor/input dependency and include generated body
      semantics in executable invalidation.
- [x] Reuse only complete generated results with matching inputs; preserve
      last-good artifacts on generation failure.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Generate same-spelled locals at different sites, capture intended outer
  bindings and compose imported generators.
- Edit a tracked input or generator body with an unchanged result type and
  verify affected callers rebuild.
- Compare fresh/retained/restart artifacts, failed-edit correction, OOM and
  unchanged-input reuse work.

## Acceptance criteria

- [x] Generated code preserves intended bindings without accidental capture.
- [x] Exact staging inputs govern reuse and every failed generation leaves the
      previous revision usable.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the acceptance traces of the
[typed staging design](../zig-native/TYPED_STAGING.md) listed below. The
acceptance criteria below are read against these traces.

| Acceptance trace                                                | Expected result                                          |
| --------------------------------------------------------------- | -------------------------------------------------------- |
| Two emissions each bind a local `value` beside a caller `value` | Three distinct lexical identities.                       |
| Asset bytes change, type remains U32                            | Rerun tracked generator and affected executable users.   |
| Generator fails after allocating a partial graph                | Keep prior code/assets usable; release candidate owners. |
| Restart from dependency/checkpoint code records                 | Same bindings, bytes, source fuel and failure behavior.  |

Forms outside these traces are not required work: general named
pattern/request/resolver helpers, captured loans and general resource captures,
general qualified producer transport and complete generated declaration/source
maps must reject or decline conservatively (rebuilding staged fragments is
acceptable) and are recorded as limitations. Population and retained costs are
measured and recorded; they are not a pass/fail target.

The task completes when each trace maps to named passing native laws or guest
tests in the full compiler gate on the committed source, recorded durably in
[STAGING_QUALIFICATION.md](../zig-native/STAGING_QUALIFICATION.md). The
[trace-to-law index](../zig-native/STAGING_QUALIFICATION.md#trace-to-law-index-17-october-2026)
built from the gate at `05401a9` is recorded there.

## Completion evidence

- Current local milestone: the commit containing this record; compiler and exact
  source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: All fixed hygiene/generation traces pass with fresh, retained and
  restart parity. Task 024 and the current population/edit cost record are
  complete.
- Remaining limits: General qualified producer transport and complete generated
  declaration maps remain documented limitations outside the closed acceptance
  scope.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Commit: pending; no local milestone revision is recorded for this task.
- Validation: the full gate at `05401a9` (17 October 2026) passes 2,355 native
  laws with zero leaks, 1,501 guest tests and zero analyzer findings over 486
  files. The
  [trace-to-law index](../zig-native/STAGING_QUALIFICATION.md#trace-to-law-index-17-october-2026)
  maps all four traces to named passing laws. Before closure: measure population
  and edit costs on gated source and record them in STAGING_QUALIFICATION.md
  (not a pass/fail target), and complete dependency
  [024](024-apply-general-body-interface-cutoff.md).
- Implemented (focused only): seven staging guest laws pass. The combined
  imported law compares fresh, retained and restarted Wasm after fixed-type
  scalar input edits and quoted executable-body edits; three emissions preserve
  shadowed locals; a failing second expansion preserves the last accepted
  executable. Two callable-descriptor native laws include exhaustive allocation
  failure.
- Follow-on helpers (14–15 October 2026, focused only): tracked JSON asset
  bytes, imported generic helpers and ordinary nominal lifts match fresh
  execution after same-type edits; invalid JSON, wrong payload types and illegal
  stage crossings preserve accepted output; corrected inputs and restarted
  compilers agree in the twelve-group staging guest screen. Statement-if helpers
  preserve branch shadowing and independent emissions (six native laws, twelve
  guest groups, 31 work steps; unchanged/recovery zero). Immutable
  producer-local data, collection helpers (76 steps) and nominal field-reader
  helpers (40 steps) keep exact fresh/retained/restart output in both codegen
  tiers; failed revisions preserve the accepted output and correction uses zero
  work. Pins were under `build/bench/finish-program-20261014/` (historical;
  `build/` was removed). The collection and field-reader slices are summarized
  in
  [task 067](067-implement-typed-code-and-descriptors.md#completion-evidence).
- Comparison: pending; population and edit costs must be measured and recorded,
  but they are not a pass/fail target.
- Remaining limitations: general qualified producer transport, complete
  generated declaration/source maps and cost qualification remain open. Staged
  fragments conservatively rebuild when an entire unchanged output cannot be
  reused.
- Durable record:
  [staging qualification](../zig-native/STAGING_QUALIFICATION.md).
