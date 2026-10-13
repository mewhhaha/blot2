# 058 — Implement effect instances and subtraction

## Status, dependencies, and originating requirements

- **Status:** In progress — direct scopes, scoped requests, symbolic rows and
  exact generic capability/callback contracts, dependent arrow headers and exact
  two-input capability member helpers, bounded local selected identities and
  owned parameter footprints for pure product helpers are implemented. General
  multi-input bodies, generative selection schemes and general capture contracts
  remain open; see
  [qualification](../zig-native/SCOPED_EFFECTS_QUALIFICATION.md).
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

[types.zig](../zig-native/src/types.zig),
[check.zig](../zig-native/src/check.zig),
[provider_chain.zig](../zig-native/src/provider_chain.zig) and
[request_runtime.zig](../zig-native/src/request_runtime.zig) currently identify
closed operations. Task 057 defines symbolic arguments, generative instances and
row subtraction.

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
