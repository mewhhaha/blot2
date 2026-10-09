# 036 — Summarize demand control flow

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [007](007-infer-recursive-components-jointly.md),
  [014](014-specify-unified-query-table.md)
- **Originating requirements:** DEMANDS: Compiler plan and retained
  dependencies. Sources: [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Publish versioned demand-use summaries covering dynamic counts, aliases, escape,
loops and control/provider boundaries.

## Starting point

[demand_inline.zig](../zig-native/src/demand_inline.zig) uses a bounded 96-node
`Plan` for known acyclic expression forwarding.
[core.zig](../zig-native/src/core.zig) retains `suspend_`/`force`; broader
retained-body analysis is not implemented.

## Implementation checklist

- [ ] Classify never/once/repeated/unknown/escaping demand uses by dynamic
      control flow rather than textual occurrence count.
- [ ] Track aliases, creation scopes, loops, captures and request/provider
      boundaries; use bounded recursive-component fixed points.
- [ ] Record checked-body identity, summary version, captures, latent effects
      and every consumed dependency in the query model. Keep Core immutable and
      principal facts distinct.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Analyze demands read in branches/loops, forwarded through aliases, stored in
  closures and recursive callbacks.
- Test bounded exhaustion and unknown control flow, imported bodies, changed
  callee bodies with stable types and failed revisions.
- Check summary ownership, OOM publication and work proportional to analyzed
  retained bodies.

## Acceptance criteria

- [ ] Each summary conservatively represents dynamic use and scope with exact
      versioned dependencies.
- [ ] No unknown use is misclassified as local/once, and repeated lookup can
      reuse summaries safely.
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
