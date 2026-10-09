# 077 — Split checker responsibilities

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [076](076-split-core-module-and-builder.md)
- **Originating requirements:** PLAN: Hill 14 / checker structure and function
  size. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Separate scheme handling, expression/statement checking, rows/fields and
validation, reducing large handwritten functions.

## Starting point

[check.zig](../zig-native/src/check.zig) combines these roles;
`checkInternalExecution` and related large routines own order-sensitive checking
and diagnostics.

## Implementation checklist

- [ ] Extract cohesive checker responsibilities with explicit shared context and
      ownership.
- [ ] Split large functions toward approximately 120 lines while keeping
      diagnostic order, scope and chronological substitution visible.
- [ ] Avoid duplicate validation and forwarding-only modules; update all callers
      and adjacent tests.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run scheme, row, effect, pattern, module, negative-diagnostic and
  allocation-failure laws.
- Compare complete ordered diagnostics and fresh/retained output across the full
  compiler gate.
- Record before/after handwritten function sizes and check hot-path
  CPU/allocation.

## Acceptance criteria

- [ ] Checker concerns have clear boundaries and materially smaller production
      functions.
- [ ] Chronology, diagnostics, imports and ownership retain parity.
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
