# 999 — Remove tasks and plan

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [001](001-qualify-list-span-prototype.md),
  [002](002-close-packed-list-traversal-regression.md),
  [003](003-specify-general-call-summaries.md),
  [004](004-summarize-predicate-bearing-callees.md),
  [005](005-summarize-higher-order-callees.md),
  [006](006-summarize-lexical-closures.md),
  [007](007-infer-recursive-components-jointly.md),
  [008](008-canonicalize-specialization-keys.md),
  [009](009-cache-composite-type-resolutions.md),
  [010](010-schedule-constraints-by-variable.md),
  [011](011-reduce-semantic-allocation-traffic.md),
  [012](012-schedule-independent-semantic-jobs.md),
  [013](013-qualify-parallel-inference.md),
  [014](014-specify-unified-query-table.md),
  [015](015-migrate-refinement-queries.md),
  [016](016-migrate-specialization-and-principal-queries.md),
  [017](017-unify-source-and-revision-validation.md),
  [018](018-migrate-executable-reuse-queries.md),
  [019](019-serialize-the-query-table.md),
  [020](020-persist-complete-semantic-artifacts.md),
  [021](021-publish-transactional-revision-deltas.md),
  [022](022-retain-constants-and-relocatable-data.md),
  [023](023-narrow-literal-edit-invalidation.md),
  [024](024-apply-general-body-interface-cutoff.md),
  [025](025-resolve-calls-before-emission.md),
  [026](026-resolve-structured-control-flow.md),
  [027](027-represent-ownership-in-resolved-ir.md),
  [028](028-make-emission-consume-resolved-bodies.md),
  [029](029-remove-function-indices-from-reuse-keys.md),
  [030](030-specify-shared-and-cyclic-ownership.md),
  [031](031-implement-shared-reference-counting.md),
  [032](032-own-escaping-values-and-persistent-roots.md),
  [033](033-own-suspended-effects-and-cancellation.md),
  [034](034-reclaim-cyclic-ownership.md),
  [035](035-remove-the-tracing-runtime.md),
  [036](036-summarize-demand-control-flow.md),
  [037](037-lower-loop-aware-local-memos.md),
  [038](038-eliminate-demands-through-known-callbacks.md),
  [039](039-guarantee-and-explain-demand-lowering.md),
  [040](040-fuse-packed-row-producers-and-consumers.md),
  [041](041-broaden-numeric-simd.md), [042](042-specify-ragged-builders.md),
  [043](043-implement-ragged-builders.md),
  [044](044-specify-rolling-and-summary-operations.md),
  [045](045-implement-rolling-reductions.md),
  [046](046-implement-composable-summary-trees.md),
  [047](047-eliminate-generic-iterator-state.md),
  [048](048-explain-dispatch-and-evidence.md),
  [049](049-specify-editor-completion.md),
  [050](050-implement-editor-completion.md),
  [051](051-specify-module-abstraction.md),
  [052](052-implement-opaque-types-and-privacy.md),
  [053](053-qualify-module-cutoffs-and-wrapper-erasure.md),
  [054](054-specify-associated-types-and-implementations.md),
  [055](055-implement-associated-type-members.md),
  [056](056-implement-declarations-and-evidence-diagnostics.md),
  [057](057-specify-scoped-effect-identities.md),
  [058](058-implement-effect-instances-and-subtraction.md),
  [059](059-reject-escaping-capabilities.md),
  [060](060-specify-usage-and-lifetime-contracts.md),
  [061](061-check-usage-and-call-multiplicity.md),
  [062](062-implement-resource-cleanup-contracts.md),
  [063](063-specify-polymorphic-packages.md),
  [064](064-check-higher-rank-types-and-skolems.md),
  [065](065-implement-existential-packages.md),
  [066](066-specify-typed-staging.md),
  [067](067-implement-typed-code-and-descriptors.md),
  [068](068-implement-hygienic-generation-and-reuse.md),
  [069](069-specify-bounded-erased-proofs.md),
  [070](070-implement-numeric-and-index-witnesses.md),
  [071](071-eliminate-checks-from-proved-branch-facts.md),
  [072](072-specify-structured-concurrency.md),
  [073](073-implement-scoped-tasks-and-cancellation.md),
  [074](074-implement-disjoint-access-and-host-execution.md),
  [075](075-split-evaluator-state-and-dispatch.md),
  [076](076-split-core-module-and-builder.md),
  [077](077-split-checker-responsibilities.md),
  [078](078-split-backend-state-and-emission.md),
  [079](079-relocate-fixtures-through-a-test-module.md),
  [080](080-organize-the-source-tree.md),
  [081](081-finalize-durable-documentation.md),
  [082](082-qualify-the-remote-analyzer-workflow.md),
  [083](083-review-and-clean-old-build-artifacts.md),
  [084](084-qualify-the-complete-program.md)
- **Originating requirements:** Approved task manifest / final conditional
  cleanup. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

After every required task and external gate is complete, remove the entire tasks
directory and PLAN.md and commit that cleanup locally.

## Starting point

[README.md](README.md) is the temporary execution index and
[PLAN.md](../PLAN.md) preserves the source scope. Task 081 migrates durable
knowledge; task 084 qualifies the entire program. This task is intentionally
last so additional work can be inserted before it.

## Implementation checklist

- [ ] Re-read every completion record, including newly inserted follow-ups, and
      verify all acceptance gates and external evidence are complete.
- [ ] Ensure durable specifications, decisions, measurements, run links and
      limitations live outside `tasks/` and `PLAN.md`, with stable references.
- [ ] Remove the whole `tasks/` directory, including this file, and `PLAN.md`;
      update all remaining references to valid durable destinations.
- [ ] Inspect the deletion diff and commit only the intended cleanup locally on
      main. Preserve unrelated work and do not push.

## Validation

Apply the relevant [shared validation](README.md#shared-validation) rules. Use
formatting, link, consistency and evidence checks for documentation-only
changes; run code gates only when code or build inputs change.

- Before deletion, validate statuses, dependencies, coverage and completion
  evidence for every required task; no ready/pending task may remain.
- After deletion, search tracked files for dangling task/PLAN references and
  verify documentation links and the exact deletion diff.
- Run formatting/consistency checks for changed documentation; compiler tests
  are unnecessary if code and build inputs did not change.

## Acceptance criteria

- [ ] All specifications and qualification evidence survive outside the deleted
      planning files.
- [ ] `tasks/` and `PLAN.md` are absent, remaining references work and the
      cleanup is committed locally on main without a push.
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
