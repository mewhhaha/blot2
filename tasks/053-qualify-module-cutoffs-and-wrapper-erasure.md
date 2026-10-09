# 053 — Qualify module cutoffs and wrapper erasure

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [052](052-implement-opaque-types-and-privacy.md),
  [024](024-apply-general-body-interface-cutoff.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 2 / interface
  cutoff and zero-cost wrappers. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Prove that private implementation edits reuse callers and eligible abstraction
wrappers add no runtime representation cost.

## Starting point

Task 052 supplies opacity and task 024 general interface cutoff.
[module_frontend_cutoff.zig](../zig-native/src/module_frontend_cutoff.zig),
resolved layouts and optimizer captures provide the reuse/representation
boundaries.

## Implementation checklist

- [ ] Make private implementation dependencies distinct from public interface
      dependencies for semantic callers.
- [ ] Preserve executable invalidation where private code is inlined or staged,
      even when semantic callers reuse.
- [ ] Identify eligible wrapper erasure and compare layouts/operations without
      weakening nominal identity or privacy.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Edit a private body/representation with an unchanged public interface; compare
  caller query work and fresh/retained output.
- Change the public contract and prove invalidation resumes across source and
  compiled dependencies.
- Compare wrapped/unwrapped layout and generated operations for eligible cases;
  test escapes and non-eligible fallback.

## Acceptance criteria

- [ ] Private edits achieve the specified semantic cutoff while executable
      dependencies stay correct.
- [ ] Eligible wrappers add no representation allocation or indirection;
      retained nominal/privacy laws still pass.
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
