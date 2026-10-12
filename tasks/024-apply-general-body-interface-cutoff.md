# 024 — Apply general body interface cutoff

## Status, dependencies, and originating requirements

- **Status:** In progress — partial milestones through `2689ad5`; no completion
  is claimed.
- **Dependencies:** [023](023-narrow-literal-edit-invalidation.md)
- **Originating requirements:** PLAN: Hill 6 / general body edits under 100 ms.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Recheck changed bodies individually and stop semantic propagation when their
interfaces remain unchanged.

## Starting point

[module_frontend_cutoff.zig](../zig-native/src/module_frontend_cutoff.zig) and
refinement receipts provide limited cutoffs. The unified queries distinguish
semantic dependencies from executable and staging reads.

## Implementation checklist

- [ ] Compare complete public body interfaces after individual rechecking,
      including residual predicates, effects, captures and identities.
- [x] Stop semantic propagation only on exact interface equality; rebuild
      executable consumers of changed bodies, selected evidence, captures or
      staged inputs.
- [x] Preserve failed-revision rollback and dependencies across imports,
      namespaces and serialized artifacts.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Edit bodies with unchanged types but changed values, effect traces, demand
  control flow or lifetime summaries; executable callers must update.
- Change signatures, predicates and captures and verify semantic propagation
  resumes; test imports, dependencies, restart and correction.
- Measure first/later general body edit CPU, reused regions and metadata with
  fresh/retained equality.

## Acceptance criteria

- [ ] Unchanged interfaces stop semantic propagation without hiding executable
      or staged changes.
- [x] The under-100-ms body-edit target is measured or remains an explicit
      unfinished performance gate.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `a686304a31d49fe18f9f252e654995de7f10a951` (partial compiler
  milestone; the task stays open).
- Implementation: refinement receipts rooted in an edited module are admitted
  per declaration (body roots by exact projection and identity, closure roots by
  the exact projection of the declaration that reaches them), so unchanged
  declarations and consumers that read only an unchanged interface keep their
  semantic inference; executable fragments still rebuild every transitive
  caller. Hygienic loop names are numbered per top-level declaration, so
  size-changing edits no longer change the namespace.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 632 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 310 files. Native, gate
  and process-level laws cover replay, interface cutoff, revoked closures,
  demand and effect-trace changes with executed results, failed edits and
  recovery. `cli_profile.test.ts` no longer flakes on temporary path lengths.
- Comparison: 21 alternating repetitions over seventeen workloads at load 40–49:
  ecs edits 0.84–0.85 × CPU with refinement hits 10 → 58 of 82, monads 0.85 ×; a
  size-changing lists edit now keeps its gate but is 1.13 × slower;
  size-changing ecs and syntax edits are unchanged. Steady geomeans 0.972 (edit)
  and 0.969 (revert). Baseline `5bfae5b` (sources of `fbe28c8`).
- Remaining work (why the task is open): the frontend still rechecks every body
  of an edited module rather than the changed bodies individually; Core node and
  type IDs are module-global, so edits that add nodes or types renumber later
  declarations or change the type catalog and disable the gate; the symbol table
  is ordered by first use, so a new identifier spelling disables the gate. The
  under-100-ms target stays an unfinished gate for task 084.
- Durable record: [body interface cutoff](../zig-native/BODY_CUTOFF.md),
  [distributions](../zig-native/qualification/body-cutoff.csv) and
  [pins](../zig-native/qualification/body-cutoff-pins.json).

### Qualified owned-body slice — 12 October 2026

`46bf8b9` adds immutable leases and conservative replay with complete
closed-row, nominal/field and evidence receipts. The full native/914-guest
compiler gate, eight unchanged budgets and 348-file zero analyzer pass. Admitted
deep-body edit CPU falls about 29–30%; population/retained-memory costs and
cheap-body regressions remain explicit. Shared-callee and qualification
followups were isolated at that milestone. General forms, relocation and the
under-100-ms target keep this task open. See
[combined qualification](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md).

### Qualified shared/portable/annotation slice — 12 October2026

`2689ad5` adds bounded completed shared principals, original declared
qualification owners through source/compiled imports, independent body offers
after seed rebuild and complete applied-annotation/constructor recipe reads. The
joint full native/925-guest gate, eight unchanged budgets and349-file zero
analyzer pass. Unsupported blocks/cases and other forms, producer-unit ordinal
relocation and the total edit target stay open. Pinned isolated costs remain
distinct from mixed merged release costs.
See[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md)
and[the combined record](../zig-native/ROW_FUSION.md#integrated-qualification).

### Qualified guarded scopes and local principals —12 October2026

`850793f` fixes a confirmed retained dotted-access wrong result by declining
incomplete access-path metadata. It also admits owned ordinary block/case/
constructor scopes, predecessors/joins and unqualified local principals with
exact covariance rows. The joint native/936-guest gate, eight unchanged budgets
and350-file zero analyzer pass. Captured93-unit work still elaborates80 bodies;
no total edit gain is claimed. Explicit-field receipts are separately frozen;
compact access paths, requirements, relocation and the total target remain open.
See[BODY_CUTOFF](../zig-native/BODY_CUTOFF.md) and
[merged qualification](../zig-native/NUMERIC_SIMD.md).
