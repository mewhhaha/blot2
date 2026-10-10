# 012 — Schedule independent semantic jobs

## Status, dependencies, and originating requirements

- **Status:** Complete — private ready components, deterministic atomic
  publication and failure ownership are qualified; the default stays serial.
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

- [x] Schedule only independent components with immutable inputs and private
      solver, scratch, importer maps and diagnostics.
- [x] Join every worker before source/allocator teardown and publish results in
      deterministic source order under complete canonical keys.
- [x] Handle worker failure, cancellation and allocation failure without partial
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

- [x] Independent jobs own all mutable solver state and publish
      deterministically after successful validation.
- [x] Single-worker equivalence, cancellation and failure ownership are
      demonstrated; default parallel policy is reserved for task 013.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `eb66151` (`eb6615122912bafb2150dd049f8fdcc644e3ea5e`).
- Validation: Zig `0.17.0`; `deno task test:compiler` passes the full LLVM
  native suite and 620 guest/client tests; `deno task lint:zig` checks 297 files
  with zero findings; `deno task package:check` and affected formatting checks
  pass. Native allocation-failure, joined cancellation, mixed outcomes, lexical
  capture and component-atomic recursive laws are included.
- Comparison: the immutable task 011 compiler and candidate default/worker
  counts 1, 2, 4 and 8 match all 626 public source/prelude cases (3,756
  invocations), ordered diagnostics and Wasm, with zero live tracked bytes.
  Corpus expectations execute in 192 guests / 10,362 calls. Repeated retained
  population/edit/revert/no-op, failed-source correction and checkpoint restart
  match on 27 workloads, with 2,106 successful revision samples and 648 guests /
  41,208 calls, including edited outputs. Exact pins and allocation observations
  are in the durable record. CPU/wall distributions and default policy are task
  013; this task makes no timing claim.
- Remaining limitations: currently running jobs poll cancellation at their next
  dispatch boundary; unsupported new lexical origins, ambiguous same-owner SCCs,
  active parent dependencies and non-positional artifact source units decline
  safely to ordinary inference. Private gdev and the original boxed compiler are
  still absent and remain external qualification gates. No push occurred.
- Durable record: [SEMANTIC_JOBS.md](../zig-native/SEMANTIC_JOBS.md),
  [ownership contract](../zig-native/CONTRACT.md) and
  [public client options](../zig-native/PROJECT_CLIENT.md).
