# 065 — Implement existential packages

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed language-qualification rows by
  owner decision on 15 October 2026; waiting for a passing full gate on current
  source.
- **Dependencies:** [064](064-check-higher-rank-types-and-skolems.md),
  [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 7 / existential
  packages. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement packing, unpacking, evidence passing, specialization and heterogeneous
package use across portable interfaces.

## Starting point

Task 064 provides skolem checking; task 020 portable semantic graphs.
[core.zig](../zig-native/src/check/core.zig),
[specialization.zig](../zig-native/src/eval/specialization.zig) and runtime
layouts must represent the package design from task 063.

## Implementation checklist

- [ ] Check package creation against its abstract interface and introduce scoped
      abstract identities on unpacking.
- [ ] Carry the required operations/evidence into specialization without
      exposing hidden representation.
- [ ] Support heterogeneous collections and artifact transport with correct
      capture/resource ownership.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Pack different implementations behind one interface, store them together and
  invoke their permitted operations.
- Reject representation access, wrong evidence and hidden-type escape through
  results/captures.
- Round-trip source/dependency/checkpoint paths and verify retained edits,
  failure recovery and package destruction.

## Acceptance criteria

- [ ] Packages preserve abstraction and evidence through heterogeneous use and
      separate compilation.
- [ ] Packing/unpacking diagnostics, identity and ownership satisfy the
      specified laws.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the rows of
[language qualification](../zig-native/LANGUAGE_QUALIFICATION.md) listed below.
Forms outside these rows ("general" captures, stores, transports and shapes) are
not required work: they must reject or decline conservatively with a stable
diagnostic and are recorded as limitations. The acceptance criteria below are
read against these rows.

| Contract | Qualified requirements                                     |
| -------- | ---------------------------------------------------------- |
| Packages | Sealing, heterogeneous carriers, openings, stored evidence |
| Packages | Resealing, associated payloads, captures, affine ownership |

Intentional rejections under the normative design: affine values hidden in
unrestricted type binders.

The task completes when every native law and guest test mapped to these rows
passes in the full compiler gate (`deno task test:compiler` and
`deno task lint:zig`) on the committed source. The rows passed in the 15 October
freeze `3548546c…`, but the current working tree failed 20 native laws on the
evening of 15 October, so completion waits for a passing gate on current source.
The original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`; regenerate the row-to-law mapping from the passing
gate's native test names and guest JUnit report and record it durably in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md).

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: focused native ownership/binder laws and both-tier executed
  package groups pass; see the durable record. The full compiler gate remains
  required.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: portable rank publication, row/region/predicate
  evidence, qualified drop contracts and full release qualification.
- Durable record:
  [implementation and remaining qualification](../zig-native/POLYMORPHIC_PACKAGE_IMPLEMENTATION.md).
