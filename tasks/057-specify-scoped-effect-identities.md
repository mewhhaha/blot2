# 057 — Specify scoped effect identities

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [052](052-implement-opaque-types-and-privacy.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 4 / generic scoped
  effects. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify distinct same-typed effect instances, generativity, handler subtraction,
capability capture and identity transport.

## Starting point

[compiler/guide.md](../compiler/guide.md#effect-families-and-scoped-state)
supports closed family instances and rejects symbolic generic effect labels.
[provider_chain.zig](../zig-native/src/provider_chain.zig) and
[request_runtime.zig](../zig-native/src/request_runtime.zig) route current
operations.

## Implementation checklist

- [ ] Define source syntax and identity representation for fresh instances,
      symbolic operation arguments and scoped capabilities.
- [ ] Settle effect-row equality/subtraction, repeated labels, provider
      selection and generative identity scope.
- [ ] Specify capture, import, portable evidence and invalidation rules, plus
      diagnostics for invalid escape or unresolved identity.
- [ ] Document nesting and higher-order examples for implementation and
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

- [ ] Durable syntax, identity/effect semantics, representation and
      compatibility are settled.
- [ ] Tasks 058–059 have exact routing, subtraction and escape acceptance cases.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
