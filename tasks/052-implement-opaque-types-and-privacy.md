# 052 — Implement opaque types and privacy

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `f184dde`; qualified evidence
  below.
- **Dependencies:** [051](051-specify-module-abstraction.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 2 / opacity and
  privacy. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Enforce the specified opaque type and module privacy rules across source and
compiled imports.

## Starting point

[parser.zig](../zig-native/src/parse/parser.zig),
[check.zig](../zig-native/src/check/check.zig),
[project_check.zig](../zig-native/src/reuse/project_check.zig) and
[dependency_interface_validation.zig](../zig-native/src/reuse/dependency_interface_validation.zig)
implement current declarations/imports. Task 051 defines the new syntax and
visibility model.

## Implementation checklist

- [x] Parse/check opaque declarations and access controls using stable nominal
      identities and controlled representation access.
- [x] Enforce visibility through aliases, namespace imports and re-export
      chains; publish only permitted interface information.
- [x] Version artifact changes and keep existing public-by-default programs
      compatible as specified.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Test legal construction inside the defining module, permitted exports and
  abstract use by callers.
- Reject private constructor/field access, alias or re-export bypass, identity
  forgery and malformed dependency interfaces.
- Run dependency/checkpoint round trips, failed edits and allocation-failure
  publication.

## Acceptance criteria

- [x] Opaque representations remain private across every supported import path.
- [x] Positive/negative abstraction laws and separate-compilation compatibility
      pass.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: local implementation `f184dde`; the separate record commit contains
  this completion evidence. Nothing is pushed.
- Validation: Zig 0.17.0; `deno task test:compiler` passes all 1,400 native and
  871 guest/client laws; eight unchanged release allocation budgets pass.
  `deno task lint:zig` checks 343 files with zero findings.
  Opaque/public/private storage and executable boundaries pass source,
  compiled-import, checkpoint, forged-interface, failed-edit and OOM laws.
  Contextual host/editor syntax is regenerated and qualified.
- Comparison: Public CPU ratios 1.0042–1.0292; four synthetic graphs preserve
  all Wasm through fresh/retained/restart phases. Exact binary pins and all
  distributions are in the durable record.
- Remaining limitations: Tasks 024/053 own broader body cutoffs and
  operation-level wrapper qualification. Deep/unresolved storage recipes decline
  bounded proofs; namespace-wide exports remain outside the specified syntax.
- Durable record:
  [MODULE_ABSTRACTION_QUALIFICATION](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md);
  exact combined pins, commands, rejected attempts and raw evidence are in
  [integrated qualification](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#integrated-qualification--12-october-2026).
