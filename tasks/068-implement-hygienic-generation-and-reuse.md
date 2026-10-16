# 068 — Implement hygienic generation and reuse

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed typed-staging acceptance
  traces by owner decision on 15 October 2026; trace-to-law index and a passing
  full gate on current source remain.
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

- [ ] Generate declarations with hygienic lexical identities across shadowing,
      imports and multiple expansion sites.
- [ ] Record every code/descriptor/input dependency and include generated body
      semantics in executable invalidation.
- [ ] Reuse only complete generated results with matching inputs; preserve
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

- [ ] Generated code preserves intended bindings without accidental capture.
- [ ] Exact staging inputs govern reuse and every failed generation leaves the
      previous revision usable.
- [ ] Applicable checks pass and completion evidence records remaining
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
[STAGING_QUALIFICATION.md](../zig-native/STAGING_QUALIFICATION.md). No such
trace-to-law index exists yet; build it from the passing gate.

## Completion evidence

The statement-if follow-on preserves branch shadowing and independent emissions
through both-tier source/archive/checkpoint/restart, edited helpers and failed
revisions. Six native and twelve selected staging guest groups pass; fresh/edit/
restart uses31 work steps and unchanged/recovery uses zero. Exact pins:
`build/bench/finish-program-20261014/staging-statement-if/`. General generation
and the final full gate remain open.

- Commit: pending; record the local milestone revision.
- Validation: seven staging guest laws pass. The combined imported law compares
  fresh, retained and restarted Wasm after fixed-type scalar input edits and
  quoted executable-body edits; three emissions preserve shadowed locals. A
  failing second expansion preserves the last accepted executable. Two callable
  descriptor native laws include exhaustive allocation failure. Full compiler
  qualification remains pending.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: general qualified producer transport and population/
  edit cost qualification remain open. Staged fragments conservatively rebuild
  when an entire unchanged output cannot be reused.
- Durable record:
  [staging qualification](../zig-native/STAGING_QUALIFICATION.md).

The 14 October follow-on verifies tracked JSON asset bytes, imported generic
helpers and ordinary nominal lifts. Same-type byte/body edits match fresh
execution; invalid JSON, wrong payload types and illegal stage crossings
preserve the accepted output. Corrected inputs and restarted compilers agree in
the twelve-group staging guest screen. Portable substitution/payload corruption
and complete restart allocation-failure checks pass. This remains focused
evidence pending general declaration/source-map work, cost qualification and the
final compiler gate.

Immutable producer-local data now has exact executable-body ownership too.
Imported data edits and failed helper revisions preserve fresh bytes, fuel,
last-good execution and restart in the three changed helper groups. Runtime,
foreign and cyclic owner controls reject; focused ownership/OOM checks pass.

Collection helper edits now have the same owned body and input checks. Both
codegen tiers preserve exact fresh/retained/restart output at 76 steps; a
failing out-of-bounds read preserves the accepted output, and correction uses
zero work. Portable roundtrip and forged-shape controls pass. Exact pins are in
`build/bench/finish-program-20261014/staging-collection-helpers/`.

Nominal field-reader edits preserve exact family, constructor and physical-field
ownership too. Both codegen tiers match fresh/restart output at 40 steps;
unchanged and recovered inputs use zero work. Complete portable roundtrip OOM
and forged same-type field paths pass. The delta and pins are in
`build/bench/finish-program-20261014/staging-nominal-reads/`; final
qualification remains outstanding.
