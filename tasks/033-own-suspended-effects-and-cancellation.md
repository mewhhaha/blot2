# 033 — Own suspended effects and cancellation

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

[request_runtime.zig](../zig-native/src/request_runtime.zig),
[runtime_cleanup.zig](../zig-native/src/runtime_cleanup.zig),
[compiler/guest.ts](../compiler/guest.ts) and
[tests/demand_completion_execution.test.ts](../zig-native/tests/demand_completion_execution.test.ts)
preserve request and demand completion behavior. Persistent payload ownership
remains part of the runtime program.

## Implementation checklist

- [ ] Own suspended arguments, captures, replies and continuations/frames
      through host suspension and resumption.
- [ ] Release each canceled scope once; handler return/break resets unfinished
      demands to pending, while yield resumes the same evaluation.
- [ ] Preserve terminal persistent demands after traps/host exceptions,
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

- [ ] Every suspended or canceled value has a valid owner and all applicable
      cleanup runs once.
- [ ] Demand completion semantics and sync/JSPI parity survive ownership
      transfer and exceptional exits.
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
