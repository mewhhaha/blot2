# 065 — Implement existential packages

## Status, dependencies, and originating requirements

- **Status:** Complete — closed on 17 October 2026 against the two package rows
  of
  [language qualification](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  gate at `05401a9`.
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

- [x] Check package creation against its abstract interface and introduce scoped
      abstract identities on unpacking.
- [x] Carry the required operations/evidence into specialization without
      exposing hidden representation.
- [x] Support heterogeneous collections and artifact transport with correct
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

- [x] Packages preserve abstraction and evidence through heterogeneous use and
      separate compilation.
- [x] Packing/unpacking diagnostics, identity and ownership satisfy the
      specified laws.
- [x] Applicable checks pass and completion evidence records remaining
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
freeze `3548546c…`. The 20 native-law failures seen on the evening of 15 October
were fixed in `23a934f`, and the gate at `05401a9` passed on 17 October. The
original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`. The row-to-law mapping regenerated from that gate's
native test names and guest JUnit report is recorded in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026).

## Completion evidence

- Revision: committed source at `05401a9` (17 October 2026), the tree the gate
  ran on; `23a934f` also passed the full gate. The closure itself is
  documentation only.
- Validation (Zig 0.17.0): the full gate at `05401a9` passes 2,355 native laws
  in two shards with zero failures and zero leaks, 1,501 guest tests with zero
  failures, and the harness and smoke phases; `deno task lint:zig` reports zero
  zig-analyzer findings over 486 files. The run's final native-input check
  refused only because another session edited `../gdev` during the run; every
  phase passed. The earlier gate at `23a934f` passed 2,354 native laws with zero
  leaks, 1,486 guest, 28 harness, 21 preflight and 48 smoke tests and zero
  analyzer findings.
- Row-to-law mapping: the
  [index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026)
  names 22 native laws and 19 guest tests for the eight requirements of the two
  package rows; all passed in the `05401a9` gate.
- Comparison: performance measurement does not apply; the closed rows set no
  performance target and no speedup is claimed.
- Remaining limitations: affine values hidden in unrestricted type binders
  remain an intentional rejection; an existential witness stays unrestricted
  even when it is phantom. Forms outside the rows are excluded scope under the
  owner decision of 15 October 2026 (closed acceptance above;
  [README owner decisions](README.md#task-index)), not open work. Such forms,
  including nested package conversion and complete dictionary artifact reuse,
  reject or decline conservatively. Packages expose no representation: direct
  reflection and hidden value escape reject.
- Durable record:
  [row-to-law index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  [implementation record](../zig-native/POLYMORPHIC_PACKAGE_IMPLEMENTATION.md)
  and the [polymorphic package design](../zig-native/POLYMORPHIC_PACKAGES.md).
