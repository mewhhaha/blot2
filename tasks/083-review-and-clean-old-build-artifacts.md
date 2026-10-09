# 083 — Review and clean old build artifacts

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [081](081-finalize-durable-documentation.md)
- **Originating requirements:** PLAN: Hill 20 remainder / owner-reviewed
  artifacts. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Inventory old build artifacts, preserve required baselines/evidence and remove
only the owner-agreed set.

## Starting point

[PLAN.md](../PLAN.md) reports about 4 GB of older qualification/profile/audit
directories outside the previously approved deletion list. `build/bench/` and
`build/experiments/` include active baselines and uncommitted work.

## Implementation checklist

- [ ] Inventory paths, sizes, reproducibility and task/evidence dependencies;
      distinguish active sources, binaries, samples and disposable outputs.
- [ ] Retain required boxed/packed baselines, final measurement evidence,
      private workload handling and any still-needed experiments.
- [ ] Present a concrete deletion list for the required owner decision. Reuse an
      explicit existing decision only when it covers those exact artifacts.
- [ ] Delete only the agreed set and record the decision, removed paths,
      preserved evidence and reclaimed space durably.

## Validation

Apply the relevant [shared validation](README.md#shared-validation) rules. Use
formatting, link, consistency and evidence checks for documentation-only
changes; run code gates only when code or build inputs change.

- Check every proposed deletion against task and durable-document references
  before removal.
- Verify required binaries/manifests and evidence remain readable, then compare
  disk use and the tracked diff.
- If no owner decision covers a path, leave it in place and the relevant cleanup
  work open.

## Acceptance criteria

- [ ] An owner-reviewed inventory and exact deletion decision are recorded.
- [ ] Only agreed artifacts are removed; necessary baselines, uncommitted
      sources and evidence remain available.
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
