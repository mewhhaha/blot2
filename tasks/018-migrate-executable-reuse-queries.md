# 018 — Migrate executable reuse queries

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [017](017-unify-source-and-revision-validation.md)
- **Originating requirements:** PLAN: Hill 12 / executable queries. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Integrate code fragments and optimizer dependencies into the query table without
confusing interface stability with executable stability.

## Starting point

[artifact_capture.zig](../zig-native/src/artifact_capture.zig),
[optimized_bodies.zig](../zig-native/src/optimized_bodies.zig),
[runtime_pipeline.zig](../zig-native/src/runtime_pipeline.zig) and
[runtime_body_relocation.zig](../zig-native/src/runtime_body_relocation.zig)
capture instructions, called bodies, signatures and lifetime facts. Demand
inlining also consumes body dependencies.

## Implementation checklist

- [ ] Represent body, selected evidence, capture, staging, policy and optimizer
      dependencies as executable query inputs.
- [ ] Preserve exact instruction/signature comparisons and deterministic
      preparation of callee lifetime summaries, including recursive call graphs.
- [ ] Keep semantic early cutoff separate: a body edit with an unchanged type
      must still invalidate affected executable consumers.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run optimized-body, general-cache, compilation-tier, static-capture and
  demand-forwarding reuse tests.
- Change an inlined callee or its escape behavior without changing its
  signature; compare fresh and retained code and execution.
- Cover recursive relocation, policy changes, OOM, failed assembly and recovery.

## Acceptance criteria

- [ ] Executable queries share storage and dependency machinery while preserving
      every code/lifetime validity check.
- [ ] Unchanged interfaces never suppress required body or optimizer rebuilds.
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
