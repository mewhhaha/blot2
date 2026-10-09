# 026 — Resolve structured control flow

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [025](025-resolve-calls-before-emission.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / resolved
  control flow. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Extend the resolved representation to branches, joins, loops, returns, breaks
and request control.

## Starting point

[core_backend.zig](../zig-native/src/core_backend.zig) emits structured flow;
[wasm_control_flow.zig](../zig-native/src/wasm_control_flow.zig),
[loop_targets.zig](../zig-native/src/loop_targets.zig) and
[runtime_cleanup.zig](../zig-native/src/runtime_cleanup.zig) track edges and
exits. Task 025 supplies resolved calls.

## Implementation checklist

- [ ] Represent branch values, local versions, loop carries and exit targets
      before emission, with source spans and evaluation order.
- [ ] Make request yield/completion/cancellation edges explicit and record
      cleanup obligations on the actual exiting scopes.
- [ ] Preserve nested inlining, pattern failure paths and dominance without
      changing return/break meaning.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run nested branch/loop, early return, break, pattern guard and monadic-loop
  tests.
- Exercise request yield, handler return/break, nested providers, zero
  iterations and suspended resumption in sync/JSPI modes.
- Compare diagnostics and fresh/retained output; fail allocations during
  preparation without mutating Core.

## Acceptance criteria

- [ ] Every supported structured edge and cleanup target is represented before
      instruction emission.
- [ ] Control-flow execution, dominance and cancellation behavior match the
      current language contract.
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
