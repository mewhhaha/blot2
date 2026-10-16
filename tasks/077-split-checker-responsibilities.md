# 077 — Split checker responsibilities

## Status, dependencies, and originating requirements

- **Status:** In progress — owned scheme import and checker rule separation are
  implemented; focused and final common qualification remain required.
- **Dependencies:** [076](076-split-core-module-and-builder.md)
- **Originating requirements:** PLAN: Hill 14 / checker structure and function
  size. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Separate scheme handling, expression/statement checking, rows/fields and
validation, reducing large handwritten functions.

## Starting point

[check.zig](../zig-native/src/check/check.zig) combines these roles;
`checkInternalExecution` and related large routines own order-sensitive checking
and diagnostics.

## Implementation checklist

- [x] Extract cohesive checker responsibilities with explicit shared context and
      ownership.
- [x] Split large functions toward approximately 120 lines while keeping
      diagnostic order, scope and chronological substitution visible.
- [x] Avoid duplicate validation and forwarding-only modules; update all callers
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
- Validation: Zig 0.17.0 Safe/noLLVM; eight focused checker laws including
  complete allocation-failure sweeps, two retained body laws, the extended
  prepared-prefix snapshot law, ten executed guest groups, all native test
  interfaces compiled, and 425 affected Zig files with zero findings. Logs and
  exact source/executable pins:
  `build/bench/finish-rest-20261015/checker-owners/`.
- Comparison: fresh/edit/revert/failed-edit repair/restart output, diagnostics,
  native work and portable owner payload agree. Ordinary Cost Wasm and requested
  allocations/count/peak/live bytes are exact. Engine fields fall 210 to 192;
  expression/statement dispatch falls 476/200 to 46/18 lines.
- Remaining limitations: the lifecycle coordinator remains 407 lines; final
  common performance/compiler qualification and prerequisite closure are open.
  No completion, commit or push is claimed.
- Durable record: [Checker ownership](../zig-native/CHECKER_OWNERSHIP.md).
