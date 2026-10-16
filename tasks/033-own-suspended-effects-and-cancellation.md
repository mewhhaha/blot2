# 033 — Own suspended effects and cancellation

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `f184dde`; qualified evidence
  below.
- **Dependencies:** [032](032-own-escaping-values-and-persistent-roots.md)
- **Originating requirements:** PLAN: Earlier programs / suspended ownership;
  DEMANDS: Completion and cancellation. Sources: [PLAN.md](../PLAN.md),
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Transfer and release ownership correctly across requests, JSPI suspension,
resumption, cancellation, traps and host exceptions.

## Starting point

[request_runtime.zig](../zig-native/src/runtime/request_runtime.zig),
[runtime_cleanup.zig](../zig-native/src/runtime/runtime_cleanup.zig),
[compiler/guest.ts](../compiler/guest.ts) and
[tests/demand_completion_execution.test.ts](../zig-native/tests/demand_completion_execution.test.ts)
preserve request and demand completion behavior. Persistent payload ownership
remains part of the runtime program.

## Implementation checklist

- [x] Own suspended arguments, captures, replies and continuations/frames
      through host suspension and resumption.
- [x] Release each canceled scope once; handler return/break resets unfinished
      demands to pending, while yield resumes the same evaluation.
- [x] Preserve terminal persistent demands after traps/host exceptions,
      recursive-force rejection and the usability of unrelated entries.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run matching synchronous and JSPI traces for nested requests, resume, cancel,
  handler return/break and host rejection.
- Retry nested pending demands under a different provider; ensure effects can
  repeat only under the pinned cancellation contract.
- Stress repeated suspend/cancel cycles, discarded payloads and exceptions for
  leaks, double cleanup and dangling roots.

## Acceptance criteria

- [x] Every suspended or canceled value has a valid owner and all applicable
      cleanup runs once.
- [x] Demand completion semantics and sync/JSPI parity survive ownership
      transfer and exceptional exits.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: local implementation `f184dde`; the separate record commit contains
  this completion evidence. Nothing is pushed.
- Validation: Zig 0.17.0; `deno task test:compiler` passes all 1,400 native and
  871 guest/client laws; eight unchanged release allocation budgets pass.
  `deno task lint:zig` checks 343 files with zero findings. Sync/JSPI, nested
  requests, terminal failures, revoked capabilities, cancellation retry, pending
  roots, exceptional cleanup and repeated-allocation pressure pass alongside
  source/import/checkpoint/OOM laws.
- Comparison: Focused scalar sync overhead remains +89.4% (about 262 ns/call);
  all focused and combined distributions are recorded. This ownership task makes
  no overall speedup claim.
- Remaining limitations: Task 034 owns complete cycle collection; task 035 owns
  tracing removal and final CPU/memory qualification. JSPI settlement/rejection
  is supported; the guest has no abort API.
- Durable record: [SUSPENDED_OWNERSHIP](../zig-native/SUSPENDED_OWNERSHIP.md);
  exact combined pins, commands, rejected attempts and raw evidence are in
  [integrated qualification](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#integrated-qualification--12-october-2026).
