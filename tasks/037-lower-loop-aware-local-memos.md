# 037 — Lower loop aware local memos

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [036](036-summarize-demand-control-flow.md)
- **Originating requirements:** DEMANDS: Local memo scope, loops and acceptance
  checks. Sources: [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Place local demand memo state in its creation scope across branches and loops.

## Starting point

[demand_inline.zig](../zig-native/src/demand_inline.zig) and
[core_backend.zig](../zig-native/src/core_backend.zig) already lower repeated
admitted expression demands to invocation-local memo state; callee-loop cases
still use runtime cells.

## Implementation checklist

- [ ] Lower never/once/repeated local uses according to task 036 with explicit
      joins, initialization states and result slots.
- [ ] Create one memo outside a loop for an outside creation and reset for each
      inside creation; preserve alias sharing and first-demand scope.
- [ ] Handle zero iterations, early exits and cancellation without speculative
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

- [ ] Local memo lifetime matches dynamic creation in all branch/loop cases.
- [ ] Evaluation occurs only at the first executed demand and normal completion
      is the only shared-result publication.
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
