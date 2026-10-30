# 058 — Implement effect instances and subtraction

## Status, dependencies, and originating requirements

- **Status:** Complete — closed on 17 October 2026 against the three
  scoped-identity rows of
  [language qualification](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  gate at `05401a9`.
- **Dependencies:** [057](057-specify-scoped-effect-identities.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 4 / effect
  identities and handlers. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Carry scoped effect-instance identities through checking, evidence,
specialization and runtime handlers.

## Starting point

[types.zig](../zig-native/src/check/types.zig),
[check.zig](../zig-native/src/check/check.zig),
[provider_chain.zig](../zig-native/src/backend/provider_chain.zig) and
[request_runtime.zig](../zig-native/src/runtime/request_runtime.zig) currently
identify closed operations. Task 057 defines symbolic arguments, generative
instances and row subtraction.

## Implementation checklist

- [x] Implement instance creation and identity-preserving type/effect evidence
      across generic calls and captures.
- [x] Subtract only the handled instance from effect requirements and preserve
      multiplicity/chronological row behavior.
- [x] Route runtime operations to the correct provider and encode transportable
      identities in dependencies without serializing fresh authority improperly.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Nest two same-typed instances and prove each read/write reaches its own
  handler; forward unhandled instances outward.
- Test symbolic generic labels, aliases, higher-order calls, request handlers
  and same-spelled imported effects.
- Check source/dependency parity, retained identity changes, OOM and sync/JSPI
  behavior.

## Acceptance criteria

- [x] Same-typed instances remain distinct through every compiler/runtime stage.
- [x] Handler subtraction removes exactly the handled capability and preserves
      valid effects and diagnostics.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the rows of
[language qualification](../zig-native/LANGUAGE_QUALIFICATION.md) listed below.
Forms outside these rows ("general" captures, stores, transports and shapes) are
not required work: they must reject or decline conservatively with a stable
diagnostic and are recorded as limitations. The acceptance criteria below are
read against these rows.

| Contract          | Qualified requirements                                         |
| ----------------- | -------------------------------------------------------------- |
| Scoped identities | Fresh owners, routing, shadowing, forwarding, symbolic rows    |
| Scoped identities | Aliases, dependent/generative contracts, multi-input callbacks |
| Scoped identities | Requests, cancellation, revocation, imported recovery          |

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
  documentation only. Earlier implementation checkpoints include `0d77afc` and
  `10fab46`.
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
  names 32 native laws and 24 guest tests for the twelve requirements of the
  three scoped-identity rows; all passed in the `05401a9` gate.
- Comparison: the design's required measurement against closed static controls
  (seven alternating compiler pairs, 31 warmed guest pairs) is recorded in
  [measured scope cost](../zig-native/LANGUAGE_QUALIFICATION.md#measured-scope-cost):
  median fresh compiler CPU for two fresh scoped State owners is 1.0951× the
  static control, and warmed guest calls cost 1.2605× in sync and 1.0807× in
  JSPI mode. The earlier partial checkpoint `0d77afc` measured fresh/edit/revert
  CPU ratios of 1.0049/1.0074/1.0051 against the preceding product-only
  checkpoint
  ([merged qualification](../zig-native/CONTINUATION_QUALIFICATION.md)). This
  closure changes no code, so no new comparison applies.
- Remaining limitations: forms outside the rows are excluded scope under the
  owner decision of 15 October 2026 (closed acceptance above;
  [README owner decisions](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#task-index)),
  not open work. General capture/result/store graphs, general higher-order and
  anonymous invocation binder transport, and public generative selection schemes
  beyond the admitted invocation-version forms reject or decline conservatively
  with stable diagnostics
  ([conservative limits](../zig-native/SCOPED_EFFECTS_QUALIFICATION.md#conservative-limits)).
  Live scoped authority never enters portable artifacts: scoped receipts decline
  import, and checkpoints keep validated symbolic binders that create fresh
  owners when run. Scoped routing costs about 26% more per warmed sync guest
  call than static families on the measured workload.
- Durable record:
  [row-to-law index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  [scoped effect qualification](../zig-native/SCOPED_EFFECTS_QUALIFICATION.md)
  and the [scoped effects design](../zig-native/SCOPED_EFFECTS.md).
