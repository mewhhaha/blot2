# 061 — Check usage and call multiplicity

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [060](060-specify-usage-and-lifetime-contracts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 5 / checked usage
  and invocation. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Enforce the specified usage and invocation rules across branches, loops,
aliases, captures and higher-order calls.

## Starting point

Task 060 defines source contracts; [check.zig](../zig-native/src/check.zig),
resolved ownership and summary evidence provide implementation boundaries.
Existing uniqueness optimizations remain insufficient as source-level proofs.

## Implementation checklist

- [ ] Track uses and ownership flow by binding identity, joining branches and
      iterating loop facts conservatively.
- [ ] Check unique/shared and borrowed uses plus once/many function invocation
      and capture contracts.
- [ ] Import/export complete usage evidence and reject hidden duplication or
      borrow escape through generic/higher-order calls.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test valid exclusive transfer, sharing, scoped borrowing and specified
  once/many callbacks.
- Reject double use, duplicate aliases, illegal loop invocation, incompatible
  branches and captured borrowed escapes.
- Exercise imported contracts, polymorphic calls, failed edits, OOM and bounded
  recursive analysis.

## Acceptance criteria

- [ ] Every specified usage and multiplicity law is enforced at source and
      dependency boundaries.
- [ ] Valid programs remain accepted and diagnostics identify the conflicting
      use or lifetime.
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
