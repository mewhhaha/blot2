# 077 — Split checker responsibilities

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
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

- [x] Checker concerns have clear boundaries and materially smaller production
      functions.
- [x] Chronology, diagnostics, imports and ownership retain parity.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Current local milestone: `e29dd0d2c6faa2ad16a39e4a06ef254cede3ff2c`; compiler
  and exact source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: Checker responsibility owners pass current native/OOM, guest,
  import, diagnostic and retained/restart gates.
- Remaining limits: Expression/statement dispatches are 46/19 lines; the
  lifecycle coordinator is still 417 lines and is an explicit exception.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

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
