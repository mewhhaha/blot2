# 025 — Resolve calls before emission

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [008](008-canonicalize-specialization-keys.md),
  [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / resolved
  backend boundary. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Represent selected direct and indirect calls completely before Wasm instruction
emission.

## Starting point

[specialization.zig](../zig-native/src/specialization.zig) already separates
some semantic selection, but
[core_backend.zig](../zig-native/src/core_backend.zig) still resolves calls
while emitting. [known_call.zig](../zig-native/src/known_call.zig) and
[layout_bridge.zig](../zig-native/src/layout_bridge.zig) carry current
call/layout knowledge.

## Implementation checklist

- [ ] Add a resolved call representation with target/body identity, direct or
      indirect signature, complete evidence, captures, effects and source
      origins.
- [ ] Resolve semantic obligations during preparation with explicit owned
      results, retaining conservative staged/open-row handling.
- [ ] Give unresolved calls authoritative diagnostics before emission and
      preserve evaluation order and argument witness sites.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare direct, indirect, partially applied, generic, captured and effectful
  calls with existing execution and diagnostics.
- Test unresolved evidence, incompatible signatures, nested forwarding and
  imported/portable calls.
- Exercise OOM during call preparation and ensure immutable Core and previous
  artifacts survive.

## Acceptance criteria

- [ ] Prepared calls contain everything emission needs for call selection and
      signature checking.
- [ ] No call semantics are guessed from machine types or selected anew by
      instruction emission.
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
