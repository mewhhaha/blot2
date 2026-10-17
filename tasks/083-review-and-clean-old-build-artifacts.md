# 083 — Review and clean old build artifacts

## Status, dependencies, and originating requirements

- **Status:** Complete — owner decisions and the approved deletion are recorded
  below (15 October 2026).
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

- [x] Inventory paths, sizes, reproducibility and task/evidence dependencies;
      distinguish active sources, binaries, samples and disposable outputs.
- [x] Retain required boxed/packed baselines, final measurement evidence,
      private workload handling and any still-needed experiments.
- [x] Present a concrete deletion list for the required owner decision. Reuse an
      explicit existing decision only when it covers those exact artifacts.
- [x] Delete only the agreed set and record the decision, removed paths,
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

- [x] An owner-reviewed inventory and exact deletion decision are recorded.
- [x] Only agreed artifacts are removed; necessary baselines, uncommitted
      sources and evidence remain available.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Owner decisions, 15 October 2026:
  - The owner removed the repository's ignored `build/` directory, including all
    of `build/bench/`. Every `build/bench/...` path cited in task files,
    CONTINUE.md and durable records is now historical and unavailable; the
    committed durable documents under `zig-native/` (including
    `zig-native/qualification/`) are the remaining evidence of record. Any
    boxed/packed baseline binaries or measurement evidence that lived only in
    `build/` left with it.
  - Delete every `.zig-cache` directory under `/var/tmp/blot2-*`, and nothing
    else. The `/var/tmp/blot2` symlink to this repository and the active
    `zig-native/.zig-cache` were excluded.
- Inventory before deletion: `/var/tmp` held 566 `blot2-*` freeze directories
  (about 1.3 TB apparent size) with 659 `.zig-cache` directories; no process had
  a working directory in them; the disk was 97% full.
- Result: all 659 cache directories were removed; used space on `/home` fell
  from 957,115,154,432 to 518,810,796,032 bytes (438 GB reclaimed; 53% used).
  Frozen sources, patches, manifests and logs in `/var/tmp` remain; the freeze
  directories themselves were not part of the decision. Nothing else required by
  open tasks was deleted.
- Superseded proposal: the 14 October inventory (71 benchmark directories; 46
  inactive Zig caches, 14,582 files, 4,946,001,920 bytes, revalidated on 15
  October) went with `build/` and was replaced by the decision above.
- Incident, 15 October 2026: before any owner decision, a delegated task removed
  exactly
  `/var/tmp/blot2-structured-tasks-20261015/source/zig-native/.zig-cache` (about
  15 GiB reported; exact bytes not captured). This violated the approval
  requirement and is not an approved cleanup. Further deletion stopped; the
  three semantic slice source manifests and the Task-v1 failure binaries were
  verified or reproduced outside the removed cache.
- Comparison: not applicable; this is an inventory and deletion task.
- Remaining: task 081 must carry the `build/` removal and cache decision into
  durable documentation before 999.
- Durable record: pending through task 081; [CONTINUE.md](../CONTINUE.md)
  currently summarizes the decision.
