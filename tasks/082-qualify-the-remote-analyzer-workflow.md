# 082 — Qualify the remote analyzer workflow

## Status, dependencies, and originating requirements

- **Status:** In progress — the published Codeberg configuration is now active
  in enforced revision 4, and Git access to the pinned Zig source succeeds. The
  local analyzer and its backend build at `9a78ce1` with the upstream-supported
  `-Duse-llvm=true` host compiler option. Doctor reports Zig 0.17.0 and a
  compatible backend. Final-source qualification retains its documented
  dependencies.
- **19 October 2026:** rerun the local analyzers after task 084. CI lint has
  reported 0 findings on every compile-time-hill merge through 19 October.
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

- [x] Build the analyzer and its compiler backend in `../zig-analyzer`
      (`zig build`, `zig build backend`) and confirm `zig-analyzer doctor`
      passes with Zig 0.17.0.
- [x] Run `deno task lint:zig` over the final committed tree with that analyzer
      and confirm zero findings and full source coverage.
- [x] Record the analyzer commit, doctor output, file count and result durably.

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

- Commit: pending; record the final committed tree and analyzer revisions.
- Owner decision, 16 October 2026: the local `../zig-analyzer` build gates this
  task, and its known false positives are accepted for now.
- Latest local run (17 October 2026, committed tree `4599957`, clean
  `zig-native/`): `../zig-analyzer` at `9a78ce1` (0.17.0-2, pushed), which
  merges the upstream fixes for the false positives below.
  `zig-analyzer
  doctor` reports Zig 0.17.0 and a compatible compiler backend.
  `deno task
  lint:zig` and an uncached `zig-analyzer check --no-cache` each
  report 0 findings over all 487 `zig-native/src` files and the fixture module.
  The CI-pinned `756bfd5` (0.17.0-1) also reports 0 findings over the same tree,
  so no finding is reported by only one revision. Outside the gated directories,
  `check .` under the default profile warns about five deprecated `std.fs.path`
  uses (such as `zig-native/compiler_fingerprint.zig`); they are not part of
  this gate.
- Earlier local run (16 October 2026, committed tree `2b2ffbb`):
  `../zig-analyzer` at `13b7e03` (0.17.0-2), Zig 0.17.0. `zig build backend`
  succeeded (8:02) and `zig-analyzer doctor` reports Zig 0.17.0 and a compatible
  backend. `deno task lint:zig` checks 486 files and reports 10 findings, the
  same as on the 15 October uncommitted tree: `eval/region_arena.zig` (2),
  `reuse/artifact_import_tests.zig`, `reuse/code_artifacts_tests.zig`,
  `reuse/source_value_template_tests.zig` (4) and
  `reuse/dependency_interface_tests.zig` (2).
- Cause: the eight `double-release` findings come from the rule's
  deferred-release check (`src/rules/lifecycle/container_release.zig`,
  `deferredReleaseAfter`), which treats `defer if (flag) x.deinit()` as
  unconditional although its explicit-release check already skips conditional
  defers. The two `invalidated-container-view` findings flag a by-value node
  copy and a `usize` index broken out of a `for` loop, neither of which views
  the reallocated slice. No source suppressions or restructuring were applied;
  no upstream issue has been filed (that needs owner approval).
- CI-pinned analyzer `756bfd5` (0.17.0-1), built in an isolated clone, reports
  zero findings across all 486 source files and the fixture module over
  `23a934f`; the only source change since then is the `2b2ffbb` contract fix.
- Remote observation (read-only, 15 October 2026): the latest successful
  [run 37935729382](https://github.com/mewhhaha/blot2/actions/runs/37935729382)
  at `65dccda29d56d4eaf6d23ff81ca05f1720824d23` used workflow SHA-256
  `1e53d90913450bbb9b4bd46a502fcb8ecc972172cac10555588138b806b1803b`, which
  differs from the local
  `db109741eb6cd29e7505e8ee30c461c237d8fbaf0177d71cc06907f20f9d287c`, and
  predates the current compiler. It does not qualify this gate.
- Comparison: not applicable; this is a static-analysis gate.
- Remaining work: rerun both analyzers over the final committed tree that task
  084 qualifies (under a second each) and record the result.
- Durable record: pending; record the final analyzer result outside `tasks/`
  before cleanup.
