# 058 — Implement effect instances and subtraction

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed language-qualification rows by
  owner decision on 15 October 2026; waiting for a passing full gate on current
  source.
- **Dependencies:** [057](057-specify-scoped-effect-identities.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 4 / effect
  identities and handlers. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

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

- [ ] Implement instance creation and identity-preserving type/effect evidence
      across generic calls and captures.
- [ ] Subtract only the handled instance from effect requirements and preserve
      multiplicity/chronological row behavior.
- [ ] Route runtime operations to the correct provider and encode transportable
      identities in dependencies without serializing fresh authority improperly.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Nest two same-typed instances and prove each read/write reaches its own
  handler; forward unhandled instances outward.
- Test symbolic generic labels, aliases, higher-order calls, request handlers
  and same-spelled imported effects.
- Check source/dependency parity, retained identity changes, OOM and sync/JSPI
  behavior.

## Acceptance criteria

- [ ] Same-typed instances remain distinct through every compiler/runtime stage.
- [ ] Handler subtraction removes exactly the handled capability and preserves
      valid effects and diagnostics.
- [ ] Applicable checks pass and completion evidence records remaining
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
freeze `3548546c…`, but the current working tree failed 20 native laws on the
evening of 15 October, so completion waits for a passing gate on current source.
The original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`; regenerate the row-to-law mapping from the passing
gate's native test names and guest JUnit report and record it durably in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md).

## Completion evidence

- Partial checkpoint: `0d77afc`; task 058 remains in progress.
- Validation: full gate passes 1,701 native laws, 1,075 guests, 1,050 complete
  OOM sweeps plus two expected-error harness laws and zero analyzer findings
  across 375 files.
- Pure product/record helpers and multi-input Unit callback invocation preserve
  exact input owners, row multiplicity and decoded private-body validation.
  General capture/result/store graphs and public generative schemes stay open.
- Captured fresh/edit/revert CPU ratios are 1.0049/1.0074/1.0051 against the
  preceding product-only checkpoint. Public outputs and allocations are exact;
  see [merged qualification](../zig-native/CONTINUATION_QUALIFICATION.md).
- Durable record:
  [scoped effects](../zig-native/SCOPED_EFFECTS_QUALIFICATION.md).
