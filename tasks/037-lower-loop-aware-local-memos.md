# 037 — Lower loop aware local memos

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `2798ff9`.
- **Dependencies:** [036](036-summarize-demand-control-flow.md)
- **Originating requirements:** DEMANDS: Local memo scope, loops and acceptance
  checks. Sources: [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Place local demand memo state in its creation scope across branches and loops.

## Starting point

[demand_inline.zig](../zig-native/src/backend/demand_inline.zig) and
[core_backend.zig](../zig-native/src/backend/core_backend.zig) already lower
repeated admitted expression demands to invocation-local memo state; callee-loop
cases still use runtime cells.

## Implementation checklist

- [x] Lower never/once/repeated local uses according to task 036 with explicit
      joins, initialization states and result slots.
- [x] Create one memo outside a loop for an outside creation and reset for each
      inside creation; preserve alias sharing and first-demand scope.
- [x] Handle zero iterations, early exits and cancellation without speculative
      evaluation or partial result publication.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test inside/outside nested loops, conditional first reads, zero iterations and
  multiple aliases.
- Compare effects/traps and results with stored-cell fallback; exercise provider
  changes, handler return/break and JSPI suspension.
- Verify no slot/allocation per iteration for an outside creation and preserve
  captured binding snapshots.

## Acceptance criteria

- [x] Local memo lifetime matches dynamic creation in all branch/loop cases.
- [x] Evaluation occurs only at the first executed demand and normal completion
      is the only shared-result publication.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `2798ff9` (joint 029/032/037 compiler and bpm milestone).
- Implementation: Bounded structured local-demand proofs place ready/result
  state in dynamic creation scope, preserve alias sharing and force-site
  cleanup, and root managed cached results across loops.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native
  suite, 844 guest/client laws and all eight unchanged allocation budgets.
  `deno task lint:zig` checks 339 files with zero findings. Focused execution,
  OOM, archive/checkpoint, unchanged-Core and failed-edit recovery laws pass.
- Comparison: seven alternating release pairs over 13 public examples and four
  synthetic workloads. Old semantic counters match; each compiler's output is
  stable and fresh/retained/restart parity holds. Ownership helpers
  intentionally change public Wasm. Peak deltas and teardown live bytes are
  zero; CPU is mixed. Exact pins, distributions and isolated runtime costs are
  retained in the
  [shared qualification](../zig-native/PERSISTENT_ROOTS.md#integrated-qualification-12-october-2026).
- Remaining limitations: Captured/returned pending demands, unknown callbacks,
  providers inside the callee, demand-valued joins/carries and exhausted or
  recursive proofs retain ordinary cells. Known callback elimination belongs
  to 038.
- Durable record:
  [LOCAL_MEMOS_QUALIFICATION](../zig-native/LOCAL_MEMOS_QUALIFICATION.md).
