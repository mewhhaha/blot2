# 029 — Remove function indices from reuse keys

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [018](018-migrate-executable-reuse-queries.md),
  [028](028-make-emission-consume-resolved-bodies.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / stable
  optimized-body identities. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Use stable symbolic call/body identities for optimized-body reuse and relocate
final indices during assembly.

## Starting point

[optimized_bodies.zig](../zig-native/src/optimized_bodies.zig),
[runtime_function_key.zig](../zig-native/src/runtime_function_key.zig) and
[runtime_body_relocation.zig](../zig-native/src/runtime_body_relocation.zig)
currently include incidental function positions in reuse matching, despite
existing relocation proofs.

## Implementation checklist

- [ ] Replace positional identities in stored keys with stable symbolic bodies
      and complete callee/signature/lifetime dependencies.
- [ ] Relocate direct calls and table/global references on owned output copies
      during final assembly, validating cycles and consistent mappings.
- [ ] Decline ambiguous or exhausted relocation proofs and preserve separate
      public Wasm identities.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Insert, remove and reorder unrelated functions and compare cache reuse plus
  final fresh/retained bytes.
- Test recursive call graphs, imports, changed callee lifetime facts, duplicate
  bodies and indirect table slots.
- Exercise allocation failure and failed assembly without modifying retained
  optimized bodies.

## Acceptance criteria

- [ ] Incidental function-index changes no longer invalidate otherwise identical
      optimized bodies.
- [ ] Final relocation remains exact and rejects changed or ambiguous semantic
      targets.
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
