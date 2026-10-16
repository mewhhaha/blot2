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
- Validation: 14 October inventory examined 71 top-level benchmark directories,
  46 inactive Zig cache directories, 10,353 retained metadata/source/log files,
  tracked documentation references and active process working directories. No
  proposed cache has a known external hardlink or active process dependency.
- Comparison: the proposal contains 14,582 regular files totaling 4,946,001,920
  bytes. This is estimated reclaimable space, not reclaimed space. Exact paths
  and checks are in
  `build/bench/continuation-20261014/cache-cleanup-proposal.json`.
- Remaining limitations: the explicit owner decision is pending; nothing has
  been deleted. Recheck active use and exact paths before any approved deletion.
  Broader artifact cleanup and task 081 remain open.
- Revalidation:15October2026 confirms the same46directories,14,582regular files
  and4,946,001,920disk bytes, with no observed process cwd/open-file users.
  `build/bench/complete-program-20261015/cache-proposal-revalidation.json` pins
  the unchanged proposal. An exact owner-decision request is pending; no files
  were deleted.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.

### Unapproved cleanup incident —15 October

A delegated task removed exactly
`/var/tmp/blot2-structured-tasks-20261015/source/zig-native/.zig-cache` before
receiving an owner decision. This violated the requirement above; it is not an
approved cleanup or task completion. Reported pre-deletion size was about15GiB,
rounded; an exact reclaimed-byte count was not captured. Further deletion
stopped. Root verified the three current semantic slice source manifests and
reproduced Task-v1 failure binaries plus their compiler outside the removed
cache. Sources, manifests and logs outside the cache remain. The two exact
owner-decision proposals remain pending and untouched. Incident evidence:
`build/bench/finish-rest-20261015/unapproved-cache-deletion.json`.

### Owner decisions and cleanup — 15 October 2026

- The owner removed the repository's ignored `build/` directory, including all
  of `build/bench/`. Every `build/bench/...` path cited in task files,
  CONTINUE.md and durable records is now historical and unavailable; the
  committed durable documents under `zig-native/` (including
  `zig-native/qualification/`) are the remaining evidence of record. The 14
  October 46-directory proposal file went with it and is superseded.
- Inventory: `/var/tmp` held 566 `blot2-*` freeze directories (about 1.3 TB
  apparent size) with 659 `.zig-cache` directories. No process had a working
  directory in them. The disk was 97% full.
- Decision: delete every `.zig-cache` directory under `/var/tmp/blot2-*`, and
  nothing else. The `/var/tmp/blot2` symlink to this repository and the active
  `zig-native/.zig-cache` were excluded.
- Result: all 659 cache directories were removed; used space on `/home` fell
  from 957,115,154,432 to 518,810,796,032 bytes (438 GB reclaimed; 53% used).
  Frozen sources, patches, manifests and logs in `/var/tmp` remain. The
  remaining freeze directories themselves were not part of the decision.
- Any boxed/packed baseline binaries or measurement evidence that lived only in
  `build/` left with the owner's removal; nothing else required by open tasks
  was deleted by this cleanup.
- Task 081 must carry this decision into durable documentation before 999.
