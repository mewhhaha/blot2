# 082 — Qualify the remote analyzer workflow

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [081](081-finalize-durable-documentation.md)
- **Originating requirements:** PLAN: Hill 17 follow-up / first remote analyzer
  run. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Verify a successful authorized remote run containing the final analyzer workflow
and relevant code.

## Starting point

[.github/workflows/compiler.yml](../.github/workflows/compiler.yml) builds the
pinned analyzer; the known successful run 37381022849 at `86a527b` predates the
local workflow change. No qualifying remote run is established by the starting
baseline.

## Implementation checklist

- [ ] Identify an already authorized remote revision/run containing the final
      workflow and code, or leave this external gate explicitly pending.
- [ ] Inspect the revision, workflow contents, analyzer execution, coverage,
      cache behavior and successful job conclusion.
- [ ] Record run URL, revision and substantive analyzer evidence durably. Do not
      push merely to satisfy this task and do not infer publication
      authorization from this plan.

## Validation

Apply the relevant [shared validation](README.md#shared-validation) rules. Use
formatting, link, consistency and evidence checks for documentation-only
changes; run code gates only when code or build inputs change.

- Use read-only GitHub Actions/API inspection to verify the exact run and commit
  instead of relying on a green unrelated run.
- Confirm zero analyzer findings over the final production tree and successful
  required compiler jobs.
- If no qualifying authorized run exists, record the missing external evidence
  and keep this task incomplete.

## Acceptance criteria

- [ ] A successful authorized remote run contains the final workflow/relevant
      code and is linked with its exact revision.
- [ ] Final cleanup remains blocked on this evidence; an old run or local-only
      pass is insufficient.
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
