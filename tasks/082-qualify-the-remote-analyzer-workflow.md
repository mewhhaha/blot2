# 082 — Qualify the remote analyzer workflow

## Status, dependencies, and originating requirements

- **Status:** Pending — re-scoped by owner decision on 15 October 2026 to a
  local run of the analyzer built from `../zig-analyzer`; no completion is
  claimed.
- **Dependencies:** [081](081-finalize-durable-documentation.md)
- **Originating requirements:** PLAN: Hill 17 follow-up / first remote analyzer
  run. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Verify that the analyzer, built locally from the owner's `../zig-analyzer`
clone, reports zero findings over the final production tree.

**Owner decision, 15 October 2026:** a local analyzer build replaces the remote
GitHub Actions run as the gate. No push is needed or authorized for this task.
The remote workflow stays as CI; its pinned analyzer (`756bfd5`, release
0.17.0-1) is older than the local clone (`13b7e03`), so record both revisions
and note any finding that only one of them reports.

## Starting point

[.github/workflows/compiler.yml](../.github/workflows/compiler.yml) builds the
pinned analyzer; the known successful run 37381022849 at `86a527b` predates the
local workflow change. No qualifying remote run is established by the starting
baseline.

## Implementation checklist

- [ ] Build the analyzer and its compiler backend in `../zig-analyzer`
      (`zig build`, `zig build backend`) and confirm `zig-analyzer doctor`
      passes with Zig 0.17.0.
- [ ] Run `deno task lint:zig` over the final committed tree with that analyzer
      and confirm zero findings and full source coverage.
- [ ] Record the analyzer commit, doctor output, file count and result durably.

## Validation

Apply the relevant [shared validation](README.md#shared-validation) rules. Use
formatting, link, consistency and evidence checks for documentation-only
changes; run code gates only when code or build inputs change.

- Confirm the lint run covers every `zig-native/src` file plus the fixture
  module, against the exact tree that task 084 qualifies.
- A run over an older tree or with a missing backend does not qualify.

## Acceptance criteria

- [ ] A local analyzer run over the final committed tree reports zero findings
      and is recorded with the analyzer and tree revisions.
- [ ] Final cleanup remains blocked on this evidence.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: read-only Actions inspection on15October2026 found latest
  successful
  run[37935729382](https://github.com/mewhhaha/blot2/actions/runs/37935729382)
  at65dccda29d56d4eaf6d23ff81ca05f1720824d23. Its workflow SHA-256 is
  1e53d90913450bbb9b4bd46a502fcb8ecc972172cac10555588138b806b1803b; the current
  local workflow
  isdb109741eb6cd29e7505e8ee30c461c237d8fbaf0177d71cc06907f20f9d287c. The
  workflow differs and the run does not contain the current uncommitted
  compiler. It does not qualify this gate. Raw observation, jobs and workflow
  response are in `build/bench/complete-program-20261015/remote-analyzer-*`.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.

### Local analyzer runs — 15 October 2026 (current uncommitted tree)

- `../zig-analyzer` at `13b7e03` (0.17.0-2): `zig build backend` succeeded and
  `zig-analyzer doctor` reports a compatible backend. `deno task lint:zig`
  checks 486 files and reports 10 findings: eight `double-release` on guarded
  `defer if (flag) x.deinit()` sites whose flag is cleared after an explicit
  deinit, and two `invalidated-container-view` on by-value copies broken out of
  a `for` loop in `reuse/dependency_interface_tests.zig`. All ten appear to be
  false positives introduced by newer analyzer rules.
- The CI-pinned analyzer `756bfd5` (0.17.0-1), built in an isolated clone,
  reports zero findings across all 486 source files and the fixture module.
- Remaining: rerun over the final committed tree, and decide whether the gate
  uses the CI pin or the newer analyzer (which would need either analyzer fixes
  or source changes for those ten sites).

### Local analyzer run — 16 October 2026 (committed tree `2b2ffbb`)

- Owner decision, 16 October 2026: the local `../zig-analyzer` build gates this
  task, and its known false positives are accepted for now.
- `../zig-analyzer` at `13b7e03`, Zig 0.17.0: `zig build backend` succeeded
  (8:02) and `zig-analyzer doctor` reports Zig 0.17.0 and a compatible backend.
  `deno task lint:zig` checks 486 files and reports the same 10 findings as on
  15 October, in `eval/region_arena.zig` (2), `reuse/artifact_import_tests.zig`,
  `reuse/code_artifacts_tests.zig`, `reuse/source_value_template_tests.zig` (4)
  and `reuse/dependency_interface_tests.zig` (2).
- Cause of the eight `double-release` findings: the rule's deferred-release
  check (`src/rules/lifecycle/container_release.zig`, `deferredReleaseAfter`)
  treats `defer if (flag) x.deinit()` as unconditional, although its explicit-
  release check already skips conditional defers. The two
  `invalidated-container-view` findings flag a by-value node copy and a `usize`
  index broken out of a `for` loop, neither of which views the reallocated
  slice.
- No source suppressions or restructuring were applied. No upstream issue has
  been filed; that needs owner approval.
- The CI-pinned analyzer `756bfd5` reported zero findings over `23a934f`; the
  only source change since then is the `2b2ffbb` contract fix.
