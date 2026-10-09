# 084 — Qualify the complete program

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [082](082-qualify-the-remote-analyzer-workflow.md),
  [083](083-review-and-clean-old-build-artifacts.md)
- **Originating requirements:** PLAN: All open programs and final performance
  gates. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Audit full scope coverage and qualify the completed semantic, runtime, language,
tooling and performance program.

## Starting point

The task index and coverage matrix track implementation and external gates.
[zig-native/STATUS.md](../zig-native/STATUS.md) must hold current qualified
results rather than the starting baseline.

## Implementation checklist

- [ ] Audit every mapped requirement and predecessor evidence; verify that
      design/prototype completion has not been substituted for feature
      completion.
- [ ] Run final semantic/ownership, sync/JSPI, editor, packaging, analyzer,
      source-layout, dependency/checkpoint, retained/restart and failed-edit
      recovery gates.
- [ ] Measure the final workload against pinned baselines in paired runs,
      including cold/population/first-edit/later-edit/no-op/restart/recovery and
      guest runtime/memory.
- [ ] Keep every missed requirement open. Add bounded numbered follow-up tasks
      before 999, update coverage/dependencies and finish them before cleanup.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run the final qualification command set in README with exact revisions, binary
  hashes and workload manifests.
- Establish approximately 500 ms cold gdev CPU, literal edits under 30 ms,
  general body edits under 100 ms, largest inference region under 50 ms and
  cumulative requested allocation under 100 MB.
- Verify no duplicate regions for a complete canonical key, qualified tracing
  replacement, closed traversal regression, full new language/demand gates and
  complete remote/tooling evidence.

## Acceptance criteria

- [ ] Every row of the README final-gate table passes with durable evidence; a
      missed target keeps the task incomplete.
- [ ] All discovered follow-ups and external gates are complete and the
      directory is ready for the conditional cleanup audit.
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
