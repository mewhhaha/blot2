# 064 — Check higher rank types and skolems

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [063](063-specify-polymorphic-packages.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 7 / annotated
  higher-rank checking. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement annotated higher-rank checking and precise skolem-escape rejection
with bounded work.

## Starting point

[types.zig](../zig-native/src/types.zig),
[check.zig](../zig-native/src/check.zig) and
[type_evidence.zig](../zig-native/src/type_evidence.zig) implement current
scheme instantiation. Task 063 defines higher-rank introduction/elimination and
scope rules.

## Implementation checklist

- [ ] Represent rank annotations and skolem scopes distinctly from ordinary
      inference variables.
- [ ] Check annotated polymorphic arguments/results and transport required
      evidence without generalizing local skolems.
- [ ] Bound recursive checking and preserve effect/capability/usage constraints
      in higher-order calls.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Accept rank-2 callbacks used at multiple concrete types and annotated imported
  higher-rank functions.
- Reject unannotated unsupported inference, escaped skolems, incompatible
  evidence and leaked scoped capabilities.
- Exercise diagnostic origins, dependency interfaces, failed edits and OOM
  cleanup.

## Acceptance criteria

- [ ] Annotated higher-rank programs obey the specified checking rules.
- [ ] Skolems never escape their scope and excessive/unsupported inference fails
      predictably with bounded work.
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
