# 067 — Implement typed code and descriptors

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [066](066-specify-typed-staging.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 8 / typed code and
  descriptors. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Represent and check typed code values and descriptors through the ordinary
compiler stages.

## Starting point

[parser.zig](../zig-native/src/parser.zig),
[check.zig](../zig-native/src/check.zig), [core.zig](../zig-native/src/core.zig)
and [core_eval.zig](../zig-native/src/core_eval.zig) are the sole source
pipeline. Task 066 defines typed staging forms; external asset parsing remains
an existing host boundary.

## Implementation checklist

- [ ] Implement the specified typed code/descriptor nodes, constructors and
      stage checking.
- [ ] Preserve type/effect/identity evidence and reject incompatible code shapes
      or unavailable cross-stage values.
- [ ] Integrate evaluation and portable ownership without reparsing generated
      strings as a second frontend.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Check typed code composition, descriptor inspection and permitted staged
  values through imports.
- Reject mismatched code types, forbidden stage crossings, leaked local
  identities and effectful operations at pure stages.
- Test bounded evaluation, OOM, dependency transport and failed-build
  publication.

## Acceptance criteria

- [ ] Typed code and descriptors pass the specified introduction/use laws in the
      ordinary pipeline.
- [ ] Invalid stage boundaries and shapes have precise diagnostics and never
      publish partial generated artifacts.
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
