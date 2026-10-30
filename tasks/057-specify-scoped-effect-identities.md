# 057 — Specify scoped effect identities

## Status, dependencies, and originating requirements

- **Status:** Complete — durable reviewed design at `07cbc62`; 058–059 remain
  separate implementations.
- **Dependencies:** [052](052-implement-opaque-types-and-privacy.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 4 / generic scoped
  effects. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Specify distinct same-typed effect instances, generativity, handler subtraction,
capability capture and identity transport.

## Starting point

[compiler/guide.md](../compiler/guide.md#effect-families-and-scoped-state)
supports closed family instances and rejects symbolic generic effect labels.
[provider_chain.zig](../zig-native/src/backend/provider_chain.zig) and
[request_runtime.zig](../zig-native/src/runtime/request_runtime.zig) route
current operations.

## Implementation checklist

- [x] Define source syntax and identity representation for fresh instances,
      symbolic operation arguments and scoped capabilities.
- [x] Settle effect-row equality/subtraction, repeated labels, provider
      selection and generative identity scope.
- [x] Specify capture, import, portable evidence and invalidation rules, plus
      diagnostics for invalid escape or unresolved identity.
- [x] Document nesting and higher-order examples for implementation and
      capability checking.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Trace two same-typed instances under nested handlers, generic wrappers and
  captured callbacks/demands.
- Review identity transport through modules and compiled artifacts without
  merging fresh instances.

## Acceptance criteria

- [x] Durable syntax, identity/effect semantics, representation and
      compatibility are settled.
- [x] Tasks 058–059 have exact routing, subtraction and escape acceptance cases.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `07cbc62`.
- Validation: Markdown formatting, 19 local links and 23 declarative identity/
  provider/row/escape traces pass. Independent runtime review addressed explicit
  pre-exposure cleanup, revocation before retirement, pending retry versus
  ready/terminal memos, JSPI rejection and longer-lived/private journal sinks.
  Traces live in ignored `build/bench/scoped-effects-057/review.json`; they are
  design checks, not executed Blot laws.
- Comparison: documentation only; no executable performance claim. 058–059 have
  explicit source/artifact/OOM, sync/JSPI and paired cost acceptance cases.
- Remaining limitations: all proposed syntax, identity routing and escape
  checking await 058–059. The guide preserves current executable behavior.
- Durable record: [Scoped effect identities](../zig-native/SCOPED_EFFECTS.md).
