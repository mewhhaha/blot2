# 026 — Resolve structured control flow

## Status, dependencies, and originating requirements

- **Status:** Complete at `ae908fa`.
- **Dependencies:** [025](025-resolve-calls-before-emission.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / resolved
  control flow. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Extend the resolved representation to branches, joins, loops, returns, breaks
and request control.

## Starting point

[core_backend.zig](../zig-native/src/backend/core_backend.zig) emits structured
flow; [wasm_control_flow.zig](../zig-native/src/backend/wasm_control_flow.zig),
[loop_targets.zig](../zig-native/src/backend/loop_targets.zig) and
[runtime_cleanup.zig](../zig-native/src/runtime/runtime_cleanup.zig) track edges
and exits. Task 025 supplies resolved calls.

## Implementation checklist

- [x] Represent branch values, local versions, loop carries and exit targets
      before emission, with source spans and evaluation order.
- [x] Make request yield/completion/cancellation edges explicit and record
      cleanup obligations on the actual exiting scopes.
- [x] Preserve nested inlining, pattern failure paths and dominance without
      changing return/break meaning.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Run nested branch/loop, early return, break, pattern guard and monadic-loop
  tests.
- Exercise request yield, handler return/break, nested providers, zero
  iterations and suspended resumption in sync/JSPI modes.
- Compare diagnostics and fresh/retained output; fail allocations during
  preparation without mutating Core.

## Acceptance criteria

- [x] Every supported structured edge and cleanup target is represented before
      instruction emission.
- [x] Control-flow execution, dominance and cancellation behavior match the
      current language contract.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `ae908fa` ("Prepare structured flow before emission").
- Change: [resolved_flow.zig](../zig-native/src/backend/resolved_flow.zig) plans
  exits (`return`, `break`, a request handler's return and break) with their
  target construct and label, the target scope's cleanup mark, values in source
  order and the carries they replace; joins with their result type and per-arm
  local versions; matches with inputs, arms and row/guard fallthrough; loops
  with carries, refutable patterns and divergence; and request loops with their
  yield arms and exited, broken and completion edges. Each is prepared before
  its construct's first instruction, and `takeExit` discharges exactly the
  cleanup above the target scope's mark.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 646 guest/client tests; `deno task lint:zig` reports zero findings across
  314 files. A process law executes joins with rebinding merges, a guarded
  `case`, nested loops with two carries, zero iterations, `break`, `return` from
  a loop and request loops whose handlers yield, return and break, with retained
  builds equal to fresh ones and every plan shape counted; a mutant that assigns
  `break` carries in source order fails it. The existing request, JSPI and
  allocation-failure suites run unchanged.
- Comparison: every public example, the synthetic corpus in every phase and gdev
  emit byte-identical Wasm (gdev SHA-256 `3158216b…def0`, 840,534 bytes); no
  performance change was intended or measured.
- Remaining limitations: plans are transient per construct (task 028 stores
  resolved bodies); exact builders and internal traversal blocks have no plans;
  the cleanup actions an exit discharges are created during emission, so an exit
  fixes its target scope before its value and discharges what is recorded when
  it branches.
- Durable record: [resolved structured flow](../zig-native/RESOLVED_FLOW.md).
