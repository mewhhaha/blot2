# 061 — Check usage and call multiplicity

## Status, dependencies, and originating requirements

- **Status:** Complete — closed on 17 October 2026 against the two usage rows of
  [language qualification](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  gate at `05401a9`.
- **Dependencies:** [060](060-specify-usage-and-lifetime-contracts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 5 / checked usage
  and invocation. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Enforce the specified usage and invocation rules across branches, loops,
aliases, captures and higher-order calls.

## Starting point

Task 060 defines source contracts;
[check.zig](../zig-native/src/check/check.zig), resolved ownership and summary
evidence provide implementation boundaries. Existing uniqueness optimizations
remain insufficient as source-level proofs.

## Implementation checklist

- [x] Track uses and ownership flow by binding identity, joining branches and
      iterating loop facts conservatively.
- [x] Check unique/shared and borrowed uses plus once/many function invocation
      and capture contracts.
- [x] Import/export complete usage evidence and reject hidden duplication or
      borrow escape through generic/higher-order calls.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Test valid exclusive transfer, sharing, scoped borrowing and specified
  once/many callbacks.
- Reject double use, duplicate aliases, illegal loop invocation, incompatible
  branches and captured borrowed escapes.
- Exercise imported contracts, polymorphic calls, failed edits, OOM and bounded
  recursive analysis.

## Acceptance criteria

- [x] Every specified usage and multiplicity law is enforced at source and
      dependency boundaries.
- [x] Valid programs remain accepted and diagnostics identify the conflicting
      use or lifetime.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the rows of
[language qualification](../zig-native/LANGUAGE_QUALIFICATION.md) listed below.
Forms outside these rows ("general" captures, stores, transports and shapes) are
not required work: they must reject or decline conservatively with a stable
diagnostic and are recorded as limitations. The acceptance criteria below are
read against these rows.

| Contract | Qualified requirements                      |
| -------- | ------------------------------------------- |
| Usage    | Moves, aliases, branches, loops, once/many  |
| Usage    | Loans, sharing, qualified polymorphic calls |

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
  names 25 native laws and 9 guest tests for the eight requirements of the two
  usage rows; all passed in the `05401a9` gate.
- Implemented at the focused checkpoints (Zig 0.17.0; later continuations in the
  durable record supersede some rejections listed here, such as owning public
  outputs): binding moves, affine captures, branch and exit joins, exact
  one-iteration bounds and direct lexical loans; contextual ownership for fresh
  primitive scalar and Array/List literals (existing unrestricted/shared
  bindings cannot become unique by annotation); explicit unique-to-shared
  conversion; returned once captures that keep their exact owning header.
  Unique/shared primitive and primitive Array/List values retain an explicit
  counted payload box through specialization, capture, portable artifacts and
  the owning input ABI; scoped loans expose only the payload with their exact
  region identity; unknown generic affine invocation, acquired owning public
  outputs and borrowed cleanup captures reject.
- Focused evidence: the isolated lexical loan freeze passed 19 native usage
  laws, three executed guest tests and zero analyzer findings over 354 selected
  Zig files; the paired scalar resource candidate passes the same laws and
  guests unchanged. Native/guest controls cover immutable mutants, complete
  allocation sweeps, imports, sync/JSPI, both tiers, failed revisions, archive
  and checkpoint restart, with zero roots/leases and flat warmed memory. An
  earlier isolated 416-file analyzer claim is withdrawn because its Zig/std
  backend was missing.
- Comparison: performance measurement does not apply; the closed rows set no
  performance target and no speedup is claimed. Usage analysis is bounded, for
  example by the laws "usage distinct-node cap remains bounded while repeated
  wide edges retain exact shape checks" and "usage nominal DAG scans consume one
  shared work budget".
- Remaining limitations: affine values hidden in unrestricted type binders
  remain an intentional rejection under the normative design. Forms outside the
  rows are excluded scope under the owner decision of 15 October 2026 (closed
  acceptance above;
  [README owner decisions](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#task-index)),
  not open work. Usage evidence for unannotated unknown generic or higher-order
  callees and nominal/package affinity beyond the checked contracts reject
  conservatively. An existing unrestricted or shared binding cannot become
  unique by annotation. Resource transfer and cleanup closed with task
  [062](062-implement-resource-cleanup-contracts.md).
- Durable record:
  [row-to-law index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026)
  and
  [bounded qualification](../zig-native/USAGE_CONTRACTS.md#bounded-implementation-and-qualification).
