# 012 — Schedule independent semantic jobs

## Status, dependencies, and originating requirements

- **Status:** In progress — general private component jobs and failure ownership
  are being implemented; no completion is claimed.
- **Dependencies:** [007](007-infer-recursive-components-jointly.md),
  [008](008-canonicalize-specialization-keys.md),
  [010](010-schedule-constraints-by-variable.md)
- **Originating requirements:** PLAN: Hill 9 / parallel region inference.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Run independent semantic jobs with private solver state and deterministic result
publication.

## Starting point

[semantic_parallel.zig](../zig-native/src/semantic_parallel.zig) has an opt-in
independent-proof batch;
[independent_call_proof.zig](../zig-native/src/independent_call_proof.zig)
records owned judgments and
[execution_policy.zig](../zig-native/src/execution_policy.zig) selects worker
counts. General component jobs still need task-level isolation.

## Implementation checklist

- [ ] Schedule only independent components with immutable inputs and private
      solver, scratch, importer maps and diagnostics.
- [ ] Join every worker before source/allocator teardown and publish results in
      deterministic source order under complete canonical keys.
- [ ] Handle worker failure, cancellation and allocation failure without partial
      publication, races in reference counts or loss of independent successful
      proofs.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare one worker with multiple workers on chains, wide independent graphs
  and mixed successful/failing jobs; require identical diagnostics and Wasm.
- Inject failure before dispatch, during allocation and after completion; cancel
  a batch and verify all jobs join and owners are released.
- Exercise repeated retained revisions and OOM recovery using independent-proof
  tests and the full compiler gate.

## Acceptance criteria

- [ ] Independent jobs own all mutable solver state and publish
      deterministically after successful validation.
- [ ] Single-worker equivalence, cancellation and failure ownership are
      demonstrated; default parallel policy is reserved for task 013.
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
