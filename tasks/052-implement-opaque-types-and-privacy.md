# 052 — Implement opaque types and privacy

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [051](051-specify-module-abstraction.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 2 / opacity and
  privacy. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Enforce the specified opaque type and module privacy rules across source and
compiled imports.

## Starting point

[parser.zig](../zig-native/src/parser.zig),
[check.zig](../zig-native/src/check.zig),
[project_check.zig](../zig-native/src/project_check.zig) and
[dependency_interface_validation.zig](../zig-native/src/dependency_interface_validation.zig)
implement current declarations/imports. Task 051 defines the new syntax and
visibility model.

## Implementation checklist

- [ ] Parse/check opaque declarations and access controls using stable nominal
      identities and controlled representation access.
- [ ] Enforce visibility through aliases, namespace imports and re-export
      chains; publish only permitted interface information.
- [ ] Version artifact changes and keep existing public-by-default programs
      compatible as specified.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test legal construction inside the defining module, permitted exports and
  abstract use by callers.
- Reject private constructor/field access, alias or re-export bypass, identity
  forgery and malformed dependency interfaces.
- Run dependency/checkpoint round trips, failed edits and allocation-failure
  publication.

## Acceptance criteria

- [ ] Opaque representations remain private across every supported import path.
- [ ] Positive/negative abstraction laws and separate-compilation compatibility
      pass.
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
